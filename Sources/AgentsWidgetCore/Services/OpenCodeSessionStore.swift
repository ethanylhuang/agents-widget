import Foundation
import SQLite3

public protocol OpenCodeSessionStoring: Sendable {
    func summaries(now: Date) -> ProviderResult<[AgentSummary]>
}

public final class OpenCodeSessionStore: OpenCodeSessionStoring, @unchecked Sendable {
    let databaseURL: URL
    let sessionLimit: Int
    private let cacheLock = NSLock()
    private var detailCache: [String: OpenCodeCachedSummary] = [:]

    public init(
        databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/opencode/opencode.db"),
        sessionLimit: Int = 50
    ) {
        self.databaseURL = databaseURL
        self.sessionLimit = sessionLimit
    }

    public func summaries(now: Date) -> ProviderResult<[AgentSummary]> {
        var db: OpaquePointer?
        let uri = "file:\(databaseURL.path)?mode=ro"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "database unavailable"
            if db != nil {
                sqlite3_close(db)
            }
            return ProviderResult(value: [], diagnostics: [Diagnostics.openCode("\(Diagnostics.openCodeDBBusy): \(message)")])
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)

        var diagnostics: [String] = []
        var summaries: [AgentSummary] = []

        let sessions = querySessions(db: db, diagnostics: &diagnostics)
        pruneCache(keeping: sessions)
        for session in sessions {
            if let cached = cachedSummary(for: session, now: now) {
                summaries.append(cached)
                continue
            }
            let parts = queryJSONRows(
                db: db,
                sql: "select data, time_created, time_updated from part where session_id = ? order by time_updated desc limit 200",
                sessionID: session.id,
                diagnostics: &diagnostics
            )
            let messages = queryJSONRows(
                db: db,
                sql: "select data, time_created, time_updated from message where session_id = ? order by time_updated desc limit 50",
                sessionID: session.id,
                diagnostics: &diagnostics
            )
            let summary = summarize(session: session, parts: parts, messages: messages, now: now)
            storeCachedSummary(summary, for: session)
            summaries.append(summary)
        }

