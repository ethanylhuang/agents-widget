import CoreServices
import Foundation

public enum AgentRefreshTrigger: Sendable, Equatable {
    case codexSessionsChanged
    case openCodeDatabaseChanged
    case processExited(Int32)

    var requiresDetailRefresh: Bool {
        switch self {
        case .codexSessionsChanged, .openCodeDatabaseChanged:
            true
        case .processExited:
            false
        }
    }
}

public protocol AgentEventSourcing: AnyObject, Sendable {
    func start(onEvent: @escaping @Sendable (AgentRefreshTrigger) -> Void)
    func stop()
}

public final class LocalAgentEventSource: AgentEventSourcing, @unchecked Sendable {
    private let codexSessionsURL: URL
    private let openCodeDatabaseURL: URL
    private let lock = NSLock()
    private var watchers: [FSEventPathWatcher] = []
    private var callback: (@Sendable (AgentRefreshTrigger) -> Void)?

    public init(
        codexSessionsURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"),
        openCodeDatabaseURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/opencode/opencode.db")
    ) {
        self.codexSessionsURL = codexSessionsURL
        self.openCodeDatabaseURL = openCodeDatabaseURL
    }

    public func start(onEvent: @escaping @Sendable (AgentRefreshTrigger) -> Void) {
        stop()
        lock.lock()
        callback = onEvent
        lock.unlock()

        var nextWatchers: [FSEventPathWatcher] = []
        if FileManager.default.fileExists(atPath: codexSessionsURL.path) {
            nextWatchers.append(FSEventPathWatcher(paths: [codexSessionsURL.path]) { [weak self] in
                self?.emit(.codexSessionsChanged)
            })
        }

        let openCodePaths = openCodeWatchPaths()
        if !openCodePaths.isEmpty {
            nextWatchers.append(FSEventPathWatcher(paths: openCodePaths) { [weak self] in
                self?.emit(.openCodeDatabaseChanged)
            })
        }

        lock.lock()
        watchers = nextWatchers
        lock.unlock()

        for watcher in nextWatchers {
            watcher.start()
        }
    }

    public func stop() {
        lock.lock()
        let currentWatchers = watchers
        watchers = []
        callback = nil
        lock.unlock()

        for watcher in currentWatchers {
            watcher.stop()
        }
    }

    private func openCodeWatchPaths() -> [String] {
        let candidates = [
            openCodeDatabaseURL,
            URL(fileURLWithPath: openCodeDatabaseURL.path + "-wal"),
            URL(fileURLWithPath: openCodeDatabaseURL.path + "-shm"),
            openCodeDatabaseURL.deletingLastPathComponent()
        ]
        return candidates
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(\.path)
    }

    private func emit(_ trigger: AgentRefreshTrigger) {
        lock.lock()
        let callback = callback
        lock.unlock()
        callback?(trigger)
    }
}

private final class FSEventPathWatcher: @unchecked Sendable {
    private let paths: [String]
    private let callback: @Sendable () -> Void
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var stream: FSEventStreamRef?

    init(paths: [String], callback: @escaping @Sendable () -> Void) {
        self.paths = paths
        self.callback = callback
        self.queue = DispatchQueue(label: "agents-widget.fsevents.\(UUID().uuidString)", qos: .utility)
    }

    deinit {
        stop()
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard stream == nil, !paths.isEmpty else {
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard let nextStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else {
                    return
                }
                let watcher = Unmanaged<FSEventPathWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.callback()
            },
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(nextStream, queue)
        if FSEventStreamStart(nextStream) {
            stream = nextStream
        } else {
            FSEventStreamInvalidate(nextStream)
            FSEventStreamRelease(nextStream)
        }
    }

    func stop() {
        lock.lock()
        let currentStream = stream
        stream = nil
        lock.unlock()

        guard let currentStream else {
            return
        }
        FSEventStreamStop(currentStream)
        FSEventStreamInvalidate(currentStream)
        FSEventStreamRelease(currentStream)
    }
}
