import Foundation

public protocol CodexSessionStoring: Sendable {
    func summaries(now: Date) -> ProviderResult<[AgentSummary]>
}

public final class CodexSessionStore: CodexSessionStoring, ModeAwareCodexSessionStoring, @unchecked Sendable {
    let baseURL: URL
    let maxFiles: Int
    let boundedFileLimit: Int
    let coldParseByteLimit: Int
    let prefixWindowBytes: Int
    let tailWindowBytes: Int
    private let cacheLock = NSLock()
    private var summaryCache: [String: CodexCachedSummary] = [:]

    public init(
        baseURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"),
        maxFiles: Int = 50,
        boundedFileLimit: Int = 12,
        coldParseByteLimit: Int = 262_144,
        prefixWindowBytes: Int = 16_384,
        tailWindowBytes: Int = 131_072
    ) {
        self.baseURL = baseURL
        self.maxFiles = maxFiles
        self.boundedFileLimit = boundedFileLimit
        self.coldParseByteLimit = coldParseByteLimit
        self.prefixWindowBytes = prefixWindowBytes
        self.tailWindowBytes = tailWindowBytes
    }

    public func summaries(now: Date) -> ProviderResult<[AgentSummary]> {
        summaries(now: now, mode: .bounded)
    }

    public func summaries(now: Date, mode: SessionRefreshMode) -> ProviderResult<[AgentSummary]> {
        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return ProviderResult(value: [], diagnostics: [Diagnostics.codex("session directory unavailable")])
        }

        let files = jsonlFiles()
        var diagnostics: [String] = []
        var summaries: [AgentSummary] = []
        var metrics = ProviderMetrics()
        let fileLimit = mode == .bounded ? min(maxFiles, boundedFileLimit) : maxFiles
        let selectedFiles = Array(files.prefix(fileLimit))
        pruneCache(keeping: selectedFiles)
        for file in selectedFiles {
            let metadata = metadata(for: file)
            let result = summary(for: file, metadata: metadata, now: now, mode: mode, metrics: &metrics)
            diagnostics.append(contentsOf: result.diagnostics)
            if let summary = result.value {
                summaries.append(summary)
            }
        }
        return ProviderResult(value: summaries, diagnostics: diagnostics, metrics: metrics)
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

    private func summary(
        for url: URL,
        metadata: CodexFileMetadata?,
        now: Date,
        mode: SessionRefreshMode,
        metrics: inout ProviderMetrics
    ) -> ProviderResult<AgentSummary?> {
        if let cached = cachedSummary(for: url, metadata: metadata, now: now, mode: mode) {
            return cached
        }

        if mode == .bounded,
           let metadata,
           let size = metadata.size,
           let cached = cachedEntry(for: url),
           size > cached.cursorOffset {
            let result = parseAppendedBytes(
                url,
                cached: cached,
                metadata: metadata,
                now: now,
                metrics: &metrics
            )
            storeCachedSummary(for: url, metadata: metadata, parsed: result)
            return result.providerResult
        }

        let result = parseFile(url, metadata: metadata, now: now, mode: mode, metrics: &metrics)
        storeCachedSummary(for: url, metadata: metadata, parsed: result)
        return result.providerResult
    }

    private func cachedEntry(for url: URL) -> CodexCachedSummary? {
        cacheLock.lock()
        let cached = summaryCache[url.path]
        cacheLock.unlock()
        return cached
    }

    private func cachedSummary(
        for url: URL,
        metadata: CodexFileMetadata?,
        now: Date,
        mode: SessionRefreshMode
    ) -> ProviderResult<AgentSummary?>? {
        guard let metadata else {
            return nil
        }
        let cached = cachedEntry(for: url)
        guard let cached, cached.metadata == metadata else {
            return nil
        }
        var parser = cached.parser
        parser.now = now
        return ProviderResult(
            value: parser.summary()?.refreshedDynamicFields(now: now),
            diagnostics: parser.diagnostics
        )
    }

