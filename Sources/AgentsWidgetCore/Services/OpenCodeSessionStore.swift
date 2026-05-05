import Foundation
import SQLite3

public protocol OpenCodeSessionStoring: Sendable {
    func summaries(now: Date) -> ProviderResult<[AgentSummary]>
}

public final class OpenCodeSessionStore: OpenCodeSessionStoring, ModeAwareOpenCodeSessionStoring, @unchecked Sendable {
    let databaseURL: URL
    let sessionLimit: Int
    let detailCandidateLimit: Int
    private let cacheLock = NSLock()
    private var detailCache: [String: OpenCodeCachedSummary] = [:]
    private var databaseCache: OpenCodeDatabaseCache?

    public init(
        databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/opencode/opencode.db"),
        sessionLimit: Int = 50,
        detailCandidateLimit: Int = 8
    ) {
        self.databaseURL = databaseURL
        self.sessionLimit = sessionLimit
        self.detailCandidateLimit = detailCandidateLimit
    }

    public func summaries(now: Date) -> ProviderResult<[AgentSummary]> {
        summaries(now: now, mode: .bounded)
    }

    public func summaries(now: Date, mode: SessionRefreshMode) -> ProviderResult<[AgentSummary]> {
        let metadata = databaseMetadata()
        if let cached = cachedDatabaseResult(metadata: metadata, now: now, mode: mode) {
            return cached
        }

        var db: OpaquePointer?
        let uri = "file:\(databaseURL.path)?mode=ro"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "database unavailable"
            if db != nil {
                sqlite3_close(db)
            }
            let result = ProviderResult<[AgentSummary]>(value: [], diagnostics: [Diagnostics.openCode("\(Diagnostics.openCodeDBBusy): \(message)")])
            storeDatabaseResult(result, metadata: metadata, mode: mode)
            return result
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)

        var diagnostics: [String] = []
        var summaries: [AgentSummary] = []
        var metrics = ProviderMetrics()

        let sessions = querySessions(db: db, diagnostics: &diagnostics, metrics: &metrics)
        pruneCache(keeping: sessions)
        for (index, session) in sessions.enumerated() {
            if let cached = cachedSummary(for: session, now: now) {
                summaries.append(cached)
                continue
            }
            if mode == .bounded, index >= detailCandidateLimit {
                summaries.append(metadataOnlySummary(session: session))
                continue
            }
            let parts = queryJSONRows(
                db: db,
                sql: "select data, time_created, time_updated from part where session_id = ? order by time_updated desc limit 200",
                sessionID: session.id,
                diagnostics: &diagnostics,
                metrics: &metrics
            )
            let messages = queryJSONRows(
                db: db,
                sql: "select data, time_created, time_updated from message where session_id = ? order by time_updated desc limit 50",
                sessionID: session.id,
                diagnostics: &diagnostics,
                metrics: &metrics
            )
            let summary = summarize(session: session, parts: parts, messages: messages, now: now)
            storeCachedSummary(summary, for: session)
            summaries.append(summary)
        }

