import XCTest
@testable import AgentsWidgetCore

final class AgentRefreshWorkerTests: XCTestCase {
    func testRefreshesProcessesEveryTimeAndSessionDetailsOnSlowCadence() async {
        let processProvider = CountingProcessProvider()
        let codexStore = CountingCodexStore(provider: .codex)
        let openCodeStore = CountingOpenCodeStore(provider: .opencode)
        let worker = AgentRefreshWorker(
            processProvider: processProvider,
            codexStore: codexStore,
            openCodeStore: openCodeStore,
            detailRefreshInterval: 60
        )
        let now = Date(timeIntervalSince1970: 1_000)

        _ = await worker.refresh(now: now, forceDetails: false)
        _ = await worker.refresh(now: now.addingTimeInterval(1), forceDetails: false)

        XCTAssertEqual(processProvider.callCount, 2)
        XCTAssertEqual(codexStore.callCount, 1)
        XCTAssertEqual(openCodeStore.callCount, 1)

        _ = await worker.refresh(now: now.addingTimeInterval(2), forceDetails: true)

        XCTAssertEqual(processProvider.callCount, 3)
        XCTAssertEqual(codexStore.callCount, 2)
        XCTAssertEqual(openCodeStore.callCount, 2)
    }
}

private final class CountingProcessProvider: ProcessSnapshotProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _callCount
    }

    func snapshots() -> ProviderResult<[ProcessSnapshot]> {
        lock.lock()
        _callCount += 1
        lock.unlock()
        return ProviderResult(value: [])
    }
}

private final class CountingCodexStore: CodexSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    private let provider: AgentProvider

    init(provider: AgentProvider) {
        self.provider = provider
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _callCount
    }

    func summaries(now: Date) -> ProviderResult<[AgentSummary]> {
        lock.lock()
        _callCount += 1
        lock.unlock()
        return ProviderResult(value: [
            AgentSummary(id: "\(provider.rawValue)-summary", provider: provider, title: provider.displayName)
        ])
    }
}

private final class CountingOpenCodeStore: OpenCodeSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    private let provider: AgentProvider

    init(provider: AgentProvider) {
        self.provider = provider
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _callCount
    }

    func summaries(now: Date) -> ProviderResult<[AgentSummary]> {
        lock.lock()
        _callCount += 1
        lock.unlock()
        return ProviderResult(value: [
            AgentSummary(id: "\(provider.rawValue)-summary", provider: provider, title: provider.displayName)
        ])
    }
}