    private func storeCachedSummary(
        for url: URL,
        metadata: CodexFileMetadata?,
        parsed: CodexParsedSummary
    ) {
        guard let metadata, let parser = parsed.parser else {
            return
        }
        cacheLock.lock()
        summaryCache[url.path] = CodexCachedSummary(
            metadata: metadata,
            parser: parser,
            cursorOffset: parsed.cursorOffset,
            pendingFragment: parsed.pendingFragment,
            isCompleteParse: parsed.isCompleteParse
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

    private func parseFile(
        _ url: URL,
        metadata: CodexFileMetadata?,
        now: Date,
        mode: SessionRefreshMode,
        metrics: inout ProviderMetrics
    ) -> CodexParsedSummary {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return CodexParsedSummary(
                parser: nil,
                cursorOffset: metadata?.size ?? 0,
                pendingFragment: "",
                isCompleteParse: false,
                providerResult: ProviderResult(value: nil, diagnostics: [Diagnostics.codex("could not read \(url.lastPathComponent)")])
            )
        }
        defer { try? handle.close() }

        if let size = metadata?.size,
           size > Int64(coldParseByteLimit) {
            return parseColdWindow(url, handle: handle, fileSize: size, now: now, metrics: &metrics)
        }

        let data = handle.readDataToEndOfFile()
        metrics.bytesRead += Int64(data.count)
        metrics.filesParsed += 1
        guard let text = String(data: data, encoding: .utf8) else {
            return CodexParsedSummary(
                parser: nil,
                cursorOffset: metadata?.size ?? Int64(data.count),
                pendingFragment: "",
                isCompleteParse: false,
                providerResult: ProviderResult(value: nil, diagnostics: [Diagnostics.codex("non-UTF8 session \(url.lastPathComponent)")])
            )
        }

        var parser = CodexSessionParser(fileURL: url, now: now)
        parseCompleteLines(text, parser: &parser)
        return CodexParsedSummary(
            parser: parser,
            cursorOffset: metadata?.size ?? Int64(data.count),
            pendingFragment: "",
            isCompleteParse: true,
            providerResult: ProviderResult(value: parser.summary(), diagnostics: parser.diagnostics)
        )
    }

    private func parseColdWindow(
        _ url: URL,
        handle: FileHandle,
        fileSize: Int64,
        now: Date,
        metrics: inout ProviderMetrics
    ) -> CodexParsedSummary {
        var parser = CodexSessionParser(fileURL: url, now: now)
        var diagnostics: [String] = []
        let prefixLength = min(prefixWindowBytes, Int(fileSize))
        let tailLength = min(tailWindowBytes, Int(fileSize))
        let tailOffset = max(Int64(prefixLength), fileSize - Int64(tailLength))

        do {
            try handle.seek(toOffset: 0)
            let prefix = handle.readData(ofLength: prefixLength)
            metrics.bytesRead += Int64(prefix.count)
            if let text = String(data: prefix, encoding: .utf8) {
                parseCompleteLines(prefixLength < Int(fileSize) ? trimTrailingPartialLine(text) : text, parser: &parser)
            } else {
                diagnostics.append(Diagnostics.codex("non-UTF8 session prefix \(url.lastPathComponent)"))
            }

            if tailOffset < fileSize {
                try handle.seek(toOffset: UInt64(tailOffset))
                let tail = handle.readDataToEndOfFile()
                metrics.bytesRead += Int64(tail.count)
                if let text = String(data: tail, encoding: .utf8) {
                    parseCompleteLines(trimLeadingPartialLine(text), parser: &parser)
                } else {
                    diagnostics.append(Diagnostics.codex("non-UTF8 session tail \(url.lastPathComponent)"))
                }
            }
        } catch {
            diagnostics.append(Diagnostics.codex("could not seek \(url.lastPathComponent): \(error.localizedDescription)"))
        }

        metrics.filesParsed += 1
        parser.diagnostics.append(contentsOf: diagnostics)
        return CodexParsedSummary(
            parser: parser,
            cursorOffset: fileSize,
            pendingFragment: "",
            isCompleteParse: false,
            providerResult: ProviderResult(value: parser.summary(), diagnostics: parser.diagnostics)
        )
    }

    private func parseAppendedBytes(
        _ url: URL,
        cached: CodexCachedSummary,
        metadata: CodexFileMetadata,
        now: Date,
        metrics: inout ProviderMetrics
    ) -> CodexParsedSummary {
        guard let size = metadata.size, size > cached.cursorOffset else {
            var parser = cached.parser
            parser.now = now
            return CodexParsedSummary(
                parser: parser,
                cursorOffset: cached.cursorOffset,
                pendingFragment: cached.pendingFragment,
                isCompleteParse: cached.isCompleteParse,
                providerResult: ProviderResult(value: parser.summary()?.refreshedDynamicFields(now: now), diagnostics: parser.diagnostics)
            )
        }

        var parser = cached.parser
        parser.now = now
        var pendingFragment = cached.pendingFragment
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return CodexParsedSummary(
                parser: parser,
                cursorOffset: cached.cursorOffset,
                pendingFragment: pendingFragment,
                isCompleteParse: cached.isCompleteParse,
                providerResult: ProviderResult(value: parser.summary()?.refreshedDynamicFields(now: now), diagnostics: parser.diagnostics + [Diagnostics.codex("could not read appended bytes \(url.lastPathComponent)")])
            )
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: UInt64(cached.cursorOffset))
            let data = handle.readDataToEndOfFile()
            metrics.bytesRead += Int64(data.count)
            metrics.filesParsed += 1
            guard let text = String(data: data, encoding: .utf8) else {
                parser.diagnostics.append(Diagnostics.codex("non-UTF8 session append \(url.lastPathComponent)"))
                return CodexParsedSummary(
                    parser: parser,
                    cursorOffset: size,
                    pendingFragment: "",
                    isCompleteParse: cached.isCompleteParse,
                    providerResult: ProviderResult(value: parser.summary()?.refreshedDynamicFields(now: now), diagnostics: parser.diagnostics)
                )
            }
            pendingFragment = parseAppendedText(pendingFragment + text, parser: &parser)
        } catch {
            parser.diagnostics.append(Diagnostics.codex("could not seek append \(url.lastPathComponent): \(error.localizedDescription)"))
        }

