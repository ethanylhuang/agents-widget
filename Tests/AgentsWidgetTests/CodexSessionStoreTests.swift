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
        XCTAssertEqual(summary.status, .running)
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
        XCTAssertEqual(summary.status, .running)
    }

    func testTaskCompleteMarksProviderFinished() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("rollout-complete.jsonl")
        try """
        {"type":"session_meta","timestamp":"2026-05-04T10:00:00Z","payload":{"id":"codex-session-complete","cwd":"/tmp/agents-widget"}}
        {"type":"event_msg","timestamp":"2026-05-04T10:00:01Z","payload":{"type":"task_started"}}
        {"type":"event_msg","timestamp":"2026-05-04T10:00:05Z","payload":{"type":"task_complete"}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let store = CodexSessionStore(baseURL: directory, maxFiles: 50)
        let result = store.summaries(now: Date())

        XCTAssertEqual(result.value.first?.status, .complete)
    }

    func testTurnAbortedWithoutErrorMarksProviderFinished() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("rollout-aborted.jsonl")
        try """
        {"type":"session_meta","timestamp":"2026-05-04T10:00:00Z","payload":{"id":"codex-session-aborted","cwd":"/tmp/agents-widget"}}
        {"type":"event_msg","timestamp":"2026-05-04T10:00:01Z","payload":{"type":"task_started"}}
        {"type":"event_msg","timestamp":"2026-05-04T10:00:05Z","payload":{"type":"turn_aborted","message":"interrupted by user"}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let store = CodexSessionStore(baseURL: directory, maxFiles: 50)
        let result = store.summaries(now: Date())

        XCTAssertEqual(result.value.first?.status, .complete)
    }

    func testParsesAdditionalToolCallPairsAsClosed() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("rollout-tools.jsonl")
        try """
        {"type":"session_meta","timestamp":"2026-05-04T10:00:00Z","payload":{"id":"codex-session-tools","cwd":"/tmp/agents-widget"}}
        {"type":"response_item","timestamp":"2026-05-04T10:00:01Z","payload":{"type":"custom_tool_call","call_id":"custom-1","name":"patch"}}
        {"type":"response_item","timestamp":"2026-05-04T10:00:02Z","payload":{"type":"custom_tool_call_output","call_id":"custom-1","output":"done"}}
        {"type":"response_item","timestamp":"2026-05-04T10:00:03Z","payload":{"type":"tool_search_call","call_id":"search-1"}}
        {"type":"response_item","timestamp":"2026-05-04T10:00:04Z","payload":{"type":"tool_search_output","call_id":"search-1","output":"done"}}
        {"type":"response_item","timestamp":"2026-05-04T10:00:05Z","payload":{"type":"web_search_call","id":"web-1"}}
        {"type":"response_item","timestamp":"2026-05-04T10:00:06Z","payload":{"type":"web_search_end","id":"web-1"}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let store = CodexSessionStore(baseURL: directory, maxFiles: 50)
        let result = store.summaries(now: Date())

        XCTAssertNil(result.value.first?.activeTool)
        XCTAssertEqual(result.value.first?.status, .running)
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

    func testIncrementalParserReadsOnlyAppendedBytesAfterCache() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("rollout-incremental.jsonl")
        let initial = """
        {"type":"session_meta","timestamp":"2026-05-04T10:00:00Z","payload":{"id":"codex-incremental","cwd":"/tmp/agents-widget"}}

        """
        try initial.write(to: file, atomically: true, encoding: .utf8)

        let store = CodexSessionStore(baseURL: directory, maxFiles: 50)
        let first = store.summaries(now: Date(timeIntervalSince1970: 1_777_885_500))
        XCTAssertEqual(first.value.first?.id, "codex-incremental")

        let appended = """
        {"type":"response_item","timestamp":"2026-05-04T10:00:03Z","payload":{"type":"function_call","call_id":"call-1","name":"bash"}}

        """
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(appended.utf8))
        try handle.close()

        let second = store.summaries(now: Date(timeIntervalSince1970: 1_777_885_600))

        XCTAssertEqual(second.value.first?.activeTool?.name, "bash")
        XCTAssertEqual(second.metrics.bytesRead, Int64(appended.utf8.count))
        XCTAssertEqual(second.metrics.filesParsed, 1)
    }

    func testLargeFileParsesPrefixAndTailNotWholeFile() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("rollout-large.jsonl")
        let metadata = """
        {"type":"session_meta","timestamp":"2026-05-04T10:00:00Z","payload":{"id":"codex-large","cwd":"/tmp/agents-widget"}}

        """
        let filler = String(repeating: "{\"type\":\"noop\",\"payload\":{\"text\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}}\n", count: 200)
        let tail = """
        {"type":"response_item","timestamp":"2026-05-04T10:00:03Z","payload":{"type":"function_call","call_id":"call-1","name":"bash"}}

        """
        let text = metadata + filler + tail
        try text.write(to: file, atomically: true, encoding: .utf8)

        let store = CodexSessionStore(
            baseURL: directory,
            maxFiles: 50,
            coldParseByteLimit: 1_024,
            prefixWindowBytes: 256,
            tailWindowBytes: 512
        )
        let result = store.summaries(now: Date(timeIntervalSince1970: 1_777_885_500), mode: .bounded)

        XCTAssertEqual(result.value.first?.id, "codex-large")
        XCTAssertEqual(result.value.first?.activeTool?.name, "bash")
        XCTAssertLessThan(result.metrics.bytesRead, Int64(text.utf8.count))

        let deep = store.summaries(now: Date(timeIntervalSince1970: 1_777_885_600), mode: .deep)
        XCTAssertEqual(deep.value.first?.activeTool?.name, "bash")
        XCTAssertEqual(deep.metrics.bytesRead, 0)

        let coldDeepStore = CodexSessionStore(
            baseURL: directory,
            maxFiles: 50,
            coldParseByteLimit: 1_024,
            prefixWindowBytes: 256,
            tailWindowBytes: 512
        )
        let coldDeep = coldDeepStore.summaries(now: Date(timeIntervalSince1970: 1_777_885_700), mode: .deep)
        XCTAssertEqual(coldDeep.value.first?.activeTool?.name, "bash")
        XCTAssertLessThan(coldDeep.metrics.bytesRead, Int64(text.utf8.count))
    }

    func testBoundedRefreshCapsRecentFilesWhileDeepUsesMaxFiles() throws {
        let directory = try temporaryDirectory()
        for index in 0..<3 {
            let file = directory.appendingPathComponent("rollout-\(index).jsonl")
            try """
            {"type":"session_meta","timestamp":"2026-05-04T10:00:0\(index)Z","payload":{"id":"codex-\(index)","cwd":"/tmp/\(index)"}}

            """.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(1_777_885_000 + index))],
                ofItemAtPath: file.path
            )
        }

        let store = CodexSessionStore(baseURL: directory, maxFiles: 3, boundedFileLimit: 1)

        XCTAssertEqual(store.summaries(now: Date(), mode: .bounded).value.count, 1)
        XCTAssertEqual(store.summaries(now: Date(), mode: .deep).value.count, 3)
    }
}
