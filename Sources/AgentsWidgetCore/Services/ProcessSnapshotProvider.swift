import Darwin
import Foundation

public struct ProcessSnapshot: Equatable, Sendable {
    public var pid: Int32
    public var parentPid: Int32
    public var provider: AgentProvider
    public var tty: String?
    public var startedAt: Date?
    public var command: String
    public var cwd: String?

    public init(
        pid: Int32,
        parentPid: Int32,
        provider: AgentProvider,
        tty: String? = nil,
        startedAt: Date? = nil,
        command: String,
        cwd: String? = nil
    ) {
        self.pid = pid
        self.parentPid = parentPid
        self.provider = provider
        self.tty = tty
        self.startedAt = startedAt
        self.command = command
        self.cwd = cwd
    }
}

public protocol ProcessSnapshotProviding: Sendable {
    func snapshots() -> ProviderResult<[ProcessSnapshot]>
}

public final class ProcessSnapshotProvider: ProcessSnapshotProviding, @unchecked Sendable {
    private let cacheTTL: TimeInterval
    private let now: @Sendable () -> Date
    private let collector: (@Sendable () -> ProviderResult<[ProcessSnapshot]>)?
    private let cacheLock = NSLock()
    private var cache: ProcessSnapshotCache?

    public init(cacheTTL: TimeInterval = 1.0, now: @escaping @Sendable () -> Date = Date.init) {
        self.cacheTTL = cacheTTL
        self.now = now
        self.collector = nil
    }

    init(
        cacheTTL: TimeInterval,
        now: @escaping @Sendable () -> Date,
        collector: @escaping @Sendable () -> ProviderResult<[ProcessSnapshot]>
    ) {
        self.cacheTTL = cacheTTL
        self.now = now
        self.collector = collector
    }

    public func snapshots() -> ProviderResult<[ProcessSnapshot]> {
        let capturedAt = now()
        if let cached = cachedSnapshots(at: capturedAt) {
            return cached
        }

        let result: ProviderResult<[ProcessSnapshot]>
        if let collector {
            result = collector()
        } else {
            result = uncachedSnapshots()
        }
        storeCache(result, capturedAt: capturedAt)
        return result
    }

    private func uncachedSnapshots() -> ProviderResult<[ProcessSnapshot]> {
        var diagnostics: [String] = []
        var metrics = ProviderMetrics()

        metrics.processSyscalls += 1
        let output: String
        do {
            output = try ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/ps"),
                arguments: ["-axo", "pid=,ppid=,tty=,lstart=,command="],
                timeoutSeconds: 2
            )
        } catch {
            diagnostics.append(Diagnostics.process("ps failed: \(error.localizedDescription)"))
            return ProviderResult(value: [], diagnostics: diagnostics, metrics: metrics)
        }

