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

public struct ProcessSnapshotProvider: ProcessSnapshotProviding {
    public init() {}

    public func snapshots() -> ProviderResult<[ProcessSnapshot]> {
        do {
            let output = try ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/ps"),
                arguments: ["-axo", "pid=,ppid=,tty=,lstart=,command="]
            )
            var diagnostics: [String] = []
            var snapshots = parsePSOutput(output, diagnostics: &diagnostics)
            for index in snapshots.indices {
                snapshots[index].cwd = cwd(for: snapshots[index].pid)
            }
            return ProviderResult(value: snapshots, diagnostics: diagnostics)
        } catch {
            return ProviderResult(value: [], diagnostics: [Diagnostics.process("ps failed: \(error.localizedDescription)")])
        }
    }

    func cwd(for pid: Int32) -> String? {
        do {
            let output = try ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/sbin/lsof"),
                arguments: ["-a", "-p", String(pid), "-d", "cwd", "-Fn"],
                timeoutSeconds: 0.25
            )
            return output
                .split(separator: "\n")
                .first(where: { $0.hasPrefix("n/") })
                .map { String($0.dropFirst()) }
        } catch {
            return nil
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