        return CodexParsedSummary(
            parser: parser,
            cursorOffset: size,
            pendingFragment: pendingFragment,
            isCompleteParse: cached.isCompleteParse,
            providerResult: ProviderResult(value: parser.summary()?.refreshedDynamicFields(now: now), diagnostics: parser.diagnostics)
        )
    }

    private func parseCompleteLines(_ text: String, parser: inout CodexSessionParser) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            parser.parseLine(String(line).trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
        }
    }

    private func parseAppendedText(_ text: String, parser: inout CodexSessionParser) -> String {
        guard !text.isEmpty else {
            return ""
        }
        let hasTrailingNewline = text.hasSuffix("\n") || text.hasSuffix("\r")
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let pending = hasTrailingNewline ? "" : (lines.popLast() ?? "")
        for line in lines {
            parser.parseLine(line.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
        }
        return pending
    }

    private func trimLeadingPartialLine(_ text: String) -> String {
        guard let newlineIndex = text.firstIndex(of: "\n") else {
            return ""
        }
        return String(text[text.index(after: newlineIndex)...])
    }

    private func trimTrailingPartialLine(_ text: String) -> String {
        guard let newlineIndex = text.lastIndex(of: "\n") else {
            return ""
        }
        return String(text[...newlineIndex])
    }
}

private struct CodexFileMetadata: Equatable, Sendable {
    var modifiedAt: Date?
    var size: Int64?
}

private struct CodexCachedSummary: Sendable {
    var metadata: CodexFileMetadata
    var parser: CodexSessionParser
    var cursorOffset: Int64
    var pendingFragment: String
    var isCompleteParse: Bool
}

private struct CodexParsedSummary: Sendable {
    var parser: CodexSessionParser?
    var cursorOffset: Int64
    var pendingFragment: String
    var isCompleteParse: Bool
    var providerResult: ProviderResult<AgentSummary?>
}

