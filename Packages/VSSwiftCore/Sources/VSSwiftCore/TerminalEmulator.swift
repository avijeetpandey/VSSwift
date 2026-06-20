import Foundation

/// A terminal color reference produced by the ANSI parser. The concrete RGB value is
/// resolved by the UI layer so the emulator stays free of any UI framework.
public enum TerminalColor: Equatable, Sendable, Hashable {
    /// One of the 16 standard ANSI colors (0–7 normal, 8–15 bright).
    case ansi(Int)
    /// An xterm 256-color palette index.
    case palette(Int)
    /// A direct 24-bit truecolor value.
    case rgb(UInt8, UInt8, UInt8)
}

/// Text attributes for a run of terminal output, derived from SGR escape codes.
public struct TerminalStyle: Equatable, Sendable, Hashable {
    public var foreground: TerminalColor?
    public var background: TerminalColor?
    public var bold: Bool
    public var dim: Bool
    public var italic: Bool
    public var underline: Bool
    public var inverse: Bool

    public init(
        foreground: TerminalColor? = nil,
        background: TerminalColor? = nil,
        bold: Bool = false,
        dim: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        inverse: Bool = false
    ) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
        self.dim = dim
        self.italic = italic
        self.underline = underline
        self.inverse = inverse
    }

    public static let `default` = TerminalStyle()
}

/// A contiguous run of characters sharing a single style.
public struct TerminalSpan: Equatable, Sendable, Hashable {
    public var text: String
    public var style: TerminalStyle

    public init(text: String, style: TerminalStyle) {
        self.text = text
        self.style = style
    }
}

/// A single visual line of terminal output, composed of styled spans.
public struct TerminalLine: Equatable, Sendable, Identifiable {
    public let id: Int
    public var spans: [TerminalSpan]

    public init(id: Int, spans: [TerminalSpan]) {
        self.id = id
        self.spans = spans
    }

    /// The plain text of the line with styling removed.
    public var plainText: String { spans.map(\.text).joined() }
}

/// A pragmatic, scrollback-oriented ANSI terminal emulator. It interprets the common
/// control sequences emitted by interactive shells — SGR colors/attributes, carriage
/// returns, backspace, tabs, line erase, and screen clear — while safely discarding
/// cursor-positioning and OSC (window-title / working-directory) sequences that would
/// otherwise leak as garbage text. It is intentionally UI-framework agnostic and pure,
/// so it can be unit tested in isolation.
public final class TerminalEmulator {

    // MARK: - Cell model

    private struct Cell {
        var character: Character
        var style: TerminalStyle
    }

    private enum ParserState {
        case ground
        case escape
        case csi
        case osc
        case oscEscape
        case charset  // consume a single charset-designation byte
    }

    // MARK: - State

    private var finishedLines: [[Cell]] = []
    private var currentLine: [Cell] = []
    private var cursorColumn = 0
    private var style = TerminalStyle.default

    private var state: ParserState = .ground
    private var csiBuffer = ""

    private let maxLines: Int
    private let tabWidth = 8
    private var lineIDCounter = 0
    private var firstLineID = 0

    public init(maxScrollbackLines: Int = 5_000) {
        self.maxLines = max(200, maxScrollbackLines)
    }

    // MARK: - Public API

    /// Feeds a chunk of terminal output through the parser. Escape sequences may be
    /// split across chunks; parser state is preserved between calls.
    public func feed(_ text: String) {
        for scalar in text.unicodeScalars {
            process(scalar)
        }
    }

    /// Clears all output and resets the cursor and style (like the `clear` command).
    public func reset() {
        finishedLines.removeAll()
        currentLine.removeAll()
        cursorColumn = 0
        style = .default
        state = .ground
        csiBuffer.removeAll()
    }

