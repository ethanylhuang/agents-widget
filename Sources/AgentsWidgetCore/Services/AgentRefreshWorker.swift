import Darwin
import Foundation

public enum AgentRefreshReason: String, Codable, Equatable, Sendable {
    case startup
    case menuOpen
    case manual
    case providerDirty
    case processExit
    case backgroundMaintenance
}

public enum SessionRefreshMode: String, Codable, Equatable, Sendable {
    case bounded
    case deep
}

public struct RefreshProfile: Codable, Equatable, Sendable {
    public var reason: AgentRefreshReason
    public var wallTimeSeconds: TimeInterval
    public var cpuTimeSeconds: TimeInterval
    public var bytesRead: Int64
    public var filesParsed: Int
    public var sqliteQueries: Int
    public var processSyscalls: Int

    public init(
        reason: AgentRefreshReason,
        wallTimeSeconds: TimeInterval,
        cpuTimeSeconds: TimeInterval,
        metrics: ProviderMetrics
    ) {
        self.reason = reason
        self.wallTimeSeconds = wallTimeSeconds
        self.cpuTimeSeconds = cpuTimeSeconds
        self.bytesRead = metrics.bytesRead
        self.filesParsed = metrics.filesParsed
        self.sqliteQueries = metrics.sqliteQueries
        self.processSyscalls = metrics.processSyscalls
    }
}

public struct AgentRefreshResult: Sendable {
    public var agents: [AgentSummary]
    public var diagnostics: [String]
    public var refreshedAt: Date
    public var duration: TimeInterval
    public var profile: RefreshProfile

    public init(
        agents: [AgentSummary],
        diagnostics: [String],
        refreshedAt: Date,
        duration: TimeInterval,
        profile: RefreshProfile
    ) {
        self.agents = agents
        self.diagnostics = diagnostics
        self.refreshedAt = refreshedAt
        self.duration = duration
        self.profile = profile
    }
}

public protocol ModeAwareCodexSessionStoring: CodexSessionStoring {
    func summaries(now: Date, mode: SessionRefreshMode) -> ProviderResult<[AgentSummary]>
}

public protocol ModeAwareOpenCodeSessionStoring: OpenCodeSessionStoring {
    func summaries(now: Date, mode: SessionRefreshMode) -> ProviderResult<[AgentSummary]>
}

public actor AgentRefreshWorker {
    private let processProvider: any ProcessSnapshotProviding
    private let codexStore: any CodexSessionStoring
    private let openCodeStore: any OpenCodeSessionStoring
    private let detailRefreshInterval: TimeInterval
    private var cachedCodex: ProviderResult<[AgentSummary]>?
    private var cachedOpenCode: ProviderResult<[AgentSummary]>?
    private var lastDetailRefreshAt: Date?

    public init(
        processProvider: any ProcessSnapshotProviding,
        codexStore: any CodexSessionStoring,
        openCodeStore: any OpenCodeSessionStoring,
        detailRefreshInterval: TimeInterval = 10
    ) {
        self.processProvider = processProvider
        self.codexStore = codexStore
        self.openCodeStore = openCodeStore
        self.detailRefreshInterval = detailRefreshInterval
    }

    public func refresh(
        now: Date,
        forceDetails: Bool,
        mode: SessionRefreshMode = .bounded,
        reason: AgentRefreshReason = .manual
    ) -> AgentRefreshResult {
        let startedAt = Date()
        let startedCPU = Self.currentCPUTime()
        let processes = processProvider.snapshots()
        let details = sessionDetails(now: now, force: forceDetails, mode: mode)
        let merged = merge(processes: processes.value, details: details, now: now)
        var metrics = processes.metrics
        metrics.merge(details.codex.metrics)
        metrics.merge(details.openCode.metrics)
        let duration = Date().timeIntervalSince(startedAt)
        return AgentRefreshResult(
            agents: merged,
            diagnostics: processes.diagnostics + details.codex.diagnostics + details.openCode.diagnostics,
            refreshedAt: now,
            duration: duration,
            profile: RefreshProfile(
                reason: reason,
                wallTimeSeconds: duration,
                cpuTimeSeconds: max(0, Self.currentCPUTime() - startedCPU),
                metrics: metrics
            )
        )
    }

    public func refreshProcesses(
        now: Date,
        reason: AgentRefreshReason = .processExit
    ) -> AgentRefreshResult {
        let startedAt = Date()
        let startedCPU = Self.currentCPUTime()
        let processes = processProvider.snapshots()
        let details = cachedSessionDetails(now: now)
        let merged = merge(processes: processes.value, details: details, now: now)
        let duration = Date().timeIntervalSince(startedAt)
        return AgentRefreshResult(
            agents: merged,
            diagnostics: processes.diagnostics + details.codex.diagnostics + details.openCode.diagnostics,
            refreshedAt: now,
            duration: duration,
            profile: RefreshProfile(
                reason: reason,
                wallTimeSeconds: duration,
                cpuTimeSeconds: max(0, Self.currentCPUTime() - startedCPU),
                metrics: processes.metrics
            )
        )
    }

    private func sessionDetails(
        now: Date,
        force: Bool,
        mode: SessionRefreshMode
    ) -> (codex: ProviderResult<[AgentSummary]>, openCode: ProviderResult<[AgentSummary]>) {
        let shouldRefreshDetails = force
            || cachedCodex == nil
            || cachedOpenCode == nil
            || lastDetailRefreshAt.map { now.timeIntervalSince($0) >= detailRefreshInterval } != false

        guard shouldRefreshDetails else {
            return (
                cachedCodex ?? ProviderResult(value: []),
                cachedOpenCode ?? ProviderResult(value: [])
            )
        }

        let codex: ProviderResult<[AgentSummary]>
        if let store = codexStore as? any ModeAwareCodexSessionStoring {
            codex = store.summaries(now: now, mode: mode)
        } else {
            codex = codexStore.summaries(now: now)
        }

        let openCode: ProviderResult<[AgentSummary]>
        if let store = openCodeStore as? any ModeAwareOpenCodeSessionStoring {
            openCode = store.summaries(now: now, mode: mode)
        } else {
            openCode = openCodeStore.summaries(now: now)
        }
        cachedCodex = codex
        cachedOpenCode = openCode
        lastDetailRefreshAt = now
        return (codex, openCode)
    }

    private func cachedSessionDetails(
        now: Date
    ) -> (codex: ProviderResult<[AgentSummary]>, openCode: ProviderResult<[AgentSummary]>) {
        (
            cachedCodex?.refreshedDynamicFields(now: now) ?? ProviderResult(value: []),
            cachedOpenCode?.refreshedDynamicFields(now: now) ?? ProviderResult(value: [])
        )
    }

    private static func currentCPUTime() -> TimeInterval {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else {
            return 0
        }
        let user = TimeInterval(usage.ru_utime.tv_sec) + TimeInterval(usage.ru_utime.tv_usec) / 1_000_000
        let system = TimeInterval(usage.ru_stime.tv_sec) + TimeInterval(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    private func merge(
        processes: [ProcessSnapshot],
        details: (codex: ProviderResult<[AgentSummary]>, openCode: ProviderResult<[AgentSummary]>),
        now: Date
    ) -> [AgentSummary] {
        AgentMonitor.merge(
            processes: processes,
            sessions: details.codex.value + details.openCode.value,
            now: now
        )
    }
}

extension ProviderResult where Value == [AgentSummary] {
    func refreshedDynamicFields(now: Date) -> ProviderResult<[AgentSummary]> {
        ProviderResult(value: value.map { $0.refreshedDynamicFields(now: now) }, diagnostics: diagnostics)
    }
}
