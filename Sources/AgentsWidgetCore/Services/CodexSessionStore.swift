import Foundation

public protocol CodexSessionStoring: Sendable {
    func summaries(now: Date) -> ProviderResult<[AgentSummary]>
}

public final class CodexSessionStore: CodexSessionStoring, @unchecked Sendable {
    let baseURL: URL
    let maxFiles: Int
    private let cacheLock = NSLock()
    private var summaryCache: [String: CodexCachedSummary] = [:]

    public init(
        baseURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"),
        maxFiles: Int = 50
    ) {
        self.baseURL = baseURL
        self.maxFiles = maxFiles
    }

    public func summaries(now: Date) -> ProviderResult<[AgentSummary]> {
        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return ProviderResult(value: [], diagnostics: [Diagnostics.codex("session directory unavailable")])
        }

        let files = jsonlFiles()
        var diagnostics: [String] = []
        var summaries: [AgentSummary] = []
        let selectedFiles = Array(files.prefix(maxFiles))
        pruneCache(keeping: selectedFiles)
        for file in selectedFiles {
            let metadata = metadata(for: file)
            if let cached = cachedSummary(for: file, metadata: metadata, now: now) {
                diagnostics.append(contentsOf: cached.diagnostics)
                if let summary = cached.value {
                    summaries.append(summary)
                }
                continue
            }
            let result = parseFile(file, now: now)
            storeCachedSummary(for: file, metadata: metadata, result: result)
            diagnostics.append(contentsOf: result.diagnostics)
            if let summary = result.value {
                summaries.append(summary)
            }
        }
        return ProviderResult(value: summaries, diagnostics: diagnostics)
    }

    private func metadata(for url: URL) -> CodexFileMetadata? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard values?.contentModificationDate != nil || values?.fileSize != nil else {
            return nil
        }
        return CodexFileMetadata(
            modifiedAt: values?.contentModificationDate,
            size: values?.fileSize.map(Int64.init)
        )
    }

    private func cachedSummary(
        for url: URL,
        metadata: CodexFileMetadata?,
        now: Date
    ) -> ProviderResult<AgentSummary?>? {
        guard let metadata else {
            return nil
        }
        cacheLock.lock()
        let cached = summaryCache[url.path]
        cacheLock.unlock()
        guard let cached, cached.metadata == metadata else {
            return nil
        }
        return ProviderResult(
            value: cached.summary?.refreshedDynamicFields(now: now),
            diagnostics: cached.diagnostics
        )
    }

    private func storeCachedSummary(
        for url: URL,
        metadata: CodexFileMetadata?,
        result: ProviderResult<AgentSummary?>
    ) {
        guard let metadata else {
            return
        }
        cacheLock.lock()
        summaryCache[url.path] = CodexCachedSummary(
            metadata: metadata,
            summary: result.value,
            diagnostics: result.diagnostics
        )
        cacheLock.unlock()
    }

    private func pruneCache(keeping urls: [URL]) {
        let paths = Set(urls.map(\.path))
        cacheLock.lock()
        summaryCache = summaryCache.filter { paths.contains($0.key) }
        cacheLock.unlock()
    }

    func jsonlFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let files = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "jsonl" else {
                return nil
            }
            return url
        }

        return files.sorted { lhs, rhs in
            let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return leftDate > rightDate
        }
    }

    func parseFile(_ url: URL, now: Date) -> ProviderResult<AgentSummary?> {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ProviderResult(value: nil, diagnostics: [Diagnostics.codex("could not read \(url.lastPathComponent)")])
        }
        defer { try? handle.close() }

        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else {
            return ProviderResult(value: nil, diagnostics: [Diagnostics.codex("non-UTF8 session \(url.lastPathComponent)")])
        }

        var parser = CodexSessionParser(fileURL: url, now: now)
        text.enumerateLines { line, _ in
            parser.parseLine(line)
        }
        return ProviderResult(value: parser.summary(), diagnostics: parser.diagnostics)
    }
}

private struct CodexFileMetadata: Equatable, Sendable {
    var modifiedAt: Date?
    var size: Int64?
}

private struct CodexCachedSummary: Sendable {
    var metadata: CodexFileMetadata
    var summary: AgentSummary?
    var diagnostics: [String]
}

struct CodexSessionParser {
    let fileURL: URL
    let now: Date
    var diagnostics: [String] = []
    var sessionID: String?
    var cwd: String?
    var title: String?
    var createdAt: Date?
    var updatedAt: Date?
    var tokenUsage: TokenUsage?
    var didError = false
    var tools: [String: ToolCallSummary] = [:]
    var toolOrder: [String] = []
    var lineNumber = 0

    mutating func parseLine(_ line: String) {
        lineNumber += 1
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        guard shouldParse(trimmed) else {
            return
        }

        let dictionary: JSONDictionary
        do {
            dictionary = try JSONHelpers.dictionary(from: trimmed)
        } catch {
            diagnostics.append(Diagnostics.codex("\(fileURL.lastPathComponent): malformed JSONL line \(lineNumber)"))
            return
        }

        let type = JSONHelpers.string(dictionary, keys: ["type"])
        let payload = JSONHelpers.dictionary(dictionary, key: "payload") ?? [:]
        let timestamp = JSONHelpers.date(dictionary["timestamp"]) ?? JSONHelpers.date(payload["timestamp"])
        if let timestamp {
            updateDates(timestamp)
        }

        switch type {
        case "session_meta":
            sessionID = JSONHelpers.string(payload, keys: ["id"]) ?? sessionID
            cwd = JSONHelpers.string(payload, keys: ["cwd"]) ?? cwd
            if let timestamp = JSONHelpers.date(payload["timestamp"]) {
                updateDates(timestamp)
            }
        case "turn_context":
            cwd = JSONHelpers.string(payload, keys: ["cwd"]) ?? cwd
        case "event_msg":
            parseEventMessage(payload, timestamp: timestamp)
        case "response_item":
            parseResponseItem(payload, timestamp: timestamp)
        default:
            break
        }
    }