    /// A snapshot of the current screen + scrollback as styled lines, newest last.
    public func snapshot() -> [TerminalLine] {
        var result: [TerminalLine] = []
        result.reserveCapacity(finishedLines.count + 1)
        var id = firstLineID
        for line in finishedLines {
            result.append(TerminalLine(id: id, spans: coalesce(line)))
            id += 1
        }
        result.append(TerminalLine(id: id, spans: coalesce(currentLine)))
        return result
    }

    // MARK: - Parser

    private func process(_ scalar: Unicode.Scalar) {
        switch state {
        case .ground: processGround(scalar)
        case .escape: processEscape(scalar)
        case .csi: processCSI(scalar)
        case .osc: processOSC(scalar)
        case .oscEscape: processOSCEscape(scalar)
        case .charset: state = .ground
        }
    }

    private func processGround(_ scalar: Unicode.Scalar) {
        switch scalar.value {
        case 0x1B:  // ESC
            state = .escape
        case 0x0A:  // \n
            newline()
        case 0x0D:  // \r
            cursorColumn = 0
        case 0x08:  // backspace
            cursorColumn = max(0, cursorColumn - 1)
        case 0x09:  // tab
            advanceToTabStop()
        case 0x07:  // bell
            break
        case 0x00..<0x20:  // other control chars — ignore
            break
        default:
            put(Character(scalar))
        }
    }

    private func processEscape(_ scalar: Unicode.Scalar) {
        switch scalar {
        case "[":
            csiBuffer.removeAll()
            state = .csi
        case "]":
            state = .osc
        case "(", ")", "*", "+":
            state = .charset
        default:
            // Other two-byte escapes (e.g. ESC =, ESC >, ESC M) — ignore.
            state = .ground
        }
    }

    private func processCSI(_ scalar: Unicode.Scalar) {
        // Final byte is in the range 0x40–0x7E; parameter/intermediate bytes precede it.
        if scalar.value >= 0x40 && scalar.value <= 0x7E {
            dispatchCSI(final: Character(scalar))
            state = .ground
        } else {
            csiBuffer.unicodeScalars.append(scalar)
        }
    }

    private func processOSC(_ scalar: Unicode.Scalar) {
        switch scalar.value {
        case 0x07:  // BEL terminates OSC
            state = .ground
        case 0x1B:  // possible ST (ESC \)
            state = .oscEscape
        default:
            break  // discard OSC payload
        }
    }

    private func processOSCEscape(_ scalar: Unicode.Scalar) {
        // We arrived here from ESC inside an OSC; either way return to ground.
        state = .ground
        if scalar != "\\" {
            // Not a true ST — re-interpret this scalar from the ground state.
            process(scalar)
        }
    }

    // MARK: - CSI dispatch

    private func dispatchCSI(final: Character) {
        switch final {
        case "m":
            applySGR(csiBuffer)
        case "K":
            eraseInLine(parameter: firstParameter(default: 0))
        case "J":
            eraseInDisplay(parameter: firstParameter(default: 0))
        case "G":
            cursorColumn = max(0, firstParameter(default: 1) - 1)
        case "C":
            cursorColumn += max(1, firstParameter(default: 1))
        case "D":
            cursorColumn = max(0, cursorColumn - max(1, firstParameter(default: 1)))
        default:
            break  // cursor up/down/home/etc. — ignored for scrollback
        }
    }

    private func firstParameter(default fallback: Int) -> Int {
        let params = csiBuffer.split(separator: ";", omittingEmptySubsequences: false)
        guard let first = params.first, let value = Int(first) else { return fallback }
        return value
    }

    private func eraseInLine(parameter: Int) {
        switch parameter {
        case 0:  // cursor to end of line
            if cursorColumn < currentLine.count {
                currentLine.removeSubrange(cursorColumn..<currentLine.count)
            }
        case 1:  // start of line to cursor
            let end = min(cursorColumn + 1, currentLine.count)
            for index in 0..<end { currentLine[index] = Cell(character: " ", style: style) }
        case 2:  // entire line
            currentLine.removeAll()
            cursorColumn = 0
        default:
            break
        }
    }

