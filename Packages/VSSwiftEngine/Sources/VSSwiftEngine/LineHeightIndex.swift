import Foundation

/// A Fenwick (binary indexed) tree giving O(log n) prefix sums and point updates.
/// Used to map between line indices and pixel offsets when line heights vary
/// (wrapped lines, folded regions, inline widgets).
public struct FenwickTree: Sendable {
    private var tree: [Double]
    public private(set) var count: Int

    public init(count: Int, initialValue: Double = 0) {
        self.count = count
        self.tree = Array(repeating: 0, count: count + 1)
        if initialValue != 0 {
            for i in 0..<count { add(i, initialValue) }
        }
    }

    /// Adds `delta` to the value at `index`.
    public mutating func add(_ index: Int, _ delta: Double) {
        var i = index + 1
        while i <= count {
            tree[i] += delta
            i += i & (-i)
        }
    }

    /// Sum of values in `[0, index]` (inclusive). Returns 0 for index < 0.
    public func prefixSum(through index: Int) -> Double {
        var i = index + 1
        var sum = 0.0
        while i > 0 {
            sum += tree[i]
            i -= i & (-i)
        }
        return sum
    }

    /// Sum of values in `[0, index)` (exclusive upper bound).
    public func prefixSum(upTo index: Int) -> Double {
        prefixSum(through: index - 1)
    }

    /// Finds the smallest index whose inclusive prefix sum exceeds `target`.
    /// Equivalent to "which line contains pixel y". Runs in O(log n).
    public func indexForPrefixSum(_ target: Double) -> Int {
        var pos = 0
        var remaining = target
        var logn = 1
        while (logn << 1) <= count { logn <<= 1 }
        var step = logn
        while step > 0 {
            let next = pos + step
            if next <= count && tree[next] <= remaining {
                remaining -= tree[next]
                pos = next
            }
            step >>= 1
        }
        return min(pos, count - 1)
    }
}

/// Maps line indices to vertical pixel positions, supporting variable row heights.
public struct LineHeightIndex: Sendable {
    private var fenwick: FenwickTree
    public let defaultHeight: Double
    public private(set) var lineCount: Int

    public init(lineCount: Int, defaultHeight: Double) {
        self.lineCount = lineCount
        self.defaultHeight = defaultHeight
        self.fenwick = FenwickTree(count: max(lineCount, 1), initialValue: defaultHeight)
    }

    /// The y-offset of the top of `line`.
    public func yOffset(ofLine line: Int) -> Double {
        guard line > 0 else { return 0 }
        return fenwick.prefixSum(upTo: line)
    }

    /// The total content height.
    public var totalHeight: Double { fenwick.prefixSum(through: lineCount - 1) }

    /// The line whose row contains vertical position `y`.
    public func line(atY y: Double) -> Int {
        fenwick.indexForPrefixSum(y)
    }

    /// Updates a single line's height (e.g., after wrapping or folding changes it).
    public mutating func setHeight(_ height: Double, forLine line: Int) {
        let current = fenwick.prefixSum(through: line) - fenwick.prefixSum(through: line - 1)
        fenwick.add(line, height - current)
    }

    /// Computes the inclusive range of lines visible within the viewport `[top, bottom)`.
    public func visibleLineRange(top: Double, bottom: Double) -> ClosedRange<Int> {
        let first = line(atY: max(0, top))
        let last = line(atY: max(0, bottom))
        return first...max(first, last)
    }
}
