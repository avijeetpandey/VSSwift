import SwiftUI
import AppKit
import VSSwiftCore

/// Observable terminal session: feeds PTY output into a displayed buffer.
@MainActor
public final class TerminalViewModel: ObservableObject {
    @Published public private(set) var contents: String = ""
    private let pty = PseudoTerminal()
    private var task: Task<Void, Never>?
    private var started = false

    public init() {}

    public func startIfNeeded() {
        guard !started else { return }
        started = true
        _ = pty.start()
        task = Task { [weak self] in
            guard let self else { return }
            for await data in pty.output {
                let chunk = String(decoding: data, as: UTF8.self)
                await MainActor.run { self.append(chunk) }
            }
        }
    }

    private func append(_ chunk: String) {
        contents += TerminalViewModel.stripBasicANSI(chunk)
        // Cap retained scrollback to keep the view light.
        if contents.count > 200_000 {
            contents = String(contents.suffix(150_000))
        }
    }

    public func send(_ text: String) { pty.write(text) }
    public func sendLine(_ text: String) { pty.write(text + "\n") }
    public func resize(columns: UInt16, rows: UInt16) { pty.resize(columns: columns, rows: rows) }

    public func stop() {
        task?.cancel()
        pty.stop()
    }

    /// Removes the most common CSI escape sequences so the plain-text view stays readable.
    static func stripBasicANSI(_ s: String) -> String {
        guard s.contains("\u{1B}") else { return s }
        var result = ""
        var iterator = s.makeIterator()
        var pending: Character? = iterator.next()
        while let ch = pending {
            if ch == "\u{1B}" {
                // Skip until a letter terminator of the escape sequence.
                var next = iterator.next()
                if next == "[" { next = iterator.next() }
                while let c = next, !(c.isLetter) { next = iterator.next() }
                pending = iterator.next()
            } else if ch == "\r" {
                pending = iterator.next()
            } else {
                result.append(ch)
                pending = iterator.next()
            }
        }
        return result
    }
}

/// A simple integrated terminal panel: scrolling output plus an input field.
public struct TerminalView: View {
    @ObservedObject var model: TerminalViewModel
    var theme: Theme
    @State private var input: String = ""

    public init(model: TerminalViewModel, theme: Theme) {
        self.model = model
        self.theme = theme
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.contents.isEmpty ? "Starting shell…" : model.contents)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(model.contents.isEmpty ? Palette.textTertiary : Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("term-bottom")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .onChange(of: model.contents) { _, _ in
                    withAnimation(Motion.quick) { proxy.scrollTo("term-bottom", anchor: .bottom) }
                }
            }
            Divider().overlay(Palette.border)
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.accentPink)
                TextField("Type a command…", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                    .onSubmit {
                        model.sendLine(input)
                        input = ""
                    }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
        }
        .background(Palette.bg)
        .onAppear { model.startIfNeeded() }
    }
}
