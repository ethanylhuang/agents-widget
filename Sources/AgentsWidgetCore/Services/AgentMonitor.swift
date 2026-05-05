import Combine
import Foundation

public protocol DateProviding: Sendable {
    func now() -> Date
}

public struct SystemDateProvider: DateProviding {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

@MainActor
public final class AgentMonitor: ObservableObject {
    @Published public private(set) var agents: [AgentSummary] = []
    @Published public private(set) var lastRefreshAt: Date?
    @Published public private(set) var lastRefreshDuration: TimeInterval?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var diagnostics: [String] = []
    @Published public private(set) var lastRefreshProfile: RefreshProfile?
    @Published public private(set) var attentionCount = 0

    private let worker: AgentRefreshWorker
    private let dateProvider: any DateProviding
    private let eventSource: (any AgentEventSourcing)?
    private let eventDebounceNanoseconds: UInt64
    private let menuOpenRefreshThrottleInterval: TimeInterval
    private let menuCloseGraceNanoseconds: UInt64
    private var eventDebounceTask: Task<Void, Never>?
    private var menuCloseTask: Task<Void, Never>?
    private var activeRefreshTask: Task<AgentRefreshResult, Never>?
    private var pendingRefreshScope: RefreshScope?
    private var pendingDebouncedScope: RefreshScope?
    private var processExitWatchers: [Int32: DispatchSourceProcess] = [:]
    private var previousStatusesByID: [String: AgentStatus] = [:]
    private var previousTerminalBackedIDs: Set<String> = []
    private var lastMenuOpenRefreshAt: Date?
    private var didStart = false
    private var isMenuVisible = false
    private var isEventSourceRunning = false

    public init(
        processProvider: any ProcessSnapshotProviding,
        codexStore: any CodexSessionStoring,
        openCodeStore: any OpenCodeSessionStoring,
        dateProvider: any DateProviding = SystemDateProvider(),
        detailRefreshInterval: TimeInterval = 10,
        eventSource: (any AgentEventSourcing)? = nil,
        eventDebounceNanoseconds: UInt64 = 250_000_000,
        menuTickIntervalNanoseconds: UInt64 = 2_000_000_000,
        menuOpenRefreshThrottleInterval: TimeInterval = 5,
        menuCloseGraceNanoseconds: UInt64 = 3_000_000_000
    ) {
        self.worker = AgentRefreshWorker(
            processProvider: processProvider,
            codexStore: codexStore,
            openCodeStore: openCodeStore,
            detailRefreshInterval: detailRefreshInterval
        )
        self.dateProvider = dateProvider
        self.eventSource = eventSource
        self.eventDebounceNanoseconds = eventDebounceNanoseconds
        self.menuOpenRefreshThrottleInterval = menuOpenRefreshThrottleInterval
        self.menuCloseGraceNanoseconds = menuCloseGraceNanoseconds
        _ = menuTickIntervalNanoseconds
    }

    public static func live() -> AgentMonitor {
        AgentMonitor(
            processProvider: ProcessSnapshotProvider(),
            codexStore: CodexSessionStore(),
            openCodeStore: OpenCodeSessionStore(),
            eventSource: LocalAgentEventSource()
        )
    }

    public func start() {
        guard !didStart else {
            return
        }
        didStart = true
    }

    public func stop() {
        didStart = false
        menuCloseTask?.cancel()
        menuCloseTask = nil
        stopEventSource()
        eventDebounceTask?.cancel()
        eventDebounceTask = nil
        pendingDebouncedScope = nil
        stopProcessExitWatchers()
    }

    public func setPollingInterval(_ seconds: UInt64) {
        _ = seconds
    }

    public func setMenuVisible(_ isVisible: Bool) {
        isMenuVisible = isVisible
        guard didStart else {
            return
        }
        if isVisible {
            menuCloseTask?.cancel()
            menuCloseTask = nil
            startEventSourceIfNeeded()
            requestMenuOpenRefreshIfAllowed()
        } else {
            scheduleHiddenTeardown()
        }
    }

    public func requestRefresh(force: Bool = false) {
        requestRefresh(scope: .full(
            forceDetails: force,
            mode: force ? .deep : .bounded,
            reason: force ? .manual : .menuOpen
        ))
    }

    public func warmCache() {
        requestRefresh(scope: .full(
            forceDetails: false,
            mode: .bounded,
            reason: .startup
        ))
    }

    private func requestProcessRefresh(reason: AgentRefreshReason) {
        requestRefresh(scope: .processOnly(reason: reason))
    }

