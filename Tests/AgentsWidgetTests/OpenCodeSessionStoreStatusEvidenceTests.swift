import SQLite3
import XCTest
@testable import AgentsWidgetCore

final class OpenCodeSessionStoreStatusEvidenceTests: XCTestCase {
    func testUserInputOnlyTerminalBackedSessionClassifiesAsIdle() throws {
        let now = Date(timeIntervalSince1970: 1_777_885_500)
        let dbURL = try makeDatabase(messageJSON: #"{"role":"user"}"#, messageUpdatedAt: now.addingTimeInterval(-100))
        let summary = try XCTUnwrap(OpenCodeSessionStore(databaseURL: dbURL).summaries(now: now).value.first)
        let merged = AgentMonitor.merge(processes: [process(now: now)], sessions: [summary], now: now)

        XCTAssertEqual(summary.statusEvidence?.lastUserInputAt, now.addingTimeInterval(-100))
        XCTAssertEqual(merged.first?.status, .idle)
    }

    func testFreshAssistantActivityClassifiesAsRunning() throws {
        let now = Date(timeIntervalSince1970: 1_777_885_500)
        let dbURL = try makeDatabase(messageJSON: #"{"role":"assistant","finish":false}"#, messageUpdatedAt: now.addingTimeInterval(-10))
        let summary = try XCTUnwrap(OpenCodeSessionStore(databaseURL: dbURL).summaries(now: now).value.first)
        let merged = AgentMonitor.merge(processes: [process(now: now)], sessions: [summary], now: now)

        XCTAssertEqual(summary.statusEvidence?.lastAssistantOrToolActivityAt, now.addingTimeInterval(-10))
        XCTAssertEqual(merged.first?.status, .running)
    }

    private func process(now: Date) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: 234,
            parentPid: 1,
            provider: .opencode,
            tty: "/dev/ttys002",
            startedAt: now.addingTimeInterval(-600),
            command: "opencode",
            cwd: "/tmp/agents-widget"
        )
    }

    private func makeDatabase(messageJSON: String, messageUpdatedAt: Date) throws -> URL {
        let directory = try temporaryDirectory()
        let dbURL = directory.appendingPathComponent("opencode.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        guard let db else {
            throw NSError(domain: "OpenCodeSessionStoreStatusEvidenceTests", code: 1)
        }
        defer { sqlite3_close(db) }

        try exec("""
        create table session(id text primary key, title text, directory text, time_created integer, time_updated integer);
        create table part(id text, session_id text, data text, time_created integer, time_updated integer);
        create table message(id text, session_id text, data text, time_created integer, time_updated integer);
        insert into session values('opencode-status', 'Status task', '/tmp/agents-widget', 1777884000000, \(milliseconds(messageUpdatedAt)));
        insert into message values('message-1', 'opencode-status', '\(messageJSON)', \(milliseconds(messageUpdatedAt)), \(milliseconds(messageUpdatedAt)));
        """, db: db)

        return dbURL
    }

    private func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private func exec(_ sql: String, db: OpaquePointer) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown sqlite error"
            sqlite3_free(error)
            throw NSError(domain: "OpenCodeSessionStoreStatusEvidenceTests", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}

private func date(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}
