import Foundation
import VSSwiftCore

/// A line-oriented text buffer with value semantics.
///
/// Columns and offsets are measured in `Character`s (extended grapheme clusters).
/// Lines are stored without their trailing newline; `lineCount` is always >= 1.
public struct TextBuffer: Sendable, Equatable {
    public private(set) var lines: [String]

    public init(_ text: String = "") {
        // Split on "\n" preserving a trailing empty line if the text ends with a newline.
        self.lines = text.isEmpty ? [""] : text.components(separatedBy: "\n")
    }

    public init(lines: [String]) {
        self.lines = lines.isEmpty ? [""] : lines
    }

    public var lineCount: Int { lines.count }

    public var text: String { lines.joined(separator: "\n") }

    public func line(at index: Int) -> String {
        precondition(index >= 0 && index < lines.count, "line index out of range")
        return lines[index]
    }

    public func lineLength(at index: Int) -> Int { lines[index].count }

    /// Clamps a position to a valid location within the buffer.
    public func clamp(_ position: TextPosition) -> TextPosition {
        let line = position.line.clamped(to: 0...(lines.count - 1))
        let col = position.column.clamped(to: 0...lines[line].count)
        return TextPosition(line: line, column: col)
    }

    private func index(in line: String, column: Int) -> String.Index {
        line.index(line.startIndex, offsetBy: column.clamped(to: 0...line.count))
    }

    /// Inserts `string` at `position`, returning the position immediately after the inserted text.
    @discardableResult
    public mutating func insert(_ string: String, at position: TextPosition) -> TextPosition {
        let p = clamp(position)
        let insertedLines = string.components(separatedBy: "\n")
        let current = lines[p.line]
        let splitIndex = index(in: current, column: p.column)
        let prefix = String(current[current.startIndex..<splitIndex])
        let suffix = String(current[splitIndex...])

        if insertedLines.count == 1 {
            lines[p.line] = prefix + insertedLines[0] + suffix
            return TextPosition(line: p.line, column: p.column + insertedLines[0].count)
        } else {
            var newBlock: [String] = []
            newBlock.append(prefix + insertedLines[0])
            for i in 1..<(insertedLines.count - 1) { newBlock.append(insertedLines[i]) }
            let lastInserted = insertedLines[insertedLines.count - 1]
            newBlock.append(lastInserted + suffix)
            lines.replaceSubrange(p.line...p.line, with: newBlock)
            let endLine = p.line + insertedLines.count - 1
            return TextPosition(line: endLine, column: lastInserted.count)
        }
    }

    /// Deletes the text within `range`, returning the deleted substring.
    @discardableResult
    public mutating func delete(_ range: VSSwiftRange) -> String {
        let start = clamp(range.start)
        let end = clamp(range.end)
        guard start < end else { return "" }

        if start.line == end.line {
            let line = lines[start.line]
            let s = index(in: line, column: start.column)
            let e = index(in: line, column: end.column)
            let removed = String(line[s..<e])
            lines[start.line] = String(line[line.startIndex..<s]) + String(line[e...])
            return removed
        }

        let firstLine = lines[start.line]
        let lastLine = lines[end.line]
        let s = index(in: firstLine, column: start.column)
        let e = index(in: lastLine, column: end.column)

        var removed = String(firstLine[s...])
        for i in (start.line + 1)..<end.line { removed += "\n" + lines[i] }
        removed += "\n" + String(lastLine[lastLine.startIndex..<e])

        let merged = String(firstLine[firstLine.startIndex..<s]) + String(lastLine[e...])
        lines.replaceSubrange(start.line...end.line, with: [merged])
        return removed
    }

    /// Converts a position to an absolute character offset from the start of the buffer.
    public func offset(of position: TextPosition) -> Int {
        let p = clamp(position)
        var offset = 0
        for i in 0..<p.line { offset += lines[i].count + 1 } // +1 for the newline
        return offset + p.column
    }

    /// Converts an absolute character offset to a position.
    public func position(at offset: Int) -> TextPosition {
        var remaining = max(0, offset)
        for (i, line) in lines.enumerated() {
            if remaining <= line.count {
                return TextPosition(line: i, column: remaining)
            }
            remaining -= (line.count + 1)
        }
        let last = lines.count - 1
        return TextPosition(line: last, column: lines[last].count)
    }
}