    private func requestRefresh(scope: RefreshScope) {
        guard activeRefreshTask == nil else {
            pendingRefreshScope = pendingRefreshScope?.merged(with: scope) ?? scope
            return
        }

        isRefreshing = true
        let now = dateProvider.now()
        let refreshWorker = worker
        let task = Task.detached(priority: .utility) {
            switch scope {
            case .full(let forceDetails, let mode, let reason):
                await refreshWorker.refresh(now: now, forceDetails: forceDetails, mode: mode, reason: reason)
            case .processOnly(let reason):
                await refreshWorker.refreshProcesses(now: now, reason: reason)
            }
        }
        activeRefreshTask = task

        Task { [weak self] in
            let result = await task.value
            self?.completeRefresh(result)
        }
    }

    public func refresh() async {
        guard activeRefreshTask == nil else {
            let scope = RefreshScope.full(forceDetails: true, mode: .deep, reason: .manual)
            pendingRefreshScope = pendingRefreshScope?.merged(with: scope) ?? scope
            return
        }

        isRefreshing = true
        let result = await worker.refresh(now: dateProvider.now(), forceDetails: true, mode: .deep, reason: .manual)
        completeRefresh(result)
    }

    private func completeRefresh(_ result: AgentRefreshResult) {
        let withAttention = Self.applyAttention(
            to: result.agents,
            previousStatuses: previousStatusesByID,
            previousTerminalBackedIDs: previousTerminalBackedIDs
        )
        let sortedAgents = Self.sortedAgents(withAttention)
        agents = sortedAgents
        attentionCount = sortedAgents.filter(\.needsAttention).count
        diagnostics = result.diagnostics
        lastRefreshAt = result.refreshedAt
        lastRefreshDuration = result.duration
        lastRefreshProfile = result.profile
        activeRefreshTask = nil
        previousStatusesByID = Dictionary(uniqueKeysWithValues: sortedAgents.map { ($0.id, $0.status) })
        previousTerminalBackedIDs = Set(sortedAgents.filter(\.isTerminalBacked).map(\.id))
        updateProcessExitWatchers(for: sortedAgents)

        if let pendingRefreshScope {
            self.pendingRefreshScope = nil
            requestRefresh(scope: pendingRefreshScope)
        } else {
            isRefreshing = false
        }
    }

    private func requestMenuOpenRefreshIfAllowed() {
        let now = dateProvider.now()
        if let lastMenuOpenRefreshAt,
           now.timeIntervalSince(lastMenuOpenRefreshAt) < menuOpenRefreshThrottleInterval {
            return
        }
        lastMenuOpenRefreshAt = now
        requestRefresh(scope: .full(forceDetails: false, mode: .bounded, reason: .menuOpen))
    }

