import SwiftUI
import AppKit
import VSSwiftCore

/// Observable terminal session: feeds raw PTY output through an ANSI emulator and
/// publishes styled lines for rendering.
@MainActor
public final class TerminalViewModel: ObservableObject {
    /// The styled, parsed terminal buffer (newest line last).
    @Published public private(set) var lines: [TerminalLine] = []
    /// Monotonic counter bumped on every update so the view can drive auto-scroll.
    @Published public private(set) var revision: Int = 0

    private let emulator = TerminalEmulator(maxScrollbackLines: 5_000)
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
                await MainActor.run { self.ingest(chunk) }
            }
        }
    }

    private func ingest(_ chunk: String) {
        emulator.feed(chunk)
        lines = emulator.snapshot()
        revision &+= 1
    }

    /// Whether any output has been produced yet (beyond an empty initial line).
    public var isEmpty: Bool {
        lines.isEmpty || (lines.count == 1 && lines[0].spans.isEmpty)
    }

    public func send(_ text: String) { pty.write(text) }
    public func sendLine(_ text: String) { pty.write(text + "\n") }
    public func resize(columns: UInt16, rows: UInt16) { pty.resize(columns: columns, rows: rows) }

    /// Sends Ctrl-C to interrupt the foreground process.
    public func interrupt() { pty.write("\u{03}") }

    /// Clears the visible buffer (sends the shell `clear` for good measure).
    public func clear() {
        emulator.reset()
        lines = emulator.snapshot()
        revision &+= 1
        pty.write("clear\n")
    }

    public func stop() {
        task?.cancel()
        pty.stop()
    }
}

/// Renders a single emulator line as styled, selectable monospace text.
struct TerminalLineView: View {
    let line: TerminalLine

    var body: some View {
        if line.spans.isEmpty {
            Text(" ")
                .font(.system(size: 12.5, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            line.spans.reduce(Text("")) { partial, span in
                partial + styled(span)
            }
            .font(.system(size: 12.5, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func styled(_ span: TerminalSpan) -> Text {
        var text = Text(span.text)
            .foregroundColor(span.style.resolvedForeground(default: Palette.textPrimary))
        if span.style.bold { text = text.bold() }
        if span.style.italic { text = text.italic() }
        if span.style.underline { text = text.underline() }
        return text
    }
}

/// A polished integrated terminal panel: scrolling ANSI-colored output and a
/// prompt-styled input field with quick actions.
public struct TerminalView: View {
    @ObservedObject var model: TerminalViewModel
    var theme: Theme
    @State private var input: String = ""
    @FocusState private var inputFocused: Bool

    public init(model: TerminalViewModel, theme: Theme) {
        self.model = model
        self.theme = theme
    }

    public var body: some View {
        VStack(spacing: 0) {
            outputArea
            inputBar
        }
        .background(Palette.bg)
        .onAppear { model.startIfNeeded() }
    }

    private var outputArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if model.isEmpty {
                        Text("Starting shell…")
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(model.lines) { line in
                            TerminalLineView(line: line)
                                .id(line.id)
                        }
                    }
                    Color.clear.frame(height: 1).id("term-bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: model.revision) { _, _ in
                withAnimation(Motion.quick) { proxy.scrollTo("term-bottom", anchor: .bottom) }
            }
            .onTapGesture { inputFocused = true }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Palette.border)
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.accentPink)
                TextField("Type a command and press return…", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                    .focused($inputFocused)
                    .onSubmit(submit)
                Button(action: model.interrupt) {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.textTertiary)
                .help("Interrupt (Ctrl-C)")
                Button(action: model.clear) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.textTertiary)
                .help("Clear terminal")
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Palette.bgElevated)
        }
    }

    private func submit() {
        model.sendLine(input)
        input = ""
    }
}
