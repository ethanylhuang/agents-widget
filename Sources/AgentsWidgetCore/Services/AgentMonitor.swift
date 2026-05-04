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

    private let worker: AgentRefreshWorker
    private let dateProvider: any DateProviding
    private var pollingTask: Task<Void, Never>?
    private var activeRefreshTask: Task<AgentRefreshResult, Never>?
    private var pendingRefresh = false
    private var pendingForceDetails = false
    private var pollingIntervalSeconds: UInt64 = 10

    public init(
        processProvider: any ProcessSnapshotProviding,
        codexStore: any CodexSessionStoring,
        openCodeStore: any OpenCodeSessionStoring,
        dateProvider: any DateProviding = SystemDateProvider(),
        detailRefreshInterval: TimeInterval = 10
    ) {
        self.worker = AgentRefreshWorker(
            processProvider: processProvider,
            codexStore: codexStore,
            openCodeStore: openCodeStore,
            detailRefreshInterval: detailRefreshInterval
        )
        self.dateProvider = dateProvider
    }

    public static func live() -> AgentMonitor {
        AgentMonitor(
            processProvider: ProcessSnapshotProvider(),
            codexStore: CodexSessionStore(),
            openCodeStore: OpenCodeSessionStore()
        )
    }

    public func start() {
        guard pollingTask == nil else {
            return
        }
        requestRefresh()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                let seconds = self?.pollingIntervalSeconds ?? 10
                try? await Task.sleep(for: .seconds(seconds))
                self?.requestRefresh()
            }
        }
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    public func setPollingInterval(_ seconds: UInt64) {
        pollingIntervalSeconds = seconds
    }

    public func setMenuVisible(_ isVisible: Bool) {
        pollingIntervalSeconds = isVisible ? 2 : 10
    }

    public func requestRefresh(force: Bool = false) {
        guard activeRefreshTask == nil else {
            pendingRefresh = true
            pendingForceDetails = pendingForceDetails || force
            return
        }

        isRefreshing = true
        let now = dateProvider.now()
        let refreshWorker = worker
        let task = Task.detached(priority: .utility) {
            await refreshWorker.refresh(now: now, forceDetails: force)
        }
        activeRefreshTask = task

        Task { [weak self] in
            let result = await task.value
            self?.completeRefresh(result)
        }
    }

    public func refresh() async {
        guard activeRefreshTask == nil else {
            pendingRefresh = true
            pendingForceDetails = true
            return
        }

        isRefreshing = true
        let result = await worker.refresh(now: dateProvider.now(), forceDetails: true)
        completeRefresh(result)
    }

    private func completeRefresh(_ result: AgentRefreshResult) {
        agents = result.agents
        diagnostics = result.diagnostics
        lastRefreshAt = result.refreshedAt
        lastRefreshDuration = result.duration
        activeRefreshTask = nil

        if pendingRefresh {
            let forceDetails = pendingForceDetails
            pendingRefresh = false
            pendingForceDetails = false
            requestRefresh(force: forceDetails)
        } else {
            isRefreshing = false
        }
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
        var unmatchedSessions = sessions
        var merged: [AgentSummary] = []

        for process in processes {
            let matchIndex = bestMatchIndex(for: process, sessions: unmatchedSessions)
            if let matchIndex {
                var summary = unmatchedSessions.remove(at: matchIndex)
                apply(process: process, to: &summary, now: now)
                merged.append(summary)
            } else {
                merged.append(summary(for: process, now: now))
            }
        }

        for session in unmatchedSessions {
            var summary = session
            summary.status = status(for: summary, hasProcess: false, now: now)
            summary.runtimeSeconds = runtime(startedAt: summary.startedAt, now: now)
            summary.idleSeconds = idle(lastActivityAt: summary.lastActivityAt, now: now)
            merged.append(summary)
        }

        return merged.sorted { lhs, rhs in
            let leftRank = statusRank(lhs.status)
            let rightRank = statusRank(rhs.status)
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            return (lhs.lastActivityAt ?? .distantPast) > (rhs.lastActivityAt ?? .distantPast)
        }
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

    nonisolated static func apply(process: ProcessSnapshot, to summary: inout AgentSummary, now: Date) {
        summary.pid = process.pid
        summary.tty = process.tty
        summary.cwd = summary.cwd ?? process.cwd
        summary.startedAt = process.startedAt ?? summary.startedAt
        summary.runtimeSeconds = runtime(startedAt: summary.startedAt, now: now)
        summary.idleSeconds = idle(lastActivityAt: summary.lastActivityAt, now: now)
        if let tty = process.tty {
            summary.terminalTarget = TerminalTarget(tty: tty, pid: process.pid)
        }
        summary.status = status(for: summary, hasProcess: true, now: now)
    }

    nonisolated static func summary(for process: ProcessSnapshot, now: Date) -> AgentSummary {
        var summary = AgentSummary(
            id: "\(process.provider.rawValue)-pid-\(process.pid)",
            provider: process.provider,
            title: "\(process.provider.displayName) PID \(process.pid)",
            cwd: process.cwd,
            pid: process.pid,
            tty: process.tty,
            status: .running,
            startedAt: process.startedAt,
            lastActivityAt: process.startedAt,
            runtimeSeconds: runtime(startedAt: process.startedAt, now: now),
            idleSeconds: idle(lastActivityAt: process.startedAt, now: now)
        )
        if let tty = process.tty {
            summary.terminalTarget = TerminalTarget(tty: tty, pid: process.pid)
        }
        summary.status = status(for: summary, hasProcess: true, now: now)
        return summary
    }

    nonisolated static func status(for summary: AgentSummary, hasProcess: Bool, now: Date) -> AgentStatus {
        if hasProcess,
           let tool = summary.activeTool,
           tool.isIncomplete,
           (tool.ageSeconds ?? tool.startedAt.map { now.timeIntervalSince($0) } ?? 0) >= 90 {
            return .stuck
        }
        if hasProcess {
            let idleSeconds = idle(lastActivityAt: summary.lastActivityAt ?? summary.startedAt, now: now) ?? .greatestFiniteMagnitude
            return idleSeconds < 120 ? .running : .idle
        }
        if summary.status == .error {
            return .error
        }
        if summary.status == .complete {
            return .complete
        }
        return .unknown
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
}
