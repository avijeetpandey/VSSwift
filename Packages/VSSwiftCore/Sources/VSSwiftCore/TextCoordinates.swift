import Foundation

/// A zero-based line/column position within a text document.
public struct TextPosition: Sendable, Hashable, Comparable, Codable {
    public var line: Int
    public var column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    public static let zero = TextPosition(line: 0, column: 0)

    public static func < (lhs: TextPosition, rhs: TextPosition) -> Bool {
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.column < rhs.column
    }
}

/// A half-open range `[start, end)` of text positions.
public struct VSSwiftRange: Sendable, Hashable, Codable {
    public var start: TextPosition
    public var end: TextPosition

    public init(start: TextPosition, end: TextPosition) {
        if start <= end {
            self.start = start
            self.end = end
        } else {
            self.start = end
            self.end = start
        }
    }

    public init(line: Int, column: Int) {
        let p = TextPosition(line: line, column: column)
        self.init(start: p, end: p)
    }

    public var isEmpty: Bool { start == end }
    public var isSingleLine: Bool { start.line == end.line }

    public func contains(_ position: TextPosition) -> Bool {
        position >= start && position < end
    }

    /// Returns true if the two ranges overlap or touch (adjacent), so they can be merged.
    public func intersectsOrTouches(_ other: VSSwiftRange) -> Bool {
        !(end < other.start || other.end < start)
    }

    /// Returns the union of two overlapping/touching ranges.
    public func union(_ other: VSSwiftRange) -> VSSwiftRange {
        VSSwiftRange(start: Swift.min(start, other.start), end: Swift.max(end, other.end))
    }
}

/// An offset-based range `[location, location+length)` (UTF-16 code units, AppKit-friendly).
public struct OffsetRange: Sendable, Hashable, Codable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public var end: Int { location + length }
    public var isEmpty: Bool { length == 0 }
}
