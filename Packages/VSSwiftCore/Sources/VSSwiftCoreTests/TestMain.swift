import Foundation
import VSTestKit
@testable import VSSwiftCore

func colorSuite() -> TestSuite {
    let s = TestSuite("VSSwiftColor")
    s.test("parse 6-digit hex") { t in
        let c = VSSwiftColor(hex: "#1E1E1E")
        t.notNil(c)
        t.close(c!.red, 30.0 / 255.0)
        t.close(c!.alpha, 1.0)
    }
    s.test("parse 8-digit hex with alpha") { t in
        let c = VSSwiftColor(hex: "#FF000080")
        t.notNil(c)
        t.close(c!.red, 1.0)
        t.close(c!.alpha, 128.0 / 255.0)
    }
    s.test("parse shorthand hex") { t in
        let c = VSSwiftColor(hex: "#0F8")
        t.notNil(c)
        t.close(c!.green, 1.0)
        t.close(c!.blue, Double(0x88) / 255.0)
    }
    s.test("parse without # prefix") { t in
        t.notNil(VSSwiftColor(hex: "00FF00"))
    }
    s.test("invalid hex returns nil") { t in
        t.isNil(VSSwiftColor(hex: "#GGGGGG"))
        t.isNil(VSSwiftColor(hex: "#12345"))
    }
    s.test("round-trip hex string") { t in
        t.equal(VSSwiftColor(hex: "#1E1E1E")!.hexString, "#1E1E1E")
        t.equal(VSSwiftColor(hex: "#FF000080")!.hexString, "#FF000080")
    }
    return s
}

func sampleThemeData() -> Data {
    let url = Bundle.module.url(
        forResource: "sample-theme", withExtension: "json", subdirectory: "Resources")!
    return try! Data(contentsOf: url)
}

func themeSuite() -> TestSuite {
    let s = TestSuite("ThemeParser")
    s.test("parses name and type") { t in
        let theme = try ThemeParser().parse(data: sampleThemeData())
        t.equal(theme.name, "Sample Dark")
        t.equal(theme.type, .dark)
    }
    s.test("parses workbench colors") { t in
        let theme = try ThemeParser().parse(data: sampleThemeData())
        t.equal(theme.colors["editor.background"], VSSwiftColor(hex: "#1E1E1E"))
        t.equal(
            theme.color("statusBar.background", fallback: .init(red: 0, green: 0, blue: 0)).hexString,
            "#007ACC")
    }
    s.test("comma-separated scope string matches both") { t in
        let theme = try ThemeParser().parse(data: sampleThemeData())
        t.equal(theme.style(forScope: "string.quoted.double.swift").foreground, VSSwiftColor(hex: "#CE9178"))
        t.equal(theme.style(forScope: "constant.character.swift").foreground, VSSwiftColor(hex: "#CE9178"))
    }
    s.test("font style flags parsed") { t in
        let theme = try ThemeParser().parse(data: sampleThemeData())
        t.expect(theme.style(forScope: "comment.line.swift").fontStyle.contains(.italic))
        t.expect(theme.style(forScope: "keyword.control.flow.swift").fontStyle.contains(.bold))
    }
    s.test("longest-prefix scope wins") { t in
        let json = """
            {"name":"T","type":"dark","colors":{},"tokenColors":[
              {"scope":"keyword","settings":{"foreground":"#111111"}},
              {"scope":"keyword.control","settings":{"foreground":"#222222"}}]}
            """
        let theme = try ThemeParser().parse(jsonString: json)
        t.equal(theme.style(forScope: "keyword.control.swift").foreground, VSSwiftColor(hex: "#222222"))
        t.equal(theme.style(forScope: "keyword.operator.swift").foreground, VSSwiftColor(hex: "#111111"))
    }
    s.test("invalid JSON throws") { t in
        t.throwsError { _ = try ThemeParser().parse(data: Data("not json".utf8)) }
    }
    s.test("fontstyle parses multiple") { t in
        let style = FontStyle(parsing: "bold italic underline")
        t.expect(style.contains(.bold) && style.contains(.italic) && style.contains(.underline))
        t.expect(!style.contains(.strikethrough))
    }
    return s
}

