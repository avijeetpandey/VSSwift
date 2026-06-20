import Foundation
#if canImport(CoreServices)
import CoreServices
#endif

/// Watches one or more directory trees for changes using native macOS FSEvents,
/// delivering coalesced change notifications on a background queue via an
/// `AsyncStream`. The UI subscribes and refreshes affected subtrees off the hot path.
public final class FileSystemWatcher: @unchecked Sendable {
    private let paths: [String]
    private let latency: TimeInterval
    private let queue = DispatchQueue(label: "com.vsswift.fswatcher", qos: .utility)

    private var stream: FSEventStreamRef?
    private var infoPointer: UnsafeMutableRawPointer?
    private var continuation: AsyncStream<[URL]>.Continuation?

    /// A stream of batches of changed file URLs.
    public let changes: AsyncStream<[URL]>

    public init(paths: [URL], latency: TimeInterval = 0.2) {
        self.paths = paths.map { $0.path }
        self.latency = latency
        var cont: AsyncStream<[URL]>.Continuation!
        self.changes = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        self.continuation = cont
    }

    fileprivate func emit(_ urls: [URL]) {
        continuation?.yield(urls)
    }

    public func start() {
        guard stream == nil, !paths.isEmpty else { return }
        let info = Unmanaged.passRetained(self).toOpaque()
        self.infoPointer = info
        var context = FSEventStreamContext(version: 0, info: info, retain: nil, release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = { _, clientInfo, numEvents, eventPaths, _, _ in
            guard let clientInfo else { return }
            let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
            let cPaths = eventPaths.assumingMemoryBound(to: UnsafeMutableRawPointer.self)
            var urls: [URL] = []
            for i in 0..<numEvents {
                let cString = cPaths[i].assumingMemoryBound(to: CChar.self)
                urls.append(URL(fileURLWithPath: String(cString: cString)))
            }
            if !urls.isEmpty { watcher.emit(urls) }
        }

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency, flags) else {
            // Balance the retain if creation failed.
            Unmanaged<FileSystemWatcher>.fromOpaque(info).release()
            self.infoPointer = nil
            return
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        if let info = infoPointer {
            Unmanaged<FileSystemWatcher>.fromOpaque(info).release()
            self.infoPointer = nil
        }
        continuation?.finish()
    }

    deinit { stop() }
}
