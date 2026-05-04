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
            startedAt: now.addingTimeInterval(-30),
            lastActivityAt: now.addingTimeInterval(-10)
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
        XCTAssertEqual(merged.first?.status, .idle)
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