func coordinateSuite() -> TestSuite {
    let s = TestSuite("TextCoordinates")
    s.test("position ordering") { t in
        t.expect(TextPosition(line: 0, column: 5) < TextPosition(line: 1, column: 0))
        t.expect(TextPosition(line: 2, column: 1) < TextPosition(line: 2, column: 3))
    }
    s.test("range normalizes reversed endpoints") { t in
        let r = VSSwiftRange(start: .init(line: 5, column: 0), end: .init(line: 1, column: 0))
        t.equal(r.start, TextPosition(line: 1, column: 0))
        t.equal(r.end, TextPosition(line: 5, column: 0))
    }
    s.test("range contains is half-open") { t in
        let r = VSSwiftRange(start: .init(line: 0, column: 0), end: .init(line: 0, column: 5))
        t.expect(r.contains(.init(line: 0, column: 0)))
        t.expect(r.contains(.init(line: 0, column: 4)))
        t.expect(!r.contains(.init(line: 0, column: 5)))
    }
    s.test("intersects or touches") { t in
        let a = VSSwiftRange(start: .init(line: 0, column: 0), end: .init(line: 0, column: 3))
        let b = VSSwiftRange(start: .init(line: 0, column: 3), end: .init(line: 0, column: 6))
        let c = VSSwiftRange(start: .init(line: 0, column: 7), end: .init(line: 0, column: 9))
        t.expect(a.intersectsOrTouches(b))
        t.expect(!a.intersectsOrTouches(c))
    }
    s.test("range union") { t in
        let a = VSSwiftRange(start: .init(line: 0, column: 0), end: .init(line: 0, column: 3))
        let b = VSSwiftRange(start: .init(line: 0, column: 2), end: .init(line: 0, column: 6))
        let u = a.union(b)
        t.equal(u.start, .init(line: 0, column: 0))
        t.equal(u.end, .init(line: 0, column: 6))
    }
    return s
}