        var snapshots = parsePSOutput(output, diagnostics: &diagnostics)
        for index in snapshots.indices {
            snapshots[index].cwd = cwd(for: snapshots[index].pid, metrics: &metrics)
        }
        return ProviderResult(value: snapshots, diagnostics: diagnostics, metrics: metrics)
    }

    private func cachedSnapshots(at date: Date) -> ProviderResult<[ProcessSnapshot]>? {
        guard cacheTTL > 0 else {
            return nil
        }
        cacheLock.lock()
        let cached = cache
        cacheLock.unlock()
        guard let cached, date.timeIntervalSince(cached.capturedAt) < cacheTTL else {
            return nil
        }
        return ProviderResult(
            value: cached.result.value,
            diagnostics: cached.result.diagnostics,
            metrics: .zero
        )
    }

    private func storeCache(_ result: ProviderResult<[ProcessSnapshot]>, capturedAt: Date) {
        guard cacheTTL > 0 else {
            return
        }
        cacheLock.lock()
        cache = ProcessSnapshotCache(capturedAt: capturedAt, result: result)
        cacheLock.unlock()
    }

    func cwd(for pid: Int32, metrics: inout ProviderMetrics) -> String? {
        metrics.processSyscalls += 1
        var info = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.stride
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: size) { rebound in
                proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, rebound, Int32(size))
            }
        }
        guard result == Int32(size) else {
            return nil
        }
        return string(from: info.pvi_cdir.vip_path)
    }

    func processIDs(metrics: inout ProviderMetrics) -> [Int32] {
        metrics.processSyscalls += 1
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else {
            return []
        }
        let count = Int(byteCount) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: count)
        metrics.processSyscalls += 1
        let usedBytes = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard usedBytes > 0 else {
            return []
        }
        let usedCount = min(pids.count, Int(usedBytes) / MemoryLayout<pid_t>.stride)
        var processIDs: [Int32] = []
        processIDs.reserveCapacity(usedCount)
        for index in 0..<usedCount where pids[index] > 0 {
            processIDs.append(Int32(pids[index]))
        }
        return processIDs
    }

    func snapshot(pid: Int32, diagnostics: inout [String], metrics: inout ProviderMetrics) -> ProcessSnapshot? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        metrics.processSyscalls += 1
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: size) { rebound in
                proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, rebound, Int32(size))
            }
        }
        guard result == Int32(size) else {
            return nil
        }

        return snapshot(
            pid: pid,
            parentPid: Int32(info.pbi_ppid),
            comm: string(from: info.pbi_comm),
            name: string(from: info.pbi_name),
            tty: ttyName(for: info.e_tdev),
            startedAt: startedAt(from: info),
            diagnostics: &diagnostics,
            processPathLookup: { processPath(pid: $0, metrics: &metrics) },
            cwdLookup: { cwd(for: $0, metrics: &metrics) }
        )
    }

    func snapshot(
        pid: Int32,
        parentPid: Int32,
        comm: String?,
        name: String?,
        tty: String?,
        startedAt: Date?,
        diagnostics: inout [String],
        processPathLookup: (Int32) -> String?,
        cwdLookup: (Int32) -> String?
    ) -> ProcessSnapshot? {
        guard let provider = Self.identifyProvider(command: comm ?? "")
            ?? Self.identifyProvider(command: name ?? "") else {
            return nil
        }

        let command = processPathLookup(pid) ?? name ?? comm ?? provider.rawValue

        return ProcessSnapshot(
            pid: pid,
            parentPid: parentPid,
            provider: provider,
            tty: tty,
            startedAt: startedAt,
            command: command,
            cwd: cwdLookup(pid)
        )
    }

    func processPath(pid: Int32, metrics: inout ProviderMetrics) -> String? {
        metrics.processSyscalls += 1
        var buffer = [CChar](repeating: 0, count: 4_096)
        let length = buffer.withUnsafeMutableBufferPointer { pointer in
            proc_pidpath(pid, pointer.baseAddress, UInt32(pointer.count))
        }
        guard length > 0 else {
            return nil
        }
        return buffer.withUnsafeBufferPointer { pointer in
            pointer.baseAddress.map { String(cString: $0) }
        }
    }

    func startedAt(from info: proc_bsdinfo) -> Date? {
        guard info.pbi_start_tvsec > 0 else {
            return nil
        }
        return Date(
            timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec)
                + TimeInterval(info.pbi_start_tvusec) / 1_000_000
        )
    }

    func ttyName(for device: UInt32) -> String? {
        guard device != 0, device != UInt32.max, let name = devname(dev_t(device), S_IFCHR) else {
            return nil
        }
        return "/dev/\(String(cString: name))"
    }

    func string<T>(from tuple: T) -> String? {
        withUnsafePointer(to: tuple) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { charPointer in
                guard charPointer.pointee != 0 else {
                    return nil
                }
                return String(cString: charPointer)
            }
        }
    }

    func parsePSOutput(_ output: String, diagnostics: inout [String]) -> [ProcessSnapshot] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                parsePSLine(String(line), diagnostics: &diagnostics)
            }
    }

    func parsePSLine(_ line: String, diagnostics: inout [String]) -> ProcessSnapshot? {
        let columns = line.split(maxSplits: 8, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
        guard columns.count >= 9,
              let pid = Int32(columns[0]),
              let parentPid = Int32(columns[1]) else {
            return nil
        }
        let command = String(columns[8])
        guard let provider = Self.identifyProvider(command: command) else {
            return nil
        }

        let dateText = "\(columns[3]) \(columns[4]) \(columns[5]) \(columns[6]) \(columns[7])"
        let startedAt = Self.parsePSDate(dateText)
        if startedAt == nil {
            diagnostics.append(Diagnostics.process("Could not parse start date for PID \(pid)"))
        }

        return ProcessSnapshot(
            pid: pid,
            parentPid: parentPid,
            provider: provider,
            tty: Self.normalizedTTY(String(columns[2])),
            startedAt: startedAt,
            command: command
        )
    }

    static func identifyProvider(command: String) -> AgentProvider? {
        if command.contains(" app-server") {
            return nil
        }
        guard let firstToken = command.split(separator: " ").first else {
            return nil
        }
        let executable = URL(fileURLWithPath: String(firstToken)).lastPathComponent
        if executable == "codex" {
            return .codex
        }
        if executable == "opencode" {
            return .opencode
        }
        return nil
    }

    public static func normalizedTTY(_ raw: String?) -> String? {
        guard var raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, raw != "??" else {
            return nil
        }
        if raw.hasPrefix("/dev/") {
            return raw
        }
        if raw.hasPrefix("tty") {
            return "/dev/\(raw)"
        }
        if raw.hasPrefix("s") {
            raw = "tty\(raw)"
            return "/dev/\(raw)"
        }
        return "/dev/\(raw)"
    }

    static func parsePSDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter.date(from: text)
    }
}

private struct ProcessSnapshotCache: Sendable {
    var capturedAt: Date
    var result: ProviderResult<[ProcessSnapshot]>
}

enum ProcessRunner {
    static func run(executableURL: URL, arguments: [String], timeoutSeconds: TimeInterval? = nil) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()

        let group = DispatchGroup()
        let outputDrain = PipeDrain(handle: output.fileHandleForReading)
        let errorDrain = PipeDrain(handle: error.fileHandleForReading)
        outputDrain.start(group: group)
        errorDrain.start(group: group)

        if let timeoutSeconds {
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                group.wait()
                throw ProcessError.timedOut
            }
        } else {
            process.waitUntilExit()
        }
        group.wait()

        if process.terminationStatus != 0 {
            let message = String(data: errorDrain.data, encoding: .utf8) ?? "exit \(process.terminationStatus)"
            throw ProcessError.failed(message)
        }
        return String(data: outputDrain.data, encoding: .utf8) ?? ""
    }
}

final class PipeDrain: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var storage = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func start(group: DispatchGroup) {
        group.enter()
        DispatchQueue.global(qos: .utility).async { [self] in
            let readData = handle.readDataToEndOfFile()
            lock.lock()
            storage = readData
            lock.unlock()
            group.leave()
        }
    }
}

enum ProcessError: LocalizedError {
    case failed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            message
        case .timedOut:
            "timed out"
        }
    }
}
