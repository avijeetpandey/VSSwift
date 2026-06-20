import Foundation

/// Application-wide events broadcast on a decoupled bus. Subsystems publish and
/// subscribe without holding direct references to one another.
public enum AppEvent: Sendable, Equatable {
    case fileOpened(URL)
    case fileClosed(URL)
    case fileSaved(URL)
    case fileSystemChanged([URL])
    case themeChanged(String)
    case languageServerStateChanged(String)
    case diagnosticsUpdated(URL)
    case activeDocumentChanged(URL?)
}

/// A multi-subscriber event bus built on `AsyncStream`. Each subscriber gets its
/// own stream; publishing is non-blocking and safe from any task.
public actor EventBus {
    private var continuations: [UUID: AsyncStream<AppEvent>.Continuation] = [:]

    public init() {}

    /// Subscribes to all future events. The returned stream finishes when the
    /// caller stops iterating and the task is cancelled.
    public func subscribe() -> AsyncStream<AppEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id) }
            }
        }
    }

    public func publish(_ event: AppEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        continuations[id] = nil
    }

    public var subscriberCount: Int { continuations.count }
}
