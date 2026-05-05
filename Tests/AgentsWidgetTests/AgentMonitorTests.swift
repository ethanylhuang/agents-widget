import XCTest
@testable import AgentsWidgetCore

final class AgentMonitorTests: XCTestCase {
    @MainActor
    func testRequestRefreshReturnsImmediatelyWhenProviderBlocks() async throws {
        let processProvider = BlockingProcessProvider()
        let monitor = AgentMonitor(
            processProvider: processProvider,
            codexStore: EmptyCodexStore(),
            openCodeStore: EmptyOpenCodeStore()
        )

        let startedAt = Date()
        monitor.requestRefresh(force: true)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(elapsed, 0.1)
        XCTAssertTrue(monitor.isRefreshing)
        XCTAssertTrue(processProvider.waitUntilEntered(timeout: 1))

        processProvider.release()
        try await waitForMainActorCondition(timeout: 1) {
            !monitor.isRefreshing
        }
        XCTAssertEqual(processProvider.callCount, 1)
        XCTAssertNotNil(monitor.lastRefreshAt)
    }

    @MainActor
    func testOverlappingRefreshRequestsCoalesce() async throws {
        let processProvider = BlockingProcessProvider()
        let monitor = AgentMonitor(
            processProvider: processProvider,
            codexStore: EmptyCodexStore(),
            openCodeStore: EmptyOpenCodeStore()
        )

        monitor.requestRefresh()
        XCTAssertTrue(processProvider.waitUntilEntered(timeout: 1))
        monitor.requestRefresh()
        monitor.requestRefresh(force: true)
        monitor.requestRefresh()
        XCTAssertEqual(processProvider.callCount, 1)

        processProvider.release()
        try await waitForMainActorCondition(timeout: 1) {
            processProvider.callCount == 2
        }
        XCTAssertEqual(processProvider.callCount, 2)

        processProvider.release()
        try await waitForMainActorCondition(timeout: 1) {
            !monitor.isRefreshing
        }
        XCTAssertEqual(processProvider.callCount, 2)
    }

