import XCTest
@testable import AgentsWidgetCore

final class CodexSessionStoreStatusEvidenceTests: XCTestCase {
    func testUserInputOnlyTerminalBackedSessionClassifiesAsIdle() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("rollout-user.jsonl")
        try """
        {"type":"session_meta","timestamp":"2026-05-04T10:00:00Z","payload":{"id":"codex-user","cwd":"/tmp/agents-widget"}}
        {"type":"event_msg","timestamp":"2026-05-04T10:00:10Z","payload":{"type":"user_message"}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let now = date("2026-05-04T10:01:00Z")
        let summary = try XCTUnwrap(CodexSessionStore(baseURL: directory).summaries(now: now).value.first)
        let merged = AgentMonitor.merge(
            processes: [process(now: now)],
            sessions: [summary],
            now: now
        )

        XCTAssertEqual(summary.statusEvidence?.lastUserInputAt, date("2026-05-04T10:00:10Z"))
        XCTAssertEqual(merged.first?.status, .idle)
    }

    func testFreshAssistantActivityClassifiesAsRunning() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("rollout-assistant.jsonl")
        try """
        {"type":"session_meta","timestamp":"2026-05-04T10:00:00Z","payload":{"id":"codex-assistant","cwd":"/tmp/agents-widget"}}
        {"type":"event_msg","timestamp":"2026-05-04T10:00:50Z","payload":{"type":"agent_message"}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let now = date("2026-05-04T10:01:00Z")
        let summary = try XCTUnwrap(CodexSessionStore(baseURL: directory).summaries(now: now).value.first)
        let merged = AgentMonitor.merge(
            processes: [process(now: now)],
            sessions: [summary],
            now: now
        )

        XCTAssertEqual(summary.statusEvidence?.lastAssistantOrToolActivityAt, date("2026-05-04T10:00:50Z"))
        XCTAssertEqual(merged.first?.status, .running)
    }

    func testStaleOpenToolClassifiesAsStuck() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("rollout-tool.jsonl")
        try """
        {"type":"session_meta","timestamp":"2026-05-04T10:00:00Z","payload":{"id":"codex-tool","cwd":"/tmp/agents-widget"}}
        {"type":"response_item","timestamp":"2026-05-04T10:00:00Z","payload":{"type":"function_call","call_id":"call-1","name":"bash"}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let now = date("2026-05-04T10:02:00Z")
        let summary = try XCTUnwrap(CodexSessionStore(baseURL: directory).summaries(now: now).value.first)
        let merged = AgentMonitor.merge(
            processes: [process(now: now)],
            sessions: [summary],
            now: now
        )

        XCTAssertEqual(summary.statusEvidence?.openActivityKind, .toolCall)
        XCTAssertEqual(merged.first?.status, .stuck)
    }

    private func process(now: Date) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: 123,
            parentPid: 1,
            provider: .codex,
            tty: "/dev/ttys001",
            startedAt: now.addingTimeInterval(-600),
            command: "codex",
            cwd: "/tmp/agents-widget"
        )
    }
}

private func date(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}