    func handleEvent(_ trigger: AgentRefreshTrigger) {
        guard didStart, isMenuVisible else {
            return
        }
        let scope = RefreshScope(trigger: trigger)
        pendingDebouncedScope = pendingDebouncedScope?.merged(with: scope) ?? scope
        eventDebounceTask?.cancel()
        eventDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.eventDebounceNanoseconds ?? 250_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard let self else {
                    return
                }
                guard let scope = self.pendingDebouncedScope else {
                    return
                }
                self.pendingDebouncedScope = nil
                self.requestRefresh(scope: scope)
            }
        }
    }

    private func startEventSourceIfNeeded() {
        guard !isEventSourceRunning else {
            return
        }
        eventSource?.start { [weak self] trigger in
            Task { @MainActor [weak self] in
                self?.handleEvent(trigger)
            }
        }
        isEventSourceRunning = eventSource != nil
    }

    private func stopEventSource() {
        guard isEventSourceRunning else {
            return
        }
        eventSource?.stop()
        isEventSourceRunning = false
    }

    private func scheduleHiddenTeardown() {
        eventDebounceTask?.cancel()
        eventDebounceTask = nil
        pendingDebouncedScope = nil
        menuCloseTask?.cancel()

        guard menuCloseGraceNanoseconds > 0 else {
            stopEventSource()
            stopProcessExitWatchers()
            return
        }

        let delay = menuCloseGraceNanoseconds
        menuCloseTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            await MainActor.run {
                guard let self, !self.isMenuVisible else {
                    return
                }
                self.menuCloseTask = nil
                self.stopEventSource()
                self.stopProcessExitWatchers()
            }
        }
    }

    private func updateProcessExitWatchers(for agents: [AgentSummary]) {
        guard isMenuVisible else {
            stopProcessExitWatchers()
            return
        }
        let activePIDs = Set(agents.compactMap(\.pid))
        for (pid, watcher) in processExitWatchers where !activePIDs.contains(pid) {
            watcher.cancel()
            processExitWatchers[pid] = nil
        }

        for pid in activePIDs where processExitWatchers[pid] == nil {
            let watcher = DispatchSource.makeProcessSource(
                identifier: pid_t(pid),
                eventMask: .exit,
                queue: .main
            )
            watcher.setEventHandler { [weak self] in
                self?.handleEvent(.processExited(pid))
            }
            processExitWatchers[pid] = watcher
            watcher.resume()
        }
    }

    private func stopProcessExitWatchers() {
        for watcher in processExitWatchers.values {
            watcher.cancel()
        }
        processExitWatchers = [:]
    }

    public func merge(
        processes: [ProcessSnapshot],
        codex: [AgentSummary],
        openCode: [AgentSummary],
        now: Date? = nil
    ) -> [AgentSummary] {
        Self.merge(processes: processes, sessions: codex + openCode, now: now ?? dateProvider.now())
    }

    public nonisolated static func merge(processes: [ProcessSnapshot], sessions: [AgentSummary], now: Date) -> [AgentSummary] {
        let classifier = AgentStatusClassifier()
        var unmatchedSessions = sessions
        var merged: [AgentSummary] = []

        for process in processes {
            let matchIndex = bestMatchIndex(for: process, sessions: unmatchedSessions)
            if let matchIndex {
                var summary = unmatchedSessions.remove(at: matchIndex)
                apply(process: process, to: &summary, now: now, classifier: classifier)
                merged.append(summary)
            } else {
                merged.append(summary(for: process, now: now, classifier: classifier))
            }
        }

        for session in unmatchedSessions {
            var summary = session
            summary.status = classifier.classify(summary, hasLiveProcess: false, hasMatchedSession: true, now: now)
            summary.runtimeSeconds = runtime(startedAt: summary.startedAt, now: now)
            summary.idleSeconds = idle(lastActivityAt: summary.lastActivityAt, now: now)
            merged.append(summary)
        }

        return sortedAgents(merged)
    }

    nonisolated static func bestMatchIndex(for process: ProcessSnapshot, sessions: [AgentSummary]) -> Int? {
        let providerMatches = sessions.indices.filter { sessions[$0].provider == process.provider }
        if let cwd = process.cwd,
           let exact = providerMatches.first(where: { sessions[$0].cwd == cwd }) {
            return exact
        }
        if let startedAt = process.startedAt {
            return providerMatches.min { lhs, rhs in
                let leftDate = sessions[lhs].lastActivityAt ?? sessions[lhs].startedAt ?? .distantPast
                let rightDate = sessions[rhs].lastActivityAt ?? sessions[rhs].startedAt ?? .distantPast
                return abs(leftDate.timeIntervalSince(startedAt)) < abs(rightDate.timeIntervalSince(startedAt))
            }
        }
        return providerMatches.max { lhs, rhs in
            (sessions[lhs].lastActivityAt ?? .distantPast) < (sessions[rhs].lastActivityAt ?? .distantPast)
        }
    }

    nonisolated static func apply(
        process: ProcessSnapshot,
        to summary: inout AgentSummary,
        now: Date,
        classifier: AgentStatusClassifier = AgentStatusClassifier()
    ) {
        summary.pid = process.pid
        summary.tty = process.tty
        summary.cwd = summary.cwd ?? process.cwd
        summary.startedAt = process.startedAt ?? summary.startedAt
        summary.runtimeSeconds = runtime(startedAt: summary.startedAt, now: now)
        summary.idleSeconds = idle(lastActivityAt: summary.lastActivityAt, now: now)
        if let tty = process.tty {
            summary.terminalTarget = TerminalTarget(tty: tty, pid: process.pid)
        }
        summary.status = classifier.classify(summary, hasLiveProcess: true, hasMatchedSession: true, now: now)
    }

    nonisolated static func summary(
        for process: ProcessSnapshot,
        now: Date,
        classifier: AgentStatusClassifier = AgentStatusClassifier()
    ) -> AgentSummary {
        var summary = AgentSummary(
            id: "\(process.provider.rawValue)-pid-\(process.pid)",
            provider: process.provider,
            title: "\(process.provider.displayName) PID \(process.pid)",
            cwd: process.cwd,
            pid: process.pid,
            tty: process.tty,
            status: .unknown,
            startedAt: process.startedAt,
            lastActivityAt: process.startedAt,
            runtimeSeconds: runtime(startedAt: process.startedAt, now: now),
            idleSeconds: idle(lastActivityAt: process.startedAt, now: now)
        )
        if let tty = process.tty {
            summary.terminalTarget = TerminalTarget(tty: tty, pid: process.pid)
        }
        summary.status = classifier.classify(summary, hasLiveProcess: true, hasMatchedSession: false, now: now)
        return summary
    }

    nonisolated static func runtime(startedAt: Date?, now: Date) -> TimeInterval? {
        startedAt.map { max(0, now.timeIntervalSince($0)) }
    }

    nonisolated static func idle(lastActivityAt: Date?, now: Date) -> TimeInterval? {
        lastActivityAt.map { max(0, now.timeIntervalSince($0)) }
    }

    nonisolated static func statusRank(_ status: AgentStatus) -> Int {
        switch status {
        case .stuck:
            0
        case .running:
            1
        case .idle:
            2
        case .error:
            3
        case .complete:
            4
        case .unknown:
            5
        }
    }

    public nonisolated static func filteredAgents(_ agents: [AgentSummary], filter: AgentListFilter) -> [AgentSummary] {
        switch filter {
        case .activeTerminal:
            agents.filter(\.isTerminalBacked)
        case .allTasks:
            agents
        }
    }

    public nonisolated static func applyAttention(
        to agents: [AgentSummary],
        previousStatuses: [String: AgentStatus],
        previousTerminalBackedIDs: Set<String>
    ) -> [AgentSummary] {
        agents.map { agent in
            var updated = agent
            updated.attentionReasons = attentionReasons(
                for: agent,
                previousStatus: previousStatuses[agent.id],
                wasTerminalBacked: previousTerminalBackedIDs.contains(agent.id)
            )
            return updated
        }
    }

    public nonisolated static func attentionReasons(
        for agent: AgentSummary,
        previousStatus: AgentStatus?,
        wasTerminalBacked: Bool
    ) -> [AgentAttentionReason] {
        var reasons: [AgentAttentionReason] = []
        if agent.isTerminalBacked {
            if agent.status == .stuck {
                reasons.append(.stuck)
            }
            if agent.status == .error {
                reasons.append(.error)
            }
        }
        if agent.status == .complete,
           [.running, .idle, .stuck].contains(previousStatus) || wasTerminalBacked {
            reasons.append(.completed)
        }
        if agent.isTerminalBacked,
           agent.status == .idle,
           agent.statusEvidence?.openActivityKind == nil {
            reasons.append(.inputNeeded)
        }
        return reasons
    }

    public nonisolated static func sortedAgents(_ agents: [AgentSummary]) -> [AgentSummary] {
        agents.sorted { lhs, rhs in
            if lhs.needsAttention != rhs.needsAttention {
                return lhs.needsAttention
            }
            let leftRank = statusRank(lhs.status)
            let rightRank = statusRank(rhs.status)
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            return (lhs.lastActivityAt ?? .distantPast) > (rhs.lastActivityAt ?? .distantPast)
        }
    }
}