func busAndConfigSuite() -> TestSuite {
    let s = TestSuite("EventBus & Config")
    s.test("publish reaches subscriber") { t in
        let bus = EventBus()
        let stream = await bus.subscribe()
        let received = Task { () -> AppEvent? in
            for await event in stream { return event }
            return nil
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        let url = URL(fileURLWithPath: "/tmp/a.swift")
        await bus.publish(.fileOpened(url))
        let event = await received.value
        t.equal(event, .fileOpened(url))
    }
    s.test("multiple subscribers all receive") { t in
        let bus = EventBus()
        let s1 = await bus.subscribe()
        let s2 = await bus.subscribe()
        let t1 = Task { () -> AppEvent? in
            for await e in s1 { return e }; return nil
        }
        let t2 = Task { () -> AppEvent? in
            for await e in s2 { return e }; return nil
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        await bus.publish(.themeChanged("Dark+"))
        t.equal(await t1.value, .themeChanged("Dark+"))
        t.equal(await t2.value, .themeChanged("Dark+"))
    }
    s.test("configuration round-trip") { t in
        var config = EditorConfiguration.default
        config.fontSize = 16
        config.insertSpaces = false
        let store = ConfigurationStore()
        let decoded = try store.decode(from: store.encode(config))
        t.equal(decoded, config)
    }
    s.test("indent unit spaces/tab") { t in
        t.equal(EditorConfiguration(tabSize: 2, insertSpaces: true).indentUnit, "  ")
        t.equal(EditorConfiguration(insertSpaces: false).indentUnit, "\t")
    }
    s.test("app state activity toggles sidebar") { t in
        await MainActor.run {
            let state = AppState()
            state.activeActivityItem = .explorer
            state.isSidebarVisible = true
            state.selectActivity(.explorer)
            t.expect(!state.isSidebarVisible)
            state.selectActivity(.search)
            t.expect(state.isSidebarVisible)
            t.equal(state.activeActivityItem, .search)
        }
    }
    s.test("app state open/close documents") { t in
        await MainActor.run {
            let state = AppState()
            let a = EditorDocument(url: URL(fileURLWithPath: "/tmp/a.swift"))
            let b = EditorDocument(url: URL(fileURLWithPath: "/tmp/b.swift"))
            state.openDocument(a)
            state.openDocument(b)
            state.openDocument(a)
            t.equal(state.openDocuments.count, 2)
            t.equal(state.activeDocumentID, a.id)
            state.closeDocument(a.id)
            t.equal(state.activeDocumentID, b.id)
        }
    }
    return s
}

func terminalEmulatorSuite() -> TestSuite {
    let s = TestSuite("TerminalEmulator")

    s.test("plain text becomes a single span") { t in
        let emu = TerminalEmulator()
        emu.feed("hello world")
        let lines = emu.snapshot()
        t.equal(lines.count, 1)
        t.equal(lines[0].plainText, "hello world")
        t.equal(lines[0].spans.count, 1)
    }

    s.test("newlines split lines") { t in
        let emu = TerminalEmulator()
        emu.feed("one\ntwo\nthree")
        let lines = emu.snapshot()
        t.equal(lines.count, 3)
        t.equal(lines[0].plainText, "one")
        t.equal(lines[1].plainText, "two")
        t.equal(lines[2].plainText, "three")
    }

    s.test("OSC working-directory sequence is stripped (the file:// bug)") { t in
        let emu = TerminalEmulator()
        // zsh emits ESC ] 7 ; file://host/path BEL before the prompt.
        emu.feed("\u{1B}]7;file://Avijeets-MacBook-Air.local/Users/me\u{07}avijeet$ ")
        let lines = emu.snapshot()
        t.equal(lines.count, 1)
        t.equal(lines[0].plainText, "avijeet$ ")
    }

    s.test("OSC terminated by ST (ESC backslash) is stripped") { t in
        let emu = TerminalEmulator()
        emu.feed("\u{1B}]0;window title\u{1B}\\ready")
        t.equal(emu.snapshot()[0].plainText, "ready")
    }

    s.test("SGR sets foreground color and resets") { t in
        let emu = TerminalEmulator()
        emu.feed("\u{1B}[31mred\u{1B}[0m plain")
        let spans = emu.snapshot()[0].spans
        t.equal(spans.count, 2)
        t.equal(spans[0].text, "red")
        t.equal(spans[0].style.foreground, TerminalColor.ansi(1))
        t.equal(spans[1].text, " plain")
        t.isNil(spans[1].style.foreground)
    }

    s.test("bright foreground and bold attribute") { t in
        let emu = TerminalEmulator()
        emu.feed("\u{1B}[1;92mok")
        let style = emu.snapshot()[0].spans[0].style
        t.expect(style.bold)
        t.equal(style.foreground, TerminalColor.ansi(10))
    }

    s.test("256-color and truecolor extended SGR") { t in
        let emu = TerminalEmulator()
        emu.feed("\u{1B}[38;5;200ma\u{1B}[38;2;10;20;30mb")
        let spans = emu.snapshot()[0].spans
        t.equal(spans[0].style.foreground, TerminalColor.palette(200))
        t.equal(spans[1].style.foreground, TerminalColor.rgb(10, 20, 30))
    }

    s.test("carriage return overwrites from column zero") { t in
        let emu = TerminalEmulator()
        emu.feed("progress 50%\rprogress 100%")
        t.equal(emu.snapshot()[0].plainText, "progress 100%")
    }

    s.test("backspace moves cursor back") { t in
        let emu = TerminalEmulator()
        emu.feed("abcd\u{08}\u{08}XY")
        t.equal(emu.snapshot()[0].plainText, "abXY")
    }

    s.test("erase-in-line to end clears trailing text") { t in
        let emu = TerminalEmulator()
        emu.feed("hello world\r\u{1B}[5C\u{1B}[K")
        t.equal(emu.snapshot()[0].plainText, "hello")
    }

    s.test("clear screen resets scrollback") { t in
        let emu = TerminalEmulator()
        emu.feed("old\nlines\n")
        emu.feed("\u{1B}[2Jfresh")
        let lines = emu.snapshot()
        t.equal(lines.count, 1)
        t.equal(lines[0].plainText, "fresh")
    }

    s.test("escape sequence split across feeds is parsed") { t in
        let emu = TerminalEmulator()
        emu.feed("\u{1B}[3")
        emu.feed("1mred")
        let style = emu.snapshot()[0].spans[0].style
        t.equal(style.foreground, TerminalColor.ansi(1))
    }

    s.test("tab advances to next tab stop") { t in
        let emu = TerminalEmulator()
        emu.feed("a\tb")
        t.equal(emu.snapshot()[0].plainText.count, 9)
    }

    s.test("scrollback is capped") { t in
        let emu = TerminalEmulator(maxScrollbackLines: 200)
        for index in 0..<1000 { emu.feed("line \(index)\n") }
        let lines = emu.snapshot()
        t.expect(lines.count <= 201)
        t.equal(lines.first!.id != 0, true)
    }

    s.test("reset clears everything") { t in
        let emu = TerminalEmulator()
        emu.feed("\u{1B}[31msome text\n")
        emu.reset()
        let lines = emu.snapshot()
        t.equal(lines.count, 1)
        t.equal(lines[0].plainText, "")
    }

    return s
}

@main
struct Runner {
    static func main() async {
        await runSuitesAndExit([
            colorSuite(),
            themeSuite(),
            coordinateSuite(),
            busAndConfigSuite(),
            terminalEmulatorSuite(),
        ])
    }
}