        let result = ProviderResult(value: summaries, diagnostics: diagnostics, metrics: metrics)
        storeDatabaseResult(result, metadata: metadata, mode: mode)
        return result
    }

    private func cachedDatabaseResult(
        metadata: OpenCodeDatabaseMetadata?,
        now: Date,
        mode: SessionRefreshMode
    ) -> ProviderResult<[AgentSummary]>? {
        guard let metadata else {
            return nil
        }
        cacheLock.lock()
        let cached = databaseCache
        cacheLock.unlock()
        guard let cached, cached.metadata == metadata else {
            return nil
        }
        guard mode == .bounded || cached.mode == .deep else {
            return nil
        }
        return cached.result.refreshedDynamicFields(now: now)
    }

    private func storeDatabaseResult(
        _ result: ProviderResult<[AgentSummary]>,
        metadata: OpenCodeDatabaseMetadata?,
        mode: SessionRefreshMode
    ) {
        guard let metadata else {
            return
        }
        cacheLock.lock()
        databaseCache = OpenCodeDatabaseCache(metadata: metadata, mode: mode, result: result)
        cacheLock.unlock()
    }

    private func databaseMetadata() -> OpenCodeDatabaseMetadata? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return nil
        }
        let urls = [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm")
        ]
        return OpenCodeDatabaseMetadata(
            files: urls.map { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return OpenCodeFileMetadata(
                    path: url.path,
                    exists: FileManager.default.fileExists(atPath: url.path),
                    modifiedAt: values?.contentModificationDate,
                    size: values?.fileSize.map(Int64.init)
                )
            }
        )
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

    func querySessions(db: OpaquePointer, diagnostics: inout [String], metrics: inout ProviderMetrics) -> [OpenCodeSessionRow] {
        var statement: OpaquePointer?
        let sql = "select id, title, directory, time_created, time_updated from session order by time_updated desc limit ?"
        metrics.sqliteQueries += 1
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
        diagnostics: inout [String],
        metrics: inout ProviderMetrics
    ) -> [OpenCodeJSONRow] {
        var statement: OpaquePointer?
        metrics.sqliteQueries += 1
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

    func metadataOnlySummary(session: OpenCodeSessionRow) -> AgentSummary {
        AgentSummary(
            id: session.id,
            provider: .opencode,
            title: JSONHelpers.truncatedTitle(session.title ?? "OpenCode - \(AgentFormatters.formatPathBasename(session.directory))"),
            cwd: session.directory,
            status: .unknown,
            startedAt: session.createdAt,
            lastActivityAt: session.updatedAt,
            statusEvidence: AgentStatusEvidence(evidenceObservedAt: session.updatedAt)
        )
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
        var activity: ProviderActivity = .unknown
        var statusEvidence = AgentStatusEvidence(evidenceObservedAt: session.updatedAt)
        var diagnostics: [String] = []

        for row in parts {
            guard let json = try? JSONHelpers.dictionary(from: row.data) else {
                diagnostics.append(Diagnostics.openCode("malformed part JSON in \(session.id)"))
                continue
            }
            let type = JSONHelpers.string(json, keys: ["type"])
            if type == "step-finish" {
                markAssistantOrToolActivity(row: row, evidence: &statusEvidence)
                tokenUsage = JSONHelpers.tokenUsage(from: JSONHelpers.dictionary(json, key: "tokens")) ?? tokenUsage
                costUSD = JSONHelpers.decimal(json, keys: ["cost"]) ?? costUSD
                if JSONHelpers.string(json, keys: ["reason"]) == "error" {
                    didError = true
                    activity = .errored
                    statusEvidence.providerTerminalState = .error
                }
            }
            if type == "tool", activeTool == nil {
                markAssistantOrToolActivity(row: row, evidence: &statusEvidence)
                let toolState = parseToolState(json, row: row, now: now)
                if toolState.isError {
                    didError = true
                    activity = .errored
                    statusEvidence.providerTerminalState = .error
                }
                activeTool = toolState.tool
                if toolState.isActive {
                    activity = .active
                    statusEvidence.providerTerminalState = .running
                    statusEvidence.openActivityKind = .toolCall
                    statusEvidence.openActivityStartedAt = toolState.tool?.startedAt ?? row.createdAt
                    statusEvidence.openActivityUpdatedAt = row.updatedAt ?? toolState.tool?.startedAt ?? row.createdAt
                }
            }
            if ["text", "reasoning", "file", "patch"].contains(type ?? "") {
                markAssistantOrToolActivity(row: row, evidence: &statusEvidence)
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
            markMessageActivity(json, row: row, evidence: &statusEvidence)
            tokenUsage = JSONHelpers.tokenUsage(from: JSONHelpers.dictionary(json, key: "tokens")) ?? tokenUsage
            costUSD = JSONHelpers.decimal(json, keys: ["cost"]) ?? costUSD
            if json["error"] != nil {
                didError = true
                activity = .errored
                statusEvidence.providerTerminalState = .error
            }
            switch finishState(json) {
            case .active:
                if activity != .errored {
                    activity = .active
                    statusEvidence.providerTerminalState = .running
                    if statusEvidence.openActivityKind == nil {
                        statusEvidence.openActivityKind = .modelTurn
                        statusEvidence.openActivityStartedAt = row.createdAt
                        statusEvidence.openActivityUpdatedAt = row.updatedAt ?? row.createdAt
                    }
                }
            case .finished:
                if activity != .errored {
                    activity = .finished
                    statusEvidence.providerTerminalState = .complete
                    clearOpenActivity(evidence: &statusEvidence)
                }
            case .errored:
                didError = true
                activity = .errored
                statusEvidence.providerTerminalState = .error
                clearOpenActivity(evidence: &statusEvidence)
            case .unknown:
                break
            }
        }
        statusEvidence.providerTerminalState = didError ? .error : activity.providerTerminalState
        if activeTool == nil {
            clearOpenActivity(evidence: &statusEvidence)
        }

        return AgentSummary(
            id: session.id,
            provider: .opencode,
            title: JSONHelpers.truncatedTitle(session.title ?? "OpenCode - \(AgentFormatters.formatPathBasename(session.directory))"),
            cwd: session.directory,
            status: didError ? .error : activity.agentStatus,
            startedAt: session.createdAt,
            lastActivityAt: session.updatedAt,
            tokenUsage: tokenUsage,
            costUSD: costUSD,
            activeTool: activeTool,
            statusEvidence: statusEvidence,
            diagnostics: diagnostics
        )
    }

    func parseTool(_ json: JSONDictionary, row: OpenCodeJSONRow, now: Date) -> ToolCallSummary? {
        parseToolState(json, row: row, now: now).tool
    }

    func parseToolState(_ json: JSONDictionary, row: OpenCodeJSONRow, now: Date) -> OpenCodeToolState {
        let state = JSONHelpers.dictionary(json, key: "state") ?? [:]
        let status = JSONHelpers.string(state, keys: ["status"]) ?? "running"
        let time = JSONHelpers.dictionary(state, key: "time") ?? JSONHelpers.dictionary(json, key: "time") ?? [:]
        let start = JSONHelpers.date(time["start"]) ?? row.createdAt
        let end = JSONHelpers.date(time["end"])
        if status.localizedCaseInsensitiveContains("error") {
            return OpenCodeToolState(tool: nil, isActive: false, isError: true)
        }
        guard status != "completed", end == nil else {
            return OpenCodeToolState(tool: nil, isActive: false, isError: false)
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
        return OpenCodeToolState(tool: ToolCallSummary(
            id: JSONHelpers.string(json, keys: ["callID", "callId", "id"]),
            name: name,
            status: status,
            startedAt: start,
            completedAt: nil,
            ageSeconds: start.map { max(0, now.timeIntervalSince($0)) }
        ), isActive: true, isError: false)
    }

    fileprivate func finishState(_ json: JSONDictionary) -> ProviderActivity {
        guard let finish = JSONHelpers.string(json, keys: ["finish"])?.lowercased() else {
            if JSONHelpers.bool(json, keys: ["finish"]) == false {
                return .unknown
            }
            return .unknown
        }
        switch finish {
        case "tool-calls":
            return .active
        case "stop", "length", "other":
            return .finished
        case "error":
            return .errored
        default:
            return .unknown
        }
    }

    func columnString(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    private func markMessageActivity(_ json: JSONDictionary, row: OpenCodeJSONRow, evidence: inout AgentStatusEvidence) {
        let timestamp = row.updatedAt ?? row.createdAt
        if JSONHelpers.string(json, keys: ["role"]) == "user" {
            evidence.lastUserInputAt = maxDate(evidence.lastUserInputAt, timestamp)
        } else {
            evidence.lastAssistantOrToolActivityAt = maxDate(evidence.lastAssistantOrToolActivityAt, timestamp)
        }
    }

    private func markAssistantOrToolActivity(row: OpenCodeJSONRow, evidence: inout AgentStatusEvidence) {
        evidence.lastAssistantOrToolActivityAt = maxDate(evidence.lastAssistantOrToolActivityAt, row.updatedAt ?? row.createdAt)
    }

    private func clearOpenActivity(evidence: inout AgentStatusEvidence) {
        evidence.openActivityKind = nil
        evidence.openActivityStartedAt = nil
        evidence.openActivityUpdatedAt = nil
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        guard let rhs else {
            return lhs
        }
        guard let lhs else {
            return rhs
        }
        return max(lhs, rhs)
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

private struct OpenCodeFileMetadata: Equatable, Sendable {
    var path: String
    var exists: Bool
    var modifiedAt: Date?
    var size: Int64?
}

private struct OpenCodeDatabaseMetadata: Equatable, Sendable {
    var files: [OpenCodeFileMetadata]
}

private struct OpenCodeDatabaseCache: Sendable {
    var metadata: OpenCodeDatabaseMetadata
    var mode: SessionRefreshMode
    var result: ProviderResult<[AgentSummary]>
}

struct OpenCodeToolState: Sendable {
    var tool: ToolCallSummary?
    var isActive: Bool
    var isError: Bool
}

fileprivate enum ProviderActivity: Sendable {
    case active
    case finished
    case errored
    case unknown

    var agentStatus: AgentStatus {
        switch self {
        case .active:
            .running
        case .finished:
            .complete
        case .errored:
            .error
        case .unknown:
            .unknown
        }
    }

    var providerTerminalState: ProviderTerminalState {
        switch self {
        case .active:
            .running
        case .finished:
            .complete
        case .errored:
            .error
        case .unknown:
            .unknown
        }
    }
}

let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