private enum RefreshScope: Equatable {
    case full(forceDetails: Bool, mode: SessionRefreshMode, reason: AgentRefreshReason)
    case processOnly(reason: AgentRefreshReason)

    init(trigger: AgentRefreshTrigger) {
        switch trigger {
        case .codexSessionsChanged, .openCodeDatabaseChanged:
            self = .full(forceDetails: false, mode: .bounded, reason: .providerDirty)
        case .processExited:
            self = .processOnly(reason: .processExit)
        }
    }

    func merged(with other: RefreshScope) -> RefreshScope {
        switch (self, other) {
        case (.full(let lhsForce, let lhsMode, let lhsReason), .full(let rhsForce, let rhsMode, let rhsReason)):
            .full(
                forceDetails: lhsForce || rhsForce,
                mode: lhsMode == .deep || rhsMode == .deep ? .deep : .bounded,
                reason: Self.mergedReason(lhsReason, rhsReason)
            )
        case (.full(let force, let mode, let reason), .processOnly(let processReason)),
             (.processOnly(let processReason), .full(let force, let mode, let reason)):
            .full(forceDetails: force, mode: mode, reason: Self.mergedReason(reason, processReason))
        case (.processOnly(let lhsReason), .processOnly(let rhsReason)):
            .processOnly(reason: Self.mergedReason(lhsReason, rhsReason))
        }
    }

    private static func mergedReason(_ lhs: AgentRefreshReason, _ rhs: AgentRefreshReason) -> AgentRefreshReason {
        let priority: [AgentRefreshReason] = [
            .manual,
            .providerDirty,
            .menuOpen,
            .backgroundMaintenance,
            .startup,
            .processExit
        ]
        return priority.first { $0 == lhs || $0 == rhs } ?? lhs
    }
}
