import XCTest
@testable import AgentsWidgetCore

final class CodexSessionStoreTests: XCTestCase {
    func testParsesSessionMetaTokenCountAndPendingFunctionCallWithoutRawPromptTitle() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("rollout-test.jsonl")
        try """
        {"type":"session_meta","timestamp":"2026-05-04T10:00:00Z","payload":{"id":"codex-session-1","cwd":"/tmp/agents-widget"}}
        {"type":"event_msg","timestamp":"2026-05-04T10:00:01Z","payload":{"type":"task_started","message":"Implement M1 without raw transcripts"}}
        {"type":"event_msg","timestamp":"2026-05-04T10:00:02Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":8,"reasoning_output_tokens":3,"total_tokens":23}}}}
        {"type":"response_item","timestamp":"2026-05-04T10:00:03Z","payload":{"type":"function_call","call_id":"call-1","name":"bash"}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let store = CodexSessionStore(baseURL: directory, maxFiles: 50)
        let result = store.summaries(now: Date(timeIntervalSince1970: 1_800_000_000))
        let summary = try XCTUnwrap(result.value.first)

        XCTAssertEqual(summary.id, "codex-session-1")
        XCTAssertEqual(summary.cwd, "/tmp/agents-widget")
        XCTAssertEqual(summary.title, "Codex - agents-widget")
        XCTAssertEqual(summary.tokenUsage?.totalTokens, 23)
        XCTAssertEqual(summary.activeTool?.name, "bash")
        XCTAssertTrue((summary.activeTool?.ageSeconds ?? 0) > 0)
    }

    func testMarksFunctionCallCompleteWhenOutputAppears() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("rollout-test.jsonl")
        try """
        {"type":"session_meta","timestamp":"2026-05-04T10:00:00Z","payload":{"id":"codex-session-2","cwd":"/tmp/agents-widget"}}
        {"type":"response_item","timestamp":"2026-05-04T10:00:03Z","payload":{"type":"function_call","call_id":"call-1","name":"bash"}}
        {"type":"response_item","timestamp":"2026-05-04T10:00:04Z","payload":{"type":"function_call_output","call_id":"call-1","output":"done"}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let store = CodexSessionStore(baseURL: directory, maxFiles: 50)
        let result = store.summaries(now: Date())
        let summary = try XCTUnwrap(result.value.first)

        XCTAssertNil(summary.activeTool)
    }

    func testMalformedJSONLLineRecordsDiagnostic() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("rollout-test.jsonl")
        try """
        {"type":"session_meta","timestamp":"2026-05-04T10:00:00Z","payload":{"id":"codex-session-3","cwd":"/tmp/agents-widget"}}
        not-json
        """.write(to: file, atomically: true, encoding: .utf8)

        let store = CodexSessionStore(baseURL: directory, maxFiles: 50)
        let result = store.summaries(now: Date())

        XCTAssertEqual(result.value.first?.id, "codex-session-3")
        XCTAssertTrue(result.diagnostics.contains { $0.contains("malformed JSONL") })
    }

    func testReusesUnchangedFileCacheByPathModificationDateAndSize() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("rollout-cache.jsonl")
        let first = """
        {"type":"session_meta","timestamp":"2026-05-04T10:00:00Z","payload":{"id":"codex-cache-1","cwd":"/tmp/one"}}

        """
        let second = """
        {"type":"session_meta","timestamp":"2026-05-04T10:00:00Z","payload":{"id":"codex-cache-2","cwd":"/tmp/two"}}

        """
        XCTAssertEqual(first.utf8.count, second.utf8.count)
        let modificationDate = Date(timeIntervalSince1970: 1_777_885_000)
        try first.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: file.path)

        let store = CodexSessionStore(baseURL: directory, maxFiles: 50)
        let firstResult = store.summaries(now: Date(timeIntervalSince1970: 1_777_885_500))

        XCTAssertEqual(firstResult.value.first?.id, "codex-cache-1")

        try second.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: file.path)
        let secondResult = store.summaries(now: Date(timeIntervalSince1970: 1_777_885_600))

        XCTAssertEqual(secondResult.value.first?.id, "codex-cache-1")
    }
}
