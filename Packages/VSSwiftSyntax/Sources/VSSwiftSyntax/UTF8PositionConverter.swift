import Foundation
import VSSwiftCore

/// Converts absolute UTF-8 byte offsets (as produced by swift-syntax) into
/// ``TextPosition`` values (zero-based line, Character-based column).
struct UTF8PositionConverter {
    private let lineStartByteOffsets: [Int]
    private let lines: [Substring]
    private let source: String

    init(source: String) {
        self.source = source
        var starts: [Int] = [0]
        var byteCount = 0
        var lineSlices: [Substring] = []
        var lineStartIndex = source.startIndex
        var idx = source.startIndex
        while idx < source.endIndex {
            let ch = source[idx]
            if ch == "\n" {
                lineSlices.append(source[lineStartIndex..<idx])
                byteCount += String(ch).utf8.count
                starts.append(byteCount)
                lineStartIndex = source.index(after: idx)
            } else {
                byteCount += String(ch).utf8.count
            }
            idx = source.index(after: idx)
        }
        lineSlices.append(source[lineStartIndex..<source.endIndex])
        self.lineStartByteOffsets = starts
        self.lines = lineSlices
    }

    /// Maps a UTF-8 byte offset to a position. Columns are Character counts.
    func position(utf8Offset: Int) -> TextPosition {
        // Binary search for the line whose start byte offset is <= utf8Offset.
        var lo = 0, hi = lineStartByteOffsets.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStartByteOffsets[mid] <= utf8Offset { lo = mid } else { hi = mid - 1 }
        }
        let line = lo
        let byteWithinLine = utf8Offset - lineStartByteOffsets[line]
        let column = characterColumn(inLine: line, utf8Within: byteWithinLine)
        return TextPosition(line: line, column: column)
    }

    private func characterColumn(inLine line: Int, utf8Within: Int) -> Int {
        guard line < lines.count else { return 0 }
        let text = lines[line]
        var consumedBytes = 0
        var column = 0
        var i = text.startIndex
        while i < text.endIndex && consumedBytes < utf8Within {
            consumedBytes += String(text[i]).utf8.count
            column += 1
            i = text.index(after: i)
        }
        return column
    }
}
