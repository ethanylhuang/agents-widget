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
}