    func shouldParse(_ line: String) -> Bool {
        if !line.hasPrefix("{") {
            return true
        }
        return line.contains("\"session_meta\"")
            || line.contains("\"turn_context\"")
            || line.contains("\"event_msg\"")
            || line.contains("\"function_call\"")
            || line.contains("\"function_call_output\"")
            || line.contains("\"web_search_call\"")
    }

    mutating func parseEventMessage(_ payload: JSONDictionary, timestamp: Date?) {
        let eventType = JSONHelpers.string(payload, keys: ["type"])
        switch eventType {
        case "task_started":
            title = title ?? JSONHelpers.string(payload, keys: ["title", "summary"]).map { JSONHelpers.truncatedTitle($0) }
        case "token_count":
            let info = JSONHelpers.dictionary(payload, key: "info")
            tokenUsage = JSONHelpers.tokenUsage(from: JSONHelpers.dictionary(info ?? [:], key: "total_token_usage"))
                ?? JSONHelpers.tokenUsage(from: info)
                ?? tokenUsage
        case "exec_command_end":
            let exitCode = JSONHelpers.int(payload, keys: ["exit_code", "exitCode"])
                ?? JSONHelpers.int(JSONHelpers.dictionary(payload, key: "info") ?? [:], keys: ["exit_code", "exitCode"])
            if let exitCode, exitCode != 0 {
                didError = true
            }
            closeTool(id: JSONHelpers.string(payload, keys: ["call_id", "callId", "id"]), at: timestamp)
        default:
            break
        }
    }

    mutating func parseResponseItem(_ payload: JSONDictionary, timestamp: Date?) {
        let itemType = JSONHelpers.string(payload, keys: ["type"])
        switch itemType {
        case "function_call":
            let id = JSONHelpers.string(payload, keys: ["call_id", "callId", "id"]) ?? UUID().uuidString
            let name = JSONHelpers.string(payload, keys: ["name"]) ?? "tool"
            tools[id] = ToolCallSummary(
                id: id,
                name: name,
                status: "running",
                startedAt: timestamp,
                completedAt: nil,
                ageSeconds: timestamp.map { max(0, now.timeIntervalSince($0)) }
            )
            toolOrder.append(id)
        case "function_call_output":
            if JSONHelpers.string(payload, keys: ["error"]) != nil {
                didError = true
            }
            closeTool(id: JSONHelpers.string(payload, keys: ["call_id", "callId", "id"]), at: timestamp)
        case "message":
            break
        case "web_search_call":
            let id = JSONHelpers.string(payload, keys: ["id", "call_id", "callId"]) ?? UUID().uuidString
            let status = JSONHelpers.string(payload, keys: ["status"]) ?? "running"
            let completedAt = status == "completed" ? timestamp : nil
            tools[id] = ToolCallSummary(
                id: id,
                name: "web search",
                status: status,
                startedAt: timestamp,
                completedAt: completedAt,
                ageSeconds: completedAt == nil ? timestamp.map { max(0, now.timeIntervalSince($0)) } : nil
            )
            toolOrder.append(id)
        default:
            break
        }
    }

    mutating func updateDates(_ date: Date) {
        if createdAt == nil || date < createdAt! {
            createdAt = date
        }
        if updatedAt == nil || date > updatedAt! {
            updatedAt = date
        }
    }

    mutating func closeTool(id: String?, at completedAt: Date?) {
        let key: String?
        if let id, tools[id] != nil {
            key = id
        } else {
            key = toolOrder.reversed().first { tools[$0]?.completedAt == nil }
        }
        guard let key, var tool = tools[key] else {
            return
        }
        tool.status = "completed"
        tool.completedAt = completedAt ?? updatedAt ?? now
        tool.ageSeconds = nil
        tools[key] = tool
    }

    func summary() -> AgentSummary? {
        let fileModified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        let lastActivityAt = [updatedAt, fileModified].compactMap { $0 }.max()
        let id = sessionID ?? fileURL.deletingPathExtension().lastPathComponent
        let fallbackTitle: String
        if let cwd {
            fallbackTitle = "Codex - \(AgentFormatters.formatPathBasename(cwd))"
        } else {
            fallbackTitle = "Codex - \(String(id.suffix(8)))"
        }
        let activeTool = toolOrder
            .compactMap { tools[$0] }
            .last(where: { $0.isIncomplete })

        return AgentSummary(
            id: id,
            provider: .codex,
            title: title?.isEmpty == false ? title! : fallbackTitle,
            cwd: cwd,
            status: didError ? .error : .unknown,
            startedAt: createdAt ?? fileModified,
            lastActivityAt: lastActivityAt,
            tokenUsage: tokenUsage,
            activeTool: activeTool,
            diagnostics: diagnostics
        )
    }
}