struct CodexSessionParser: Sendable {
    let fileURL: URL
    var now: Date
    var diagnostics: [String] = []
    var sessionID: String?
    var cwd: String?
    var title: String?
    var createdAt: Date?
    var updatedAt: Date?
    var tokenUsage: TokenUsage?
    var didError = false
    fileprivate var activity: ProviderActivity = .unknown
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
            || line.contains("\"custom_tool_call\"")
            || line.contains("\"custom_tool_call_output\"")
            || line.contains("\"tool_search_call\"")
            || line.contains("\"tool_search_output\"")
            || line.contains("\"web_search_call\"")
            || line.contains("\"web_search_end\"")
    }

    mutating func parseEventMessage(_ payload: JSONDictionary, timestamp: Date?) {
        let eventType = JSONHelpers.string(payload, keys: ["type"])
        switch eventType {
        case "task_started":
            activity = .active
            title = title ?? JSONHelpers.string(payload, keys: ["title", "summary"]).map { JSONHelpers.truncatedTitle($0) }
        case "task_complete":
            activity = .finished
        case "turn_aborted":
            if hasErrorMarker(payload) {
                didError = true
                activity = .errored
            } else {
                activity = .finished
            }
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
                activity = .errored
            }
            closeTool(id: JSONHelpers.string(payload, keys: ["call_id", "callId", "id"]), at: timestamp)
        default:
            if eventType?.localizedCaseInsensitiveContains("error") == true || hasErrorMarker(payload) {
                didError = true
                activity = .errored
            }
            break
        }
    }

    mutating func parseResponseItem(_ payload: JSONDictionary, timestamp: Date?) {
        let itemType = JSONHelpers.string(payload, keys: ["type"])
        switch itemType {
        case "function_call":
            startTool(
                id: JSONHelpers.string(payload, keys: ["call_id", "callId", "id"]),
                name: JSONHelpers.string(payload, keys: ["name"]) ?? "tool",
                status: JSONHelpers.string(payload, keys: ["status"]) ?? "running",
                at: timestamp
            )
        case "function_call_output":
            if JSONHelpers.string(payload, keys: ["error"]) != nil {
                didError = true
                activity = .errored
            }
            closeTool(id: JSONHelpers.string(payload, keys: ["call_id", "callId", "id"]), at: timestamp)
        case "custom_tool_call":
            startTool(
                id: JSONHelpers.string(payload, keys: ["call_id", "callId", "id"]),
                name: JSONHelpers.string(payload, keys: ["name"]) ?? "custom tool",
                status: JSONHelpers.string(payload, keys: ["status"]) ?? "running",
                at: timestamp
            )
        case "custom_tool_call_output":
            if hasErrorMarker(payload) {
                didError = true
                activity = .errored
            }
            closeTool(id: JSONHelpers.string(payload, keys: ["call_id", "callId", "id"]), at: timestamp)
        case "tool_search_call":
            startTool(
                id: JSONHelpers.string(payload, keys: ["call_id", "callId", "id"]),
                name: "tool search",
                status: JSONHelpers.string(payload, keys: ["status"]) ?? "running",
                at: timestamp
            )
        case "tool_search_output":
            if hasErrorMarker(payload) {
                didError = true
                activity = .errored
            }
            closeTool(id: JSONHelpers.string(payload, keys: ["call_id", "callId", "id"]), at: timestamp)
        case "message":
            break
        case "web_search_call":
            let status = JSONHelpers.string(payload, keys: ["status"]) ?? "running"
            startTool(
                id: JSONHelpers.string(payload, keys: ["id", "call_id", "callId"]),
                name: "web search",
                status: status,
                at: timestamp
            )
            if status == "completed" {
                closeTool(id: JSONHelpers.string(payload, keys: ["id", "call_id", "callId"]), at: timestamp)
            }
        case "web_search_end":
            closeTool(id: JSONHelpers.string(payload, keys: ["id", "call_id", "callId"]), at: timestamp)
        default:
            if hasErrorMarker(payload) {
                didError = true
                activity = .errored
            }
            break
        }
    }

    mutating func startTool(id: String?, name: String, status: String, at timestamp: Date?) {
        activity = .active
        let key = id ?? UUID().uuidString
        let completedAt = status.lowercased() == "completed" ? timestamp : nil
        tools[key] = ToolCallSummary(
            id: key,
            name: name,
            status: status,
            startedAt: timestamp,
            completedAt: completedAt,
            ageSeconds: completedAt == nil ? timestamp.map { max(0, now.timeIntervalSince($0)) } : nil
        )
        if !toolOrder.contains(key) {
            toolOrder.append(key)
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

    func hasErrorMarker(_ payload: JSONDictionary) -> Bool {
        if payload["error"] != nil {
            return true
        }
        if JSONHelpers.string(payload, keys: ["status", "reason"])?.localizedCaseInsensitiveContains("error") == true {
            return true
        }
        if JSONHelpers.string(payload, keys: ["message"])?.localizedCaseInsensitiveContains("error") == true {
            return true
        }
        return false
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
            status: didError ? .error : activity.agentStatus,
            startedAt: createdAt ?? fileModified,
            lastActivityAt: lastActivityAt,
            tokenUsage: tokenUsage,
            activeTool: activeTool,
            diagnostics: diagnostics
        )
    }
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
}
