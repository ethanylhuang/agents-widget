import XCTest
@testable import AgentsWidgetCore

final class ProcessSnapshotProviderTests: XCTestCase {
    func testParsesCodexPSLine() throws {
        var diagnostics: [String] = []
        let provider = ProcessSnapshotProvider()
        let snapshot = try XCTUnwrap(provider.parsePSLine(
            "123 1 s000 Mon May 4 10:00:00 2026 /opt/homebrew/bin/codex",
            diagnostics: &diagnostics
        ))

        XCTAssertEqual(snapshot.pid, 123)
        XCTAssertEqual(snapshot.parentPid, 1)
        XCTAssertEqual(snapshot.provider, .codex)
        XCTAssertEqual(snapshot.tty, "/dev/ttys000")
        XCTAssertNotNil(snapshot.startedAt)
    }

    func testParsesOpenCodePSLine() throws {
        var diagnostics: [String] = []
        let provider = ProcessSnapshotProvider()
        let snapshot = try XCTUnwrap(provider.parsePSLine(
            "456 1 s004 Mon May 4 10:00:00 2026 /Users/ethanhuang/.opencode/bin/opencode",
            diagnostics: &diagnostics
        ))

        XCTAssertEqual(snapshot.provider, .opencode)
        XCTAssertEqual(snapshot.tty, "/dev/ttys004")
    }

    func testDoesNotMatchWordsOnlyInArguments() {
        var diagnostics: [String] = []
        let provider = ProcessSnapshotProvider()
        let snapshot = provider.parsePSLine(
            "789 1 s005 Mon May 4 10:00:00 2026 /bin/zsh -lc echo codex opencode",
            diagnostics: &diagnostics
        )

        XCTAssertNil(snapshot)
    }

    func testSkipsPathAndCWDLookupsForUnrelatedBSDProcess() {
        var diagnostics: [String] = []
        var pathLookups = 0
        var cwdLookups = 0
        let provider = ProcessSnapshotProvider()

        let snapshot = provider.snapshot(
            pid: 789,
            parentPid: 1,
            comm: "zsh",
            name: "zsh",
            tty: "/dev/ttys005",
            startedAt: nil,
            diagnostics: &diagnostics,
            processPathLookup: { _ in
                pathLookups += 1
                return "/bin/zsh"
            },
            cwdLookup: { _ in
                cwdLookups += 1
                return "/tmp"
            }
        )

        XCTAssertNil(snapshot)
        XCTAssertEqual(pathLookups, 0)
        XCTAssertEqual(cwdLookups, 0)
    }

    func testReusesRecentSnapshotCacheWithoutSyscalls() {
        let clock = ManualSnapshotClock(Date(timeIntervalSince1970: 1_000))
        let collector = CountingSnapshotCollector()
        let provider = ProcessSnapshotProvider(
            cacheTTL: 5,
            now: { clock.now() },
            collector: { collector.snapshots() }
        )

        let first = provider.snapshots()
        let second = provider.snapshots()
        clock.advance(by: 6)
        let third = provider.snapshots()

        XCTAssertEqual(collector.callCount, 2)
        XCTAssertEqual(first.metrics.processSyscalls, 42)
        XCTAssertEqual(second.metrics.processSyscalls, 0)
        XCTAssertEqual(third.metrics.processSyscalls, 42)
        XCTAssertEqual(second.value.first?.pid, 123)
    }
}

private final class ManualSnapshotClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        date = date.addingTimeInterval(seconds)
        lock.unlock()
    }
}

private final class CountingSnapshotCollector: @unchecked Sendable {
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
        return ProviderResult(
            value: [
                ProcessSnapshot(
                    pid: 123,
                    parentPid: 1,
                    provider: .codex,
                    tty: "/dev/ttys000",
                    startedAt: Date(timeIntervalSince1970: 900),
                    command: "codex",
                    cwd: "/tmp/agents-widget"
                )
            ],
            metrics: ProviderMetrics(processSyscalls: 42)
        )
    }
}
