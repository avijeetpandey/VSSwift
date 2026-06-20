import Foundation
import VSSwiftCore
import VSSwiftEngine
import VSTestKit

func bufferSuite() -> TestSuite {
    let s = TestSuite("TextBuffer")
    s.test("init splits lines") { t in
        let b = TextBuffer("a\nb\nc")
        t.equal(b.lineCount, 3)
        t.equal(b.line(at: 1), "b")
    }
    s.test("single-line insert") { t in
        var b = TextBuffer("hello world")
        let end = b.insert("brave ", at: .init(line: 0, column: 6))
        t.equal(b.text, "hello brave world")
        t.equal(end, TextPosition(line: 0, column: 12))
    }
    s.test("multi-line insert") { t in
        var b = TextBuffer("ac")
        let end = b.insert("X\nY", at: .init(line: 0, column: 1))
        t.equal(b.text, "aX\nYc")
        t.equal(end, TextPosition(line: 1, column: 1))
    }
    s.test("single-line delete") { t in
        var b = TextBuffer("hello world")
        let removed = b.delete(VSSwiftRange(start: .init(line: 0, column: 5), end: .init(line: 0, column: 11)))
        t.equal(removed, " world")
        t.equal(b.text, "hello")
    }
    s.test("multi-line delete joins lines") { t in
        var b = TextBuffer("abc\ndef\nghi")
        let removed = b.delete(VSSwiftRange(start: .init(line: 0, column: 1), end: .init(line: 2, column: 1)))
        t.equal(removed, "bc\ndef\ng")
        t.equal(b.text, "ahi")
    }
    s.test("offset/position round-trip") { t in
        let b = TextBuffer("abc\ndef\nghi")
        for line in 0..<3 {
            for col in 0...3 {
                let p = TextPosition(line: line, column: col)
                let off = b.offset(of: p)
                t.equal(b.position(at: off), p, "rt at \(line),\(col)")
            }
        }
    }
    return s
}

func concurrencySuite() -> TestSuite {
    let s = TestSuite("TextDocument concurrency")
    s.test("concurrent inserts are serialized and consistent") { t in
        let doc = TextDocument("")
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    await doc.insert("x", at: .init(line: 0, column: 0))
                }
            }
        }
        let text = await doc.text
        let version = await doc.version
        t.equal(text.count, 100, "all 100 inserts applied")
        t.expect(text.allSatisfy { $0 == "x" })
        t.equal(version, 100, "version incremented per edit")
    }
    s.test("snapshot is a stable value") { t in
        let doc = TextDocument("hello")
        let snap = await doc.snapshot()
        await doc.insert("!!!", at: .init(line: 0, column: 5))
        t.equal(snap.text, "hello", "snapshot unaffected by later edits")
        t.equal(await doc.text, "hello!!!")
    }
    return s
}

func fenwickSuite() -> TestSuite {
    let s = TestSuite("Fenwick & LineHeightIndex")
    s.test("uniform heights prefix sums") { t in
        let idx = LineHeightIndex(lineCount: 10, defaultHeight: 20)
        t.close(idx.yOffset(ofLine: 0), 0)
        t.close(idx.yOffset(ofLine: 5), 100)
        t.close(idx.totalHeight, 200)
    }
    s.test("line at y") { t in
        let idx = LineHeightIndex(lineCount: 10, defaultHeight: 20)
        t.equal(idx.line(atY: 0), 0)
        t.equal(idx.line(atY: 25), 1)
        t.equal(idx.line(atY: 199), 9)
    }
    s.test("variable height after fold") { t in
        var idx = LineHeightIndex(lineCount: 5, defaultHeight: 20)
        idx.setHeight(0, forLine: 2)
        t.close(idx.totalHeight, 80)
        t.close(idx.yOffset(ofLine: 3), 40)
    }
    s.test("visible line range windowing") { t in
        let idx = LineHeightIndex(lineCount: 1000, defaultHeight: 20)
        let range = idx.visibleLineRange(top: 1000, bottom: 1200)
        t.equal(range.lowerBound, 50)
        t.equal(range.upperBound, 60)
    }
    return s
}

func foldingSuite() -> TestSuite {
    let s = TestSuite("Folding")
    s.test("indentation ranges") { t in
        let b = TextBuffer("func a() {\n    let x = 1\n    let y = 2\n}\ntrailing")
        let ranges = FoldingProvider().indentationRanges(for: b)
        t.expect(ranges.contains { $0.startLine == 0 && $0.endLine == 2 }, "fold body of func")
    }
    s.test("bracket ranges") { t in
        let b = TextBuffer("struct S {\n  var x: Int\n}")
        let ranges = FoldingProvider().bracketRanges(for: b)
        t.expect(ranges.contains { $0.startLine == 0 && $0.endLine == 2 })
    }
    s.test("brackets ignore strings and comments") { t in
        let b = TextBuffer("let s = \"{\" // }\nlet y = 1")
        let ranges = FoldingProvider().bracketRanges(for: b)
        t.equal(ranges.count, 0, "no real multi-line bracket region")
    }
    s.test("folding state hides inner lines") { t in
        var state = FoldingState(ranges: [FoldingRange(startLine: 0, endLine: 3)])
        state.collapse(startLine: 0)
        let hidden = state.hiddenLines()
        t.expect(hidden.contains(1) && hidden.contains(2) && hidden.contains(3))
        t.expect(!hidden.contains(0), "fold header stays visible")
    }
    return s
}