    func testMergesExactCWDProcessAndSession() {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = AgentSummary(
            id: "session-1",
            provider: .codex,
            title: "Task",
            cwd: "/tmp/agents-widget",
            status: .running,
            startedAt: now.addingTimeInterval(-30),
            lastActivityAt: now.addingTimeInterval(-10),
            statusEvidence: AgentStatusEvidence(
                lastAssistantOrToolActivityAt: now.addingTimeInterval(-10)
            )
        )
        let process = ProcessSnapshot(
            pid: 123,
            parentPid: 1,
            provider: .codex,
            tty: "/dev/ttys000",
            startedAt: now.addingTimeInterval(-30),
            command: "codex",
            cwd: "/tmp/agents-widget"
        )

        let merged = AgentMonitor.merge(processes: [process], sessions: [session], now: now)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].pid, 123)
        XCTAssertEqual(merged[0].status, .running)
        XCTAssertEqual(merged[0].terminalTarget?.tty, "/dev/ttys000")
    }

    func testLeavesUnmatchedProcessVisible() {
        let now = Date(timeIntervalSince1970: 1_000)
        let process = ProcessSnapshot(
            pid: 456,
            parentPid: 1,
            provider: .opencode,
            tty: nil,
            startedAt: now.addingTimeInterval(-200),
            command: "opencode",
            cwd: nil
        )

        let merged = AgentMonitor.merge(processes: [process], sessions: [], now: now)

        XCTAssertEqual(merged.first?.title, "OpenCode PID 456")
        XCTAssertEqual(merged.first?.status, .unknown)
    }

    func testFinishedSessionWithLiveProcessIsIdle() {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = AgentSummary(
            id: "session-1",
            provider: .codex,
            title: "Task",
            cwd: "/tmp/agents-widget",
            status: .complete,
            startedAt: now.addingTimeInterval(-200),
            lastActivityAt: now.addingTimeInterval(-5)
        )
        let process = ProcessSnapshot(
            pid: 123,
            parentPid: 1,
            provider: .codex,
            tty: "/dev/ttys000",
            startedAt: now.addingTimeInterval(-200),
            command: "codex",
            cwd: "/tmp/agents-widget"
        )

        let merged = AgentMonitor.merge(processes: [process], sessions: [session], now: now)

        XCTAssertEqual(merged.first?.status, .idle)
    }

    func testFinishedSessionWithoutProcessIsComplete() {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = AgentSummary(
            id: "session-1",
            provider: .opencode,
            title: "Task",
            status: .complete,
            startedAt: now.addingTimeInterval(-200),
            lastActivityAt: now.addingTimeInterval(-5)
        )

        let merged = AgentMonitor.merge(processes: [], sessions: [session], now: now)

        XCTAssertEqual(merged.first?.status, .complete)
    }

    func testLiveProcessOverridesStaleSessionError() {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = AgentSummary(
            id: "session-1",
            provider: .codex,
            title: "Task",
            cwd: "/tmp/agents-widget",
            status: .error,
            startedAt: now.addingTimeInterval(-300),
            lastActivityAt: now.addingTimeInterval(-10),
            statusEvidence: AgentStatusEvidence(
                providerTerminalState: .error,
                lastAssistantOrToolActivityAt: now.addingTimeInterval(-2)
            )
        )
        let process = ProcessSnapshot(
            pid: 123,
            parentPid: 1,
            provider: .codex,
            tty: "/dev/ttys000",
            startedAt: now.addingTimeInterval(-300),
            command: "codex",
            cwd: "/tmp/agents-widget"
        )

        let merged = AgentMonitor.merge(processes: [process], sessions: [session], now: now)

        XCTAssertEqual(merged.first?.status, .running)
        XCTAssertEqual(merged.first?.pid, 123)
        XCTAssertEqual(merged.first?.terminalTarget?.tty, "/dev/ttys000")
    }

    func testLiveMatchedSessionWithoutFreshEvidenceIsIdle() {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = AgentSummary(
            id: "session-1",
            provider: .codex,
            title: "Long task",
            cwd: "/tmp/long-task",
            startedAt: now.addingTimeInterval(-3_600),
            lastActivityAt: now.addingTimeInterval(-600)
        )
        let process = ProcessSnapshot(
            pid: 123,
            parentPid: 1,
            provider: .codex,
            tty: "/dev/ttys004",
            startedAt: now.addingTimeInterval(-3_600),
            command: "codex",
            cwd: "/tmp/long-task"
        )

        let merged = AgentMonitor.merge(processes: [process], sessions: [session], now: now)

        XCTAssertEqual(merged.first?.status, .idle)
    }

    func testActiveProviderEvidenceWithLiveProcessIsRunning() {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = AgentSummary(
            id: "session-1",
            provider: .opencode,
            title: "Task",
            cwd: "/tmp/agents-widget",
            status: .running,
            startedAt: now.addingTimeInterval(-200),
            lastActivityAt: now.addingTimeInterval(-10),
            statusEvidence: AgentStatusEvidence(
                lastAssistantOrToolActivityAt: now.addingTimeInterval(-10)
            )
        )
        let process = ProcessSnapshot(
            pid: 123,
            parentPid: 1,
            provider: .opencode,
            tty: "/dev/ttys000",
            startedAt: now.addingTimeInterval(-200),
            command: "opencode",
            cwd: "/tmp/agents-widget"
        )

        let merged = AgentMonitor.merge(processes: [process], sessions: [session], now: now)

        XCTAssertEqual(merged.first?.status, .running)
    }

    func testStatusPriorityMakesStaleToolStuck() {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = AgentSummary(
            id: "session-1",
            provider: .codex,
            title: "Task",
            cwd: "/tmp/agents-widget",
            startedAt: now.addingTimeInterval(-200),
            lastActivityAt: now.addingTimeInterval(-10),
            activeTool: ToolCallSummary(
                id: "tool-1",
                name: "bash",
                status: "running",
                startedAt: now.addingTimeInterval(-120),
                ageSeconds: 120
            )
        )
        let process = ProcessSnapshot(
            pid: 123,
            parentPid: 1,
            provider: .codex,
            tty: "/dev/ttys000",
            startedAt: now.addingTimeInterval(-200),
            command: "codex",
            cwd: "/tmp/agents-widget"
        )

        let merged = AgentMonitor.merge(processes: [process], sessions: [session], now: now)

        XCTAssertEqual(merged.first?.status, .stuck)
    }

    @MainActor
    func testHiddenModeSchedulesNoPeriodicRefreshAfterInitialSettle() async throws {
        let processProvider = CountingMonitorProcessProvider()
        let codexStore = CountingMonitorCodexStore()
        let openCodeStore = CountingMonitorOpenCodeStore()
        let eventSource = ManualAgentEventSource()
        let monitor = AgentMonitor(
            processProvider: processProvider,
            codexStore: codexStore,
            openCodeStore: openCodeStore,
            eventSource: eventSource,
            eventDebounceNanoseconds: 10_000_000,
            menuTickIntervalNanoseconds: 10_000_000
        )

        monitor.start()
        eventSource.emit(.codexSessionsChanged)
        eventSource.emit(.openCodeDatabaseChanged)
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(processProvider.callCount, 0)
        XCTAssertEqual(codexStore.callCount, 0)
        XCTAssertEqual(openCodeStore.callCount, 0)
        monitor.stop()
    }

    @MainActor
    func testMenuOpenRequestsBoundedRefreshWithThrottle() async throws {
        let processProvider = CountingMonitorProcessProvider()
        let codexStore = CountingMonitorCodexStore()
        let openCodeStore = CountingMonitorOpenCodeStore()
        let eventSource = ManualAgentEventSource()
        let dateProvider = MutableDateProvider(date: Date(timeIntervalSince1970: 1_000))
        let monitor = AgentMonitor(
            processProvider: processProvider,
            codexStore: codexStore,
            openCodeStore: openCodeStore,
            dateProvider: dateProvider,
            eventSource: eventSource,
            eventDebounceNanoseconds: 10_000_000,
            menuTickIntervalNanoseconds: 10_000_000,
            menuOpenRefreshThrottleInterval: 5,
            menuCloseGraceNanoseconds: 100_000_000
        )

        monitor.start()
        monitor.setMenuVisible(true)
        try await waitForMainActorCondition(timeout: 1) {
            processProvider.callCount == 1 && !monitor.isRefreshing
        }

        XCTAssertEqual(processProvider.callCount, 1)
        XCTAssertEqual(codexStore.callCount, 1)
        XCTAssertEqual(openCodeStore.callCount, 1)
        XCTAssertEqual(eventSource.startCount, 1)
        XCTAssertEqual(eventSource.stopCount, 0)
        XCTAssertEqual(monitor.lastRefreshProfile?.reason, .menuOpen)

        monitor.setMenuVisible(false)
        monitor.setMenuVisible(true)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(processProvider.callCount, 1)
        XCTAssertEqual(codexStore.callCount, 1)
        XCTAssertEqual(openCodeStore.callCount, 1)
        XCTAssertEqual(eventSource.startCount, 1)
        XCTAssertEqual(eventSource.stopCount, 0)

        dateProvider.advance(by: 5.1)
        monitor.setMenuVisible(false)
        monitor.setMenuVisible(true)
        try await waitForMainActorCondition(timeout: 1) {
            processProvider.callCount == 2 && !monitor.isRefreshing
        }

        XCTAssertEqual(codexStore.callCount, 1)
        XCTAssertEqual(openCodeStore.callCount, 1)
        XCTAssertEqual(eventSource.startCount, 1)
        XCTAssertEqual(monitor.lastRefreshProfile?.reason, .menuOpen)
        monitor.setMenuVisible(false)
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertEqual(eventSource.stopCount, 1)
        monitor.stop()
    }

    @MainActor
    func testWarmCacheRunsStartupRefreshWithoutMenuVisibility() async throws {
        let processProvider = CountingMonitorProcessProvider()
        let codexStore = CountingMonitorCodexStore()
        let openCodeStore = CountingMonitorOpenCodeStore()
        let eventSource = ManualAgentEventSource()
        let monitor = AgentMonitor(
            processProvider: processProvider,
            codexStore: codexStore,
            openCodeStore: openCodeStore,
            eventSource: eventSource
        )

        monitor.start()
        monitor.warmCache()
        try await waitForMainActorCondition(timeout: 1) {
            processProvider.callCount == 1 && !monitor.isRefreshing
        }

        XCTAssertEqual(processProvider.callCount, 1)
        XCTAssertEqual(codexStore.callCount, 1)
        XCTAssertEqual(openCodeStore.callCount, 1)
        XCTAssertEqual(eventSource.startCount, 0)
        XCTAssertEqual(eventSource.stopCount, 0)
        XCTAssertEqual(monitor.lastRefreshProfile?.reason, .startup)
        monitor.stop()
    }

    @MainActor
    func testDeliveredFileDatabaseAndProcessEventsCoalesceWithoutForcingDetailRefresh() async throws {
        let processProvider = CountingMonitorProcessProvider()
        let codexStore = CountingMonitorCodexStore()
        let openCodeStore = CountingMonitorOpenCodeStore()
        let eventSource = ManualAgentEventSource()
        let monitor = AgentMonitor(
            processProvider: processProvider,
            codexStore: codexStore,
            openCodeStore: openCodeStore,
            eventSource: eventSource,
            eventDebounceNanoseconds: 10_000_000
        )

        monitor.setMenuVisible(true)
        monitor.start()

        monitor.handleEvent(.codexSessionsChanged)
        monitor.handleEvent(.openCodeDatabaseChanged)
        monitor.handleEvent(.processExited(123))

        try await waitForMainActorCondition(timeout: 1) {
            processProvider.callCount == 1 && !monitor.isRefreshing
        }
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(processProvider.callCount, 1)
        XCTAssertEqual(codexStore.callCount, 1)
        XCTAssertEqual(openCodeStore.callCount, 1)
        XCTAssertEqual(monitor.lastRefreshProfile?.reason, .providerDirty)
        monitor.stop()
    }

    func testActiveFilterReturnsOnlyTerminalBackedAgents() {
        let active = AgentSummary(
            id: "active",
            provider: .codex,
            title: "Active",
            pid: 1,
            tty: "/dev/ttys001",
            terminalTarget: TerminalTarget(tty: "/dev/ttys001", pid: 1)
        )
        let historical = AgentSummary(id: "historical", provider: .opencode, title: "Historical")

        XCTAssertEqual(AgentMonitor.filteredAgents([active, historical], filter: .activeTerminal).map(\.id), ["active"])
        XCTAssertEqual(AgentMonitor.filteredAgents([active, historical], filter: .allTasks).map(\.id), ["active", "historical"])
    }

    func testAttentionReasonsAndBadgeCountRules() {
        let stuck = AgentSummary(
            id: "stuck",
            provider: .codex,
            title: "Stuck",
            pid: 1,
            tty: "/dev/ttys001",
            status: .stuck,
            terminalTarget: TerminalTarget(tty: "/dev/ttys001", pid: 1)
        )
        let error = AgentSummary(
            id: "error",
            provider: .codex,
            title: "Error",
            pid: 2,
            tty: "/dev/ttys002",
            status: .error,
            terminalTarget: TerminalTarget(tty: "/dev/ttys002", pid: 2)
        )
        let inactiveError = AgentSummary(id: "inactive-error", provider: .codex, title: "Inactive Error", status: .error)
        let idle = AgentSummary(
            id: "idle",
            provider: .opencode,
            title: "Idle",
            pid: 3,
            tty: "/dev/ttys003",
            status: .idle,
            terminalTarget: TerminalTarget(tty: "/dev/ttys003", pid: 3),
            statusEvidence: AgentStatusEvidence()
        )

        let withAttention = AgentMonitor.applyAttention(
            to: [stuck, error, inactiveError, idle],
            previousStatuses: [:],
            previousTerminalBackedIDs: []
        )

        XCTAssertEqual(withAttention.first(where: { $0.id == "stuck" })?.attentionReasons, [.stuck])
        XCTAssertEqual(withAttention.first(where: { $0.id == "error" })?.attentionReasons, [.error])
        XCTAssertEqual(withAttention.first(where: { $0.id == "inactive-error" })?.attentionReasons, [])
        XCTAssertEqual(withAttention.first(where: { $0.id == "idle" })?.attentionReasons, [.inputNeeded])
        XCTAssertEqual(withAttention.filter(\.needsAttention).count, 3)
    }

    func testBadgeCountsOneAgentOnceWithMultipleAttentionReasons() {
        let agent = AgentSummary(
            id: "agent",
            provider: .codex,
            title: "Agent",
            pid: 3,
            tty: "/dev/ttys003",
            status: .stuck,
            terminalTarget: TerminalTarget(tty: "/dev/ttys003", pid: 3)
        )

        let withAttention = AgentMonitor.applyAttention(
            to: [agent],
            previousStatuses: [:],
            previousTerminalBackedIDs: []
        )

        XCTAssertEqual(withAttention.first?.attentionReasons, [.stuck])
        XCTAssertEqual(withAttention.filter(\.needsAttention).count, 1)
    }

    func testCompletedAttentionRequiresObservedTransitionOrPriorTerminalBacking() {
        let complete = AgentSummary(id: "session", provider: .codex, title: "Done", status: .complete)

        let historical = AgentMonitor.applyAttention(
            to: [complete],
            previousStatuses: [:],
            previousTerminalBackedIDs: []
        )
        let transitioned = AgentMonitor.applyAttention(
            to: [complete],
            previousStatuses: ["session": .running],
            previousTerminalBackedIDs: []
        )
        let previouslyTerminalBacked = AgentMonitor.applyAttention(
            to: [complete],
            previousStatuses: [:],
            previousTerminalBackedIDs: ["session"]
        )

        XCTAssertEqual(historical.first?.attentionReasons, [])
        XCTAssertEqual(transitioned.first?.attentionReasons, [.completed])
        XCTAssertEqual(previouslyTerminalBacked.first?.attentionReasons, [.completed])
    }
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private final class BlockingProcessProvider: ProcessSnapshotProviding, @unchecked Sendable {
    private let enteredSemaphore = DispatchSemaphore(value: 0)
    private let releaseSemaphore = DispatchSemaphore(value: 0)
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
        enteredSemaphore.signal()
        releaseSemaphore.wait()
        return ProviderResult(value: [])
    }

    func waitUntilEntered(timeout: TimeInterval) -> Bool {
        enteredSemaphore.wait(timeout: .now() + timeout) == .success
    }

    func release() {
        releaseSemaphore.signal()
    }
}

