import SQLite3
import XCTest
@testable import AgentsWidgetCore

final class OpenCodeSessionStoreTests: XCTestCase {
    func testParsesSessionFieldsTokensCostAndActiveTool() throws {
        let dbURL = try makeOpenCodeFixture()
        let store = OpenCodeSessionStore(databaseURL: dbURL, sessionLimit: 50)
        let now = Date(timeIntervalSince1970: 1_777_885_500)

        let result = store.summaries(now: now)
        let summary = try XCTUnwrap(result.value.first)

        XCTAssertEqual(summary.id, "opencode-session-1")
        XCTAssertEqual(summary.title, "Implement M1")
        XCTAssertEqual(summary.cwd, "/tmp/agents-widget")
        XCTAssertEqual(summary.tokenUsage?.totalTokens, 42)
        XCTAssertEqual(summary.costUSD, Decimal(string: "0.125"))
        XCTAssertEqual(summary.activeTool?.name, "bash")
        XCTAssertEqual(summary.status, .running)
    }

    func testFinishToolCallsMarksProviderActiveNotComplete() throws {
        let dbURL = try makeOpenCodeFinishFixture(finish: "tool-calls")
        let store = OpenCodeSessionStore(databaseURL: dbURL, sessionLimit: 50)

        let result = store.summaries(now: Date())

        XCTAssertEqual(result.value.first?.status, .running)
    }

    func testFinishStopMarksProviderFinished() throws {
        let dbURL = try makeOpenCodeFinishFixture(finish: "stop")
        let store = OpenCodeSessionStore(databaseURL: dbURL, sessionLimit: 50)

        let result = store.summaries(now: Date())

        XCTAssertEqual(result.value.first?.status, .complete)
    }

    func testToolErrorMarksProviderErroredWithoutActiveTool() throws {
        let dbURL = try makeOpenCodeToolStatusFixture(status: "error")
        let store = OpenCodeSessionStore(databaseURL: dbURL, sessionLimit: 50)

        let result = store.summaries(now: Date())

        XCTAssertEqual(result.value.first?.status, .error)
        XCTAssertNil(result.value.first?.activeTool)
    }

    func testUnavailableDatabaseReturnsDiagnostic() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.db")
        let store = OpenCodeSessionStore(databaseURL: missing)
        let result = store.summaries(now: Date())

