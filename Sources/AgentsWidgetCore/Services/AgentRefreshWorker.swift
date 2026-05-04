import Foundation

public struct AgentRefreshResult: Sendable {
    public var agents: [AgentSummary]
    public var diagnostics: [String]
    public var refreshedAt: Date
    public var duration: TimeInterval

    public init(
        agents: [AgentSummary],
        diagnostics: [String],
        refreshedAt: Date,
        duration: TimeInterval
    ) {
        self.agents = agents
        self.diagnostics = diagnostics
        self.refreshedAt = refreshedAt
        self.duration = duration
    }
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

    public func refresh(now: Date, forceDetails: Bool) -> AgentRefreshResult {
        let startedAt = Date()
        let processes = processProvider.snapshots()
        let details = sessionDetails(now: now, force: forceDetails)
        let merged = AgentMonitor.merge(
            processes: processes.value,
            sessions: details.codex.value + details.openCode.value,
            now: now
        )
        return AgentRefreshResult(
            agents: merged,
            diagnostics: processes.diagnostics + details.codex.diagnostics + details.openCode.diagnostics,
            refreshedAt: now,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    private func sessionDetails(
        now: Date,
        force: Bool
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

        let codex = codexStore.summaries(now: now)
        let openCode = openCodeStore.summaries(now: now)
        cachedCodex = codex
        cachedOpenCode = openCode
        lastDetailRefreshAt = now
        return (codex, openCode)
    }
}