private struct EmptyCodexStore: CodexSessionStoring {
    func summaries(now: Date) -> ProviderResult<[AgentSummary]> {
        ProviderResult(value: [])
    }
}

private struct EmptyOpenCodeStore: OpenCodeSessionStoring {
    func summaries(now: Date) -> ProviderResult<[AgentSummary]> {
        ProviderResult(value: [])
    }
}

private final class MutableDateProvider: DateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(date: Date) {
        self.date = date
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        date = date.addingTimeInterval(interval)
        lock.unlock()
    }
}

private final class CountingMonitorProcessProvider: ProcessSnapshotProviding, @unchecked Sendable {
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

private final class CountingMonitorCodexStore: CodexSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _callCount
    }

    func summaries(now: Date) -> ProviderResult<[AgentSummary]> {
        lock.lock()
        _callCount += 1
        lock.unlock()
        return ProviderResult(value: [])
    }
}

private final class CountingMonitorOpenCodeStore: OpenCodeSessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _callCount
    }

    func summaries(now: Date) -> ProviderResult<[AgentSummary]> {
        lock.lock()
        _callCount += 1
        lock.unlock()
        return ProviderResult(value: [])
    }
}

private final class ManualAgentEventSource: AgentEventSourcing, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (AgentRefreshTrigger) -> Void)?
    private var _startCount = 0
    private var _stopCount = 0

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _startCount
    }

    var stopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _stopCount
    }

    func start(onEvent: @escaping @Sendable (AgentRefreshTrigger) -> Void) {
        lock.lock()
        _startCount += 1
        callback = onEvent
        lock.unlock()
    }

    func stop() {
        lock.lock()
        _stopCount += 1
        callback = nil
        lock.unlock()
    }

    func emit(_ trigger: AgentRefreshTrigger) {
        lock.lock()
        let callback = callback
        lock.unlock()
        callback?(trigger)
    }
}

@MainActor
private func waitForMainActorCondition(timeout: TimeInterval, condition: @escaping () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Timed out waiting for condition")
}