    private func eraseInDisplay(parameter: Int) {
        // Treat clear-screen variants as a scrollback reset, matching `clear`.
        if parameter == 2 || parameter == 3 {
            finishedLines.removeAll()
            currentLine.removeAll()
            cursorColumn = 0
        }
    }

    // MARK: - SGR (Select Graphic Rendition)

    private func applySGR(_ buffer: String) {
        let codes =
            buffer
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
        var index = 0
        if codes.isEmpty { style = .default; return }
        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0: style = .default
            case 1: style.bold = true
            case 2: style.dim = true
            case 3: style.italic = true
            case 4: style.underline = true
            case 7: style.inverse = true
            case 22: style.bold = false; style.dim = false
            case 23: style.italic = false
            case 24: style.underline = false
            case 27: style.inverse = false
            case 30...37: style.foreground = .ansi(code - 30)
            case 39: style.foreground = nil
            case 40...47: style.background = .ansi(code - 40)
            case 49: style.background = nil
            case 90...97: style.foreground = .ansi(code - 90 + 8)
            case 100...107: style.background = .ansi(code - 100 + 8)
            case 38:
                index += consumeExtendedColor(codes, from: index, isForeground: true)
            case 48:
                index += consumeExtendedColor(codes, from: index, isForeground: false)
            default:
                break
            }
            index += 1
        }
    }

    /// Parses a `38;5;n` (256-color) or `38;2;r;g;b` (truecolor) extension, returning the
    /// number of extra codes consumed beyond the leading `38`/`48`.
    private func consumeExtendedColor(_ codes: [Int], from start: Int, isForeground: Bool) -> Int {
        guard start + 1 < codes.count else { return 0 }
        let mode = codes[start + 1]
        if mode == 5, start + 2 < codes.count {
            let color = TerminalColor.palette(codes[start + 2])
            if isForeground { style.foreground = color } else { style.background = color }
            return 2
        }
        if mode == 2, start + 4 < codes.count {
            let color = TerminalColor.rgb(
                UInt8(clamping: codes[start + 2]),
                UInt8(clamping: codes[start + 3]),
                UInt8(clamping: codes[start + 4]))
            if isForeground { style.foreground = color } else { style.background = color }
            return 4
        }
        return 0
    }

    // MARK: - Writing

    private func put(_ character: Character) {
        let cell = Cell(character: character, style: style)
        if cursorColumn < currentLine.count {
            currentLine[cursorColumn] = cell
        } else {
            while currentLine.count < cursorColumn {
                currentLine.append(Cell(character: " ", style: .default))
            }
            currentLine.append(cell)
        }
        cursorColumn += 1
    }

    private func advanceToTabStop() {
        let next = ((cursorColumn / tabWidth) + 1) * tabWidth
        while cursorColumn < next { put(" ") }
    }

    private func newline() {
        finishedLines.append(currentLine)
        currentLine = []
        cursorColumn = 0
        trimScrollbackIfNeeded()
    }

    private func trimScrollbackIfNeeded() {
        let overflow = finishedLines.count - maxLines
        guard overflow > 0 else { return }
        finishedLines.removeFirst(overflow)
        firstLineID += overflow
    }

    // MARK: - Span coalescing

    private func coalesce(_ cells: [Cell]) -> [TerminalSpan] {
        guard !cells.isEmpty else { return [] }
        var spans: [TerminalSpan] = []
        var currentText = ""
        var currentStyle = cells[0].style
        for cell in cells {
            if cell.style == currentStyle {
                currentText.append(cell.character)
            } else {
                spans.append(TerminalSpan(text: currentText, style: currentStyle))
                currentText = String(cell.character)
                currentStyle = cell.style
            }
        }
        spans.append(TerminalSpan(text: currentText, style: currentStyle))
        return spans
    }
}
