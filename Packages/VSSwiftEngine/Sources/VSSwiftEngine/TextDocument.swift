import Foundation
import VSSwiftCore

/// A thread-safe document wrapping a ``TextBuffer`` plus a monotonically increasing
/// version. All mutations are serialized through the actor, guaranteeing data-race
/// freedom even under concurrent edits from multiple tasks.
public actor TextDocument {
    public private(set) var buffer: TextBuffer
    public private(set) var version: Int

    public init(_ text: String = "") {
        self.buffer = TextBuffer(text)
        self.version = 0
    }

    public var text: String { buffer.text }
    public var lineCount: Int { buffer.lineCount }

    @discardableResult
    public func insert(_ string: String, at position: TextPosition) -> TextPosition {
        let result = buffer.insert(string, at: position)
        version += 1
        return result
    }

    @discardableResult
    public func delete(_ range: VSSwiftRange) -> String {
        let removed = buffer.delete(range)
        version += 1
        return removed
    }

    /// Returns an immutable snapshot suitable for off-actor parsing (Sendable value).
    public func snapshot() -> DocumentSnapshot {
        DocumentSnapshot(version: version, buffer: buffer)
    }
}

/// An immutable, `Sendable` snapshot handed to background actors (parser, LSP).
public struct DocumentSnapshot: Sendable {
    public let version: Int
    public let buffer: TextBuffer

    public init(version: Int, buffer: TextBuffer) {
        self.version = version
        self.buffer = buffer
    }

    public var text: String { buffer.text }
}