func selectionSuite() -> TestSuite {
    let s = TestSuite("Multi-cursor SelectionManager")
    s.test("overlapping selections merge") { t in
        var mgr = SelectionManager([
            VSSwiftRange(start: .init(line: 0, column: 0), end: .init(line: 0, column: 5)),
            VSSwiftRange(start: .init(line: 0, column: 3), end: .init(line: 0, column: 8))
        ])
        mgr.normalize()
        t.equal(mgr.count, 1)
        t.equal(mgr.primary.end, TextPosition(line: 0, column: 8))
    }
    s.test("multi-cursor insert at all carets") { t in
        let buffer = TextBuffer("aa\nbb")
        let sel = SelectionManager([
            VSSwiftRange(line: 0, column: 0),
            VSSwiftRange(line: 1, column: 0)
        ])
        let (newBuffer, newSel) = MultiCursorEditor.insert(">", buffer: buffer, selection: sel)
        t.equal(newBuffer.text, ">aa\n>bb")
        t.equal(newSel.count, 2)
        t.equal(newSel.selections[0].start, TextPosition(line: 0, column: 1))
        t.equal(newSel.selections[1].start, TextPosition(line: 1, column: 1))
    }
    s.test("multi-cursor insert replaces selections") { t in
        let buffer = TextBuffer("foo bar")
        let sel = SelectionManager([
            VSSwiftRange(start: .init(line: 0, column: 0), end: .init(line: 0, column: 3)),
            VSSwiftRange(start: .init(line: 0, column: 4), end: .init(line: 0, column: 7))
        ])
        let (newBuffer, _) = MultiCursorEditor.insert("X", buffer: buffer, selection: sel)
        t.equal(newBuffer.text, "X X")
    }
    s.test("multi-cursor backspace") { t in
        let buffer = TextBuffer("ab\ncd")
        let sel = SelectionManager([
            VSSwiftRange(line: 0, column: 2),
            VSSwiftRange(line: 1, column: 2)
        ])
        let (newBuffer, newSel) = MultiCursorEditor.deleteBackward(buffer: buffer, selection: sel)
        t.equal(newBuffer.text, "a\nc")
        t.equal(newSel.selections[0].start, TextPosition(line: 0, column: 1))
    }
    return s
}

func minimapSuite() -> TestSuite {
    let s = TestSuite("Minimap")
    s.test("slider height respects minimum") { t in
        let m = MinimapMetrics(lineCount: 1000, lineHeight: 20, minimapScale: 0.1,
                               viewportHeight: 400, minimapHeight: 5000)
        t.expect(m.sliderHeight >= 8)
    }
    s.test("scroll offset round-trips through minimap") { t in
        let m = MinimapMetrics(lineCount: 1000, lineHeight: 20, minimapScale: 0.1,
                               viewportHeight: 400, minimapHeight: 2000)
        let offset = 5000.0
        let y = m.sliderY(forScrollOffset: offset)
        let back = m.scrollOffset(forMinimapY: y + m.sliderHeight / 2)
        t.close(back, offset, accuracy: 1.0)
    }
    return s
}

func performanceSuite() -> TestSuite {
    let s = TestSuite("Performance (100k lines)")
    s.test("build + 10k random queries on 100k-line index") { t in
        let n = 100_000
        let clock = ContinuousClock()
        var idx = LineHeightIndex(lineCount: n, defaultHeight: 18)
        let buildTime = clock.measure {
            var i = 0
            while i < n { idx.setHeight(0, forLine: i); i += 50 }
        }
        var sink = 0
        let total = idx.totalHeight
        let queryTime = clock.measure {
            var seed: UInt64 = 88172645463325252
            for _ in 0..<10_000 {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                let bound = UInt64(total > 0 ? total : 1)
                let y = Double(seed % bound)
                sink &+= idx.line(atY: y)
            }
        }
        t.expect(sink >= 0)
        print("      build(100k)=\(buildTime), 10k queries=\(queryTime)")
        t.expect(queryTime < .seconds(2), "10k queries should be fast")
    }
    s.test("buffer init on large document") { t in
        let line = "let value = computeSomething(withArgument: 42) // a line of code"
        let big = Array(repeating: line, count: 100_000).joined(separator: "\n")
        let clock = ContinuousClock()
        var buffer = TextBuffer("")
        let initTime = clock.measure { buffer = TextBuffer(big) }
        t.equal(buffer.lineCount, 100_000)
        print("      TextBuffer(100k) init=\(initTime)")
        t.expect(initTime < .seconds(5))
    }
    return s
}

@main
struct Runner {
    static func main() async {
        await runSuitesAndExit([
            bufferSuite(),
            concurrencySuite(),
            fenwickSuite(),
            foldingSuite(),
            selectionSuite(),
            minimapSuite(),
            performanceSuite()
        ])
    }
}
