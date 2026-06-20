import Foundation
import VSSwiftCore

/// Manages a set of discontinuous selections/cursors for multi-cursor editing.
///
/// Invariant: selections are always kept sorted ascending and non-overlapping
/// (overlapping or touching selections are merged). The first selection is the
/// "primary" cursor.
public struct SelectionManager: Sendable, Equatable {
    public private(set) var selections: [VSSwiftRange]

    public init(_ selections: [VSSwiftRange] = [VSSwiftRange(line: 0, column: 0)]) {
        self.selections = selections.isEmpty ? [VSSwiftRange(line: 0, column: 0)] : selections
        normalize()
    }

    public var primary: VSSwiftRange { selections[0] }
    public var count: Int { selections.count }

    /// Replaces all selections with a single one.
    public mutating func setPrimary(_ range: VSSwiftRange) {
        selections = [range]
    }

    /// Adds an additional cursor/selection, merging if it overlaps an existing one.
    public mutating func addCursor(_ range: VSSwiftRange) {
        selections.append(range)
        normalize()
    }

    public mutating func setSelections(_ ranges: [VSSwiftRange]) {
        selections = ranges.isEmpty ? [VSSwiftRange(line: 0, column: 0)] : ranges
        normalize()
    }

    /// Sorts ascending and merges overlapping/touching ranges.
    public mutating func normalize() {
        guard selections.count > 1 else { return }
        let sorted = selections.sorted { $0.start < $1.start }
        var merged: [VSSwiftRange] = [sorted[0]]
        for range in sorted.dropFirst() {
            if merged[merged.count - 1].intersectsOrTouches(range) {
                merged[merged.count - 1] = merged[merged.count - 1].union(range)
            } else {
                merged.append(range)
            }
        }
        selections = merged
    }
}

/// A single text replacement expressed in absolute character offsets.
private struct Replacement {
    var start: Int
    var end: Int
    var text: String
}

/// Performs coordinated edits across all cursors of a ``SelectionManager``.
public enum MultiCursorEditor {

    /// Applies replacements (sorted ascending by start) to the buffer, returning the
    /// new buffer and the resulting caret offsets. Edits are applied from the bottom
    /// up so earlier offsets remain valid; carets are computed via cumulative deltas.
    private static func apply(_ replacements: [Replacement], to buffer: TextBuffer) -> (TextBuffer, [Int]) {
        var buf = buffer
        // Apply descending so lower offsets are unaffected by higher edits.
        for r in replacements.sorted(by: { $0.start > $1.start }) {
            let range = VSSwiftRange(start: buf.position(at: r.start), end: buf.position(at: r.end))
            buf.delete(range)
            if !r.text.isEmpty {
                buf.insert(r.text, at: buf.position(at: r.start))
            }
        }
        // Compute caret offsets ascending with cumulative delta.
        var carets: [Int] = []
        var delta = 0
        for r in replacements.sorted(by: { $0.start < $1.start }) {
            let caret = r.start + r.text.count + delta
            carets.append(caret)
            delta += r.text.count - (r.end - r.start)
        }
        return (buf, carets)
    }

    /// Inserts `text` at every selection, replacing any non-empty selection content.
    public static func insert(_ text: String, buffer: TextBuffer, selection: SelectionManager) -> (TextBuffer, SelectionManager) {
        let replacements = selection.selections.map {
            Replacement(start: buffer.offset(of: $0.start), end: buffer.offset(of: $0.end), text: text)
        }
        let (newBuffer, carets) = apply(replacements, to: buffer)
        var newSelection = SelectionManager(carets.map { off in
            let p = newBuffer.position(at: off)
            return VSSwiftRange(start: p, end: p)
        })
        newSelection.normalize()
        return (newBuffer, newSelection)
    }

    /// Deletes backward (Backspace) at every cursor: removes the selection if non-empty,
    /// otherwise the single character before the caret.
    public static func deleteBackward(buffer: TextBuffer, selection: SelectionManager) -> (TextBuffer, SelectionManager) {
        var replacements: [Replacement] = []
        for sel in selection.selections {
            let startOff = buffer.offset(of: sel.start)
            let endOff = buffer.offset(of: sel.end)
            if startOff != endOff {
                replacements.append(Replacement(start: startOff, end: endOff, text: ""))
            } else if startOff > 0 {
                replacements.append(Replacement(start: startOff - 1, end: startOff, text: ""))
            } else {
                replacements.append(Replacement(start: 0, end: 0, text: ""))
            }
        }
        let (newBuffer, carets) = apply(replacements, to: buffer)
        var newSelection = SelectionManager(carets.map { off in
            let p = newBuffer.position(at: off)
            return VSSwiftRange(start: p, end: p)
        })
        newSelection.normalize()
        return (newBuffer, newSelection)
    }
}