        XCTAssertTrue(result.value.isEmpty)
        XCTAssertTrue(result.diagnostics.contains { $0.contains("OpenCode DB busy") })
    }

    func testReusesUnchangedSessionDetailCache() throws {
        let dbURL = try makeOpenCodeFixture()
        let store = OpenCodeSessionStore(databaseURL: dbURL, sessionLimit: 50)
        let first = store.summaries(now: Date(timeIntervalSince1970: 1_777_885_500))

        XCTAssertEqual(first.value.first?.tokenUsage?.totalTokens, 42)
        XCTAssertEqual(first.value.first?.activeTool?.name, "bash")

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        guard let db else {
            throw NSError(domain: "OpenCodeSessionStoreTests", code: 3)
        }
        defer { sqlite3_close(db) }
        try exec("delete from part; delete from message;", db: db)

        let second = store.summaries(now: Date(timeIntervalSince1970: 1_777_885_600))

        XCTAssertEqual(second.value.first?.tokenUsage?.totalTokens, 42)
        XCTAssertEqual(second.value.first?.activeTool?.name, "bash")
        XCTAssertLessThanOrEqual(second.metrics.sqliteQueries, 1)
    }

    func testBoundedRefreshSkipsDetailsForOlderUncachedSessions() throws {
        let dbURL = try makeOpenCodeTwoSessionFixture()
        let store = OpenCodeSessionStore(databaseURL: dbURL, sessionLimit: 2, detailCandidateLimit: 1)

        let bounded = store.summaries(now: Date(timeIntervalSince1970: 1_777_885_600), mode: .bounded)

        XCTAssertEqual(bounded.metrics.sqliteQueries, 3)
        XCTAssertEqual(bounded.value.first(where: { $0.id == "newer" })?.tokenUsage?.totalTokens, 10)
        XCTAssertNil(bounded.value.first(where: { $0.id == "older" })?.tokenUsage)
        XCTAssertEqual(bounded.value.first(where: { $0.id == "older" })?.status, .unknown)

        let deepStore = OpenCodeSessionStore(databaseURL: dbURL, sessionLimit: 2, detailCandidateLimit: 1)
        let deep = deepStore.summaries(now: Date(timeIntervalSince1970: 1_777_885_600), mode: .deep)

        XCTAssertEqual(deep.metrics.sqliteQueries, 5)
        XCTAssertEqual(deep.value.first(where: { $0.id == "older" })?.tokenUsage?.totalTokens, 20)
    }

    private func makeOpenCodeFixture() throws -> URL {
        let directory = try temporaryDirectory()
        let dbURL = directory.appendingPathComponent("opencode.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        guard let db else {
            throw NSError(domain: "OpenCodeSessionStoreTests", code: 1)
        }
        defer { sqlite3_close(db) }

        try exec("""
        create table session(id text primary key, title text, directory text, time_created integer, time_updated integer);
        create table part(id text, session_id text, data text, time_created integer, time_updated integer);
        create table message(id text, session_id text, data text, time_created integer, time_updated integer);
        insert into session values('opencode-session-1', 'Implement M1', '/tmp/agents-widget', 1777885200000, 1777885300000);
        insert into part values('part-1', 'opencode-session-1', '{"type":"step-finish","tokens":{"input":20,"output":22,"total":42},"cost":0.125}', 1777885201000, 1777885201000);
        insert into part values('part-2', 'opencode-session-1', '{"type":"tool","callID":"tool-1","tool":"bash","state":{"status":"running","time":{"start":1777885202000}}}', 1777885202000, 1777885202000);
        insert into message values('message-1', 'opencode-session-1', '{"role":"assistant","finish":false}', 1777885203000, 1777885203000);
        """, db: db)

        return dbURL
    }

    private func makeOpenCodeTwoSessionFixture() throws -> URL {
        let directory = try temporaryDirectory()
        let dbURL = directory.appendingPathComponent("opencode.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        guard let db else {
            throw NSError(domain: "OpenCodeSessionStoreTests", code: 6)
        }
        defer { sqlite3_close(db) }

        try exec("""
        create table session(id text primary key, title text, directory text, time_created integer, time_updated integer);
        create table part(id text, session_id text, data text, time_created integer, time_updated integer);
        create table message(id text, session_id text, data text, time_created integer, time_updated integer);
        insert into session values('newer', 'Newer', '/tmp/newer', 1777885200000, 1777885400000);
        insert into session values('older', 'Older', '/tmp/older', 1777885100000, 1777885200000);
        insert into part values('part-1', 'newer', '{"type":"step-finish","tokens":{"total":10}}', 1777885400000, 1777885400000);
        insert into part values('part-2', 'older', '{"type":"step-finish","tokens":{"total":20}}', 1777885200000, 1777885200000);
        """, db: db)

        return dbURL
    }

    private func makeOpenCodeFinishFixture(finish: String) throws -> URL {
        let directory = try temporaryDirectory()
        let dbURL = directory.appendingPathComponent("opencode.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        guard let db else {
            throw NSError(domain: "OpenCodeSessionStoreTests", code: 4)
        }
        defer { sqlite3_close(db) }

        try exec("""
        create table session(id text primary key, title text, directory text, time_created integer, time_updated integer);
        create table part(id text, session_id text, data text, time_created integer, time_updated integer);
        create table message(id text, session_id text, data text, time_created integer, time_updated integer);
        insert into session values('opencode-session-finish', 'Finish state', '/tmp/agents-widget', 1777885200000, 1777885300000);
        insert into message values('message-1', 'opencode-session-finish', '{"role":"assistant","finish":"\(finish)"}', 1777885203000, 1777885203000);
        """, db: db)

        return dbURL
    }

    private func makeOpenCodeToolStatusFixture(status: String) throws -> URL {
        let directory = try temporaryDirectory()
        let dbURL = directory.appendingPathComponent("opencode.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        guard let db else {
            throw NSError(domain: "OpenCodeSessionStoreTests", code: 5)
        }
        defer { sqlite3_close(db) }

        try exec("""
        create table session(id text primary key, title text, directory text, time_created integer, time_updated integer);
        create table part(id text, session_id text, data text, time_created integer, time_updated integer);
        create table message(id text, session_id text, data text, time_created integer, time_updated integer);
        insert into session values('opencode-session-tool', 'Tool state', '/tmp/agents-widget', 1777885200000, 1777885300000);
        insert into part values('part-1', 'opencode-session-tool', '{"type":"tool","callID":"tool-1","tool":"bash","state":{"status":"\(status)","time":{"start":1777885202000}}}', 1777885202000, 1777885202000);
        """, db: db)

        return dbURL
    }

    private func exec(_ sql: String, db: OpaquePointer) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown sqlite error"
            sqlite3_free(error)
            throw NSError(domain: "OpenCodeSessionStoreTests", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
