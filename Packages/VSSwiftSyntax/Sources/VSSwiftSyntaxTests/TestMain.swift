import Foundation
import VSSwiftCore
import VSSwiftSyntax
import VSTestKit

func tokenParserSuite() -> TestSuite {
    let s = TestSuite("SwiftTokenParser")

    func scopes(_ tokens: [VSSwiftToken], at line: Int) -> [String] {
        tokens.filter { $0.range.start.line == line }.map { $0.scope }
    }

    s.test("keywords classified") { t in
        let parser = SwiftTokenParser()
        let batch = await parser.parse("let x = 1", version: 7)
        t.equal(batch.documentVersion, 7)
        t.expect(batch.tokens.contains { $0.scope == "keyword" }, "let is a keyword")
        t.expect(batch.tokens.contains { $0.scope == "constant.numeric" }, "1 is numeric")
    }

    s.test("control keyword scope") { t in
        let parser = SwiftTokenParser()
        let batch = await parser.parse("func f() { return 1 }", version: 1)
        t.expect(batch.tokens.contains { $0.scope == "keyword.control" }, "return is control")
        t.expect(batch.tokens.contains { $0.scope == "entity.name.function" }, "f is a function name")
    }

    s.test("type declaration name") { t in
        let parser = SwiftTokenParser()
        let batch = await parser.parse("struct Point { var x: Int }", version: 1)
        let typeTokens = batch.tokens.filter { $0.scope == "entity.name.type" }
        t.expect(typeTokens.count >= 1, "Point and/or Int are types")
    }

    s.test("string literal scope") { t in
        let parser = SwiftTokenParser()
        let batch = await parser.parse("let s = \"hello\"", version: 1)
        t.expect(batch.tokens.contains { $0.scope == "string" }, "string literal colored")
    }

    s.test("comment scope") { t in
        let parser = SwiftTokenParser()
        let batch = await parser.parse("// a comment\nlet y = 2", version: 1)
        let commentTokens = batch.tokens.filter { $0.scope == "comment" }
        t.expect(commentTokens.count == 1)
        t.equal(commentTokens.first?.range.start.line, 0)
    }

    s.test("function call mapped to function scope") { t in
        let parser = SwiftTokenParser()
        let batch = await parser.parse("print(value)", version: 1)
        t.expect(batch.tokens.contains { $0.scope == "entity.name.function" }, "print is a call")
    }

    s.test("positions are line/column accurate for multi-line") { t in
        let parser = SwiftTokenParser()
        let source = "let a = 1\nlet b = 2"
        let batch = await parser.parse(source, version: 1)
        // The numeric literal on line 1 should be at column 8.
        let numericLine1 = batch.tokens.first { $0.scope == "constant.numeric" && $0.range.start.line == 1 }
        t.notNil(numericLine1)
        t.equal(numericLine1?.range.start, TextPosition(line: 1, column: 8))
    }

    s.test("unicode columns counted as characters") { t in
        let parser = SwiftTokenParser()
        // 'é' is 2 UTF-8 bytes but 1 character; the keyword after it must land at the right column.
        let source = "let café = 1"
        let batch = await parser.parse(source, version: 1)
        let numeric = batch.tokens.first { $0.scope == "constant.numeric" }
        t.notNil(numeric)
        // "let café = " -> 'c' at col 4..7 (café), space, =, space => 1 at column 11 (character count)
        t.equal(numeric?.range.start.column, 11)
    }

    s.test("stale-version handling is caller's responsibility (version preserved)") { t in
        let parser = SwiftTokenParser()
        let batch = await parser.parse("let z = 0", version: 99)
        t.equal(batch.documentVersion, 99)
    }

    return s
}

func performanceSuite() -> TestSuite {
    let s = TestSuite("Parser performance")
    s.test("parse a large Swift source") { t in
        let unit = """
        struct Item {
            let id: Int
            func describe() -> String { return "Item \\(id)" }
        }

        """
        let big = String(repeating: unit, count: 2000) // ~10k lines
        let parser = SwiftTokenParser()
        let clock = ContinuousClock()
        var count = 0
        let elapsed = await clock.measure {
            let batch = await parser.parse(big, version: 1)
            count = batch.tokens.count
        }
        print("      parsed ~\(big.split(separator: "\\n").count) lines, \(count) tokens in \(elapsed)")
        t.expect(count > 0)
        t.expect(elapsed < .seconds(15))
    }
    return s
}

@main
struct Runner {
    static func main() async {
        await runSuitesAndExit([
            tokenParserSuite(),
            performanceSuite()
        ])
    }
}