        return ProviderResult(value: summaries, diagnostics: diagnostics)
    }

    private func cachedSummary(for session: OpenCodeSessionRow, now: Date) -> AgentSummary? {
        guard session.updatedAt != nil else {
            return nil
        }
        cacheLock.lock()
        let cached = detailCache[session.id]
        cacheLock.unlock()
        guard let cached, cached.updatedAt == session.updatedAt else {
            return nil
        }
        return cached.summary.refreshedDynamicFields(now: now)
    }

    private func storeCachedSummary(_ summary: AgentSummary, for session: OpenCodeSessionRow) {
        guard session.updatedAt != nil else {
            return
        }
        cacheLock.lock()
        detailCache[session.id] = OpenCodeCachedSummary(updatedAt: session.updatedAt, summary: summary)
        cacheLock.unlock()
    }

    private func pruneCache(keeping sessions: [OpenCodeSessionRow]) {
        let ids = Set(sessions.map(\.id))
        cacheLock.lock()
        detailCache = detailCache.filter { ids.contains($0.key) }
        cacheLock.unlock()
    }

    func querySessions(db: OpaquePointer, diagnostics: inout [String]) -> [OpenCodeSessionRow] {
        var statement: OpaquePointer?
        let sql = "select id, title, directory, time_created, time_updated from session order by time_updated desc limit ?"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            diagnostics.append(Diagnostics.openCode("session query failed: \(String(cString: sqlite3_errmsg(db)))"))
            return []
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(sessionLimit))

        var rows: [OpenCodeSessionRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = columnString(statement, 0) else {
                continue
            }
            rows.append(OpenCodeSessionRow(
                id: id,
                title: columnString(statement, 1),
                directory: columnString(statement, 2),
                createdAt: JSONHelpers.date(fromNumericTimestamp: Double(sqlite3_column_int64(statement, 3))),
                updatedAt: JSONHelpers.date(fromNumericTimestamp: Double(sqlite3_column_int64(statement, 4)))
            ))
        }
        return rows
    }

    func queryJSONRows(
        db: OpaquePointer,
        sql: String,
        sessionID: String,
        diagnostics: inout [String]
    ) -> [OpenCodeJSONRow] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            diagnostics.append(Diagnostics.openCode("detail query failed: \(String(cString: sqlite3_errmsg(db)))"))
            return []
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sessionID, -1, sqliteTransient)

        var rows: [OpenCodeJSONRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let data = columnString(statement, 0) else {
                continue
            }
            rows.append(OpenCodeJSONRow(
                data: data,
                createdAt: JSONHelpers.date(fromNumericTimestamp: Double(sqlite3_column_int64(statement, 1))),
                updatedAt: JSONHelpers.date(fromNumericTimestamp: Double(sqlite3_column_int64(statement, 2)))
            ))
        }
        return rows
    }

    func summarize(
        session: OpenCodeSessionRow,
        parts: [OpenCodeJSONRow],
        messages: [OpenCodeJSONRow],
        now: Date
    ) -> AgentSummary {
        var tokenUsage: TokenUsage?
        var costUSD: Decimal?
        var activeTool: ToolCallSummary?
        var didError = false
        var didFinish = false
        var diagnostics: [String] = []

        for row in parts {
            guard let json = try? JSONHelpers.dictionary(from: row.data) else {
                diagnostics.append(Diagnostics.openCode("malformed part JSON in \(session.id)"))
                continue
            }
            let type = JSONHelpers.string(json, keys: ["type"])
            if type == "step-finish" {
                tokenUsage = JSONHelpers.tokenUsage(from: JSONHelpers.dictionary(json, key: "tokens")) ?? tokenUsage
                costUSD = JSONHelpers.decimal(json, keys: ["cost"]) ?? costUSD
                if JSONHelpers.string(json, keys: ["reason"]) == "error" {
                    didError = true
                }
            }
            if type == "tool", activeTool == nil {
                activeTool = parseTool(json, row: row, now: now)
            }
            if costUSD == nil {
                costUSD = JSONHelpers.decimal(json, keys: ["cost"])
            }
        }

        for row in messages {
            guard let json = try? JSONHelpers.dictionary(from: row.data) else {
                diagnostics.append(Diagnostics.openCode("malformed message JSON in \(session.id)"))
                continue
            }
            tokenUsage = JSONHelpers.tokenUsage(from: JSONHelpers.dictionary(json, key: "tokens")) ?? tokenUsage
            costUSD = JSONHelpers.decimal(json, keys: ["cost"]) ?? costUSD
            if json["error"] != nil {
                didError = true
            }
            if json["finish"] != nil {
                didFinish = true
            }
        }

        return AgentSummary(
            id: session.id,
            provider: .opencode,
            title: JSONHelpers.truncatedTitle(session.title ?? "OpenCode - \(AgentFormatters.formatPathBasename(session.directory))"),
            cwd: session.directory,
            status: didError ? .error : (didFinish ? .complete : .unknown),
            startedAt: session.createdAt,
            lastActivityAt: session.updatedAt,
            tokenUsage: tokenUsage,
            costUSD: costUSD,
            activeTool: activeTool,
            diagnostics: diagnostics
        )
    }

    func parseTool(_ json: JSONDictionary, row: OpenCodeJSONRow, now: Date) -> ToolCallSummary? {
        let state = JSONHelpers.dictionary(json, key: "state") ?? [:]
        let status = JSONHelpers.string(state, keys: ["status"]) ?? "running"
        let time = JSONHelpers.dictionary(state, key: "time") ?? JSONHelpers.dictionary(json, key: "time") ?? [:]
        let start = JSONHelpers.date(time["start"]) ?? row.createdAt
        let end = JSONHelpers.date(time["end"])
        guard status != "completed", end == nil else {
            return nil
        }
        let toolValue = json["tool"]
        let name: String
        if let toolString = toolValue as? String {
            name = toolString
        } else if let toolDictionary = toolValue as? JSONDictionary {
            name = JSONHelpers.string(toolDictionary, keys: ["name", "id"]) ?? "tool"
        } else {
            name = JSONHelpers.string(json, keys: ["name"]) ?? "tool"
        }
        return ToolCallSummary(
            id: JSONHelpers.string(json, keys: ["callID", "callId", "id"]),
            name: name,
            status: status,
            startedAt: start,
            completedAt: nil,
            ageSeconds: start.map { max(0, now.timeIntervalSince($0)) }
        )
    }

    func columnString(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }
}

struct OpenCodeSessionRow: Sendable {
    var id: String
    var title: String?
    var directory: String?
    var createdAt: Date?
    var updatedAt: Date?
}

struct OpenCodeJSONRow: Sendable {
    var data: String
    var createdAt: Date?
    var updatedAt: Date?
}

private struct OpenCodeCachedSummary: Sendable {
    var updatedAt: Date?
    var summary: AgentSummary
}

let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
