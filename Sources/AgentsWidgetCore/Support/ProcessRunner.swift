import Foundation

public enum ProcessRunner {
    public static func run(executableURL: URL, arguments: [String], timeoutSeconds: TimeInterval? = nil) throws -> String {
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
