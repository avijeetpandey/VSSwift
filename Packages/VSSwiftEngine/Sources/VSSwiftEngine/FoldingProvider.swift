import Foundation
import VSSwiftCore

/// A collapsible region of lines `[startLine, endLine]` (inclusive).
public struct FoldingRange: Sendable, Hashable {
    public var startLine: Int
    public var endLine: Int
    public var kind: Kind

    public enum Kind: Sendable, Hashable { case indentation, brackets, comment }

    public init(startLine: Int, endLine: Int, kind: Kind = .indentation) {
        self.startLine = startLine
        self.endLine = endLine
        self.kind = kind
    }

    public var lineCount: Int { endLine - startLine + 1 }
}

/// Computes folding ranges using indentation levels and bracket scope scanning,
/// mirroring VSCode's indentation-based folding strategy.
public struct FoldingProvider: Sendable {
    public var tabSize: Int

    public init(tabSize: Int = 4) {
        self.tabSize = tabSize
    }

    /// Visible (non-blank) indentation width of a line, or nil if blank.
    private func indentWidth(_ line: String) -> Int? {
        var width = 0
        for ch in line {
            if ch == " " { width += 1 }
            else if ch == "\t" { width += tabSize }
            else { return width }
        }
        return nil // blank line
    }

    /// Indentation-based folding: a line folds the following block of more-indented
    /// lines (trailing blank lines are excluded), matching VSCode semantics.
    public func indentationRanges(for buffer: TextBuffer) -> [FoldingRange] {
        let lines = buffer.lines
        let n = lines.count
        var indents = [Int?](repeating: nil, count: n)
        for i in 0..<n { indents[i] = indentWidth(lines[i]) }

        var ranges: [FoldingRange] = []
        for i in 0..<n {
            guard let baseIndent = indents[i] else { continue }
            var j = i + 1
            var lastNonBlank = i
            while j < n {
                if let childIndent = indents[j] {
                    if childIndent > baseIndent {
                        lastNonBlank = j
                        j += 1
                    } else {
                        break
                    }
                } else {
                    j += 1 // blank line: tentatively include, but don't extend lastNonBlank
                }
            }
            if lastNonBlank > i {
                ranges.append(FoldingRange(startLine: i, endLine: lastNonBlank, kind: .indentation))
            }
        }
        return ranges
    }

    /// Bracket-based folding for `{}`, `[]`, `()` spanning multiple lines.
    /// Ignores brackets inside string/char literals and line comments (best-effort).
    public func bracketRanges(for buffer: TextBuffer) -> [FoldingRange] {
        var stack: [(char: Character, line: Int)] = []
        let pairs: [Character: Character] = ["}": "{", "]": "[", ")": "("]
        let openers: Set<Character> = ["{", "[", "("]
        var ranges: [FoldingRange] = []

        for (lineIndex, line) in buffer.lines.enumerated() {
            var inString = false
            var stringDelim: Character = "\""
            var prev: Character? = nil
            let chars: [Character] = Array(line)
            var k = 0
            while k < chars.count {
                let ch = chars[k]
                if inString {
                    if ch == stringDelim && prev != "\\" { inString = false }
                } else if ch == "\"" || ch == "'" {
                    inString = true; stringDelim = ch
                } else if ch == "/" && k + 1 < chars.count && chars[k + 1] == "/" {
                    break // rest of line is a comment
                } else if openers.contains(ch) {
                    stack.append((ch, lineIndex))
                } else if let opener = pairs[ch] {
                    if let top = stack.last, top.char == opener {
                        stack.removeLast()
                        if lineIndex > top.line {
                            ranges.append(FoldingRange(startLine: top.line, endLine: lineIndex, kind: .brackets))
                        }
                    }
                }
                prev = ch
                k += 1
            }
        }
        return ranges.sorted { $0.startLine < $1.startLine }
    }

    /// Combined folding ranges (indentation + brackets), de-duplicated by start line
    /// preferring the larger region.
    public func foldingRanges(for buffer: TextBuffer) -> [FoldingRange] {
        let all = indentationRanges(for: buffer) + bracketRanges(for: buffer)
        var byStart: [Int: FoldingRange] = [:]
        for r in all {
            if let existing = byStart[r.startLine] {
                if r.lineCount > existing.lineCount { byStart[r.startLine] = r }
            } else {
                byStart[r.startLine] = r
            }
        }
        return byStart.values.sorted { $0.startLine < $1.startLine }
    }
}

/// Tracks which folding ranges are currently collapsed and which lines are hidden.
public struct FoldingState: Sendable {
    public private(set) var collapsed: Set<Int> = [] // start lines that are collapsed
    private var ranges: [Int: FoldingRange] = [:]

    public init(ranges: [FoldingRange] = []) {
        for r in ranges { self.ranges[r.startLine] = r }
    }

    public mutating func setRanges(_ ranges: [FoldingRange]) {
        self.ranges = [:]
        for r in ranges { self.ranges[r.startLine] = r }
        collapsed = collapsed.intersection(Set(self.ranges.keys))
    }

    public mutating func toggle(startLine: Int) {
        guard ranges[startLine] != nil else { return }
        if collapsed.contains(startLine) { collapsed.remove(startLine) }
        else { collapsed.insert(startLine) }
    }

    public mutating func collapse(startLine: Int) {
        if ranges[startLine] != nil { collapsed.insert(startLine) }
    }

    public mutating func expand(startLine: Int) { collapsed.remove(startLine) }

    /// The set of line indices hidden by currently-collapsed ranges. The start line
    /// of a fold stays visible (showing the "…" indicator); inner lines are hidden.
    public func hiddenLines() -> Set<Int> {
        var hidden = Set<Int>()
        for startLine in collapsed {
            guard let range = ranges[startLine] else { continue }
            if range.endLine > range.startLine {
                for line in (range.startLine + 1)...range.endLine { hidden.insert(line) }
            }
        }
        return hidden
    }

    public func isCollapsed(startLine: Int) -> Bool { collapsed.contains(startLine) }
}
