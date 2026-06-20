import SwiftUI
import VSSwiftCore

/// The tabbed editor area: tab strip + breadcrumb + active editor canvas + minimap + completion overlay.
public struct EditorAreaView: View {
    @ObservedObject var appState: AppState
    var theme: Theme
    @ObservedObject var editor: EditorViewModel
    @ObservedObject var completion: CompletionController

    public init(appState: AppState, theme: Theme, editor: EditorViewModel, completion: CompletionController) {
        self.appState = appState
        self.theme = theme
        self.editor = editor
        self.completion = completion
    }

    @State private var minimapScroll: Double = 0

    public var body: some View {
        VStack(spacing: 0) {
            tabStrip
            breadcrumb
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    EditorCanvasView(model: editor, theme: theme, configuration: appState.configuration)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if appState.configuration.showMinimap {
                        MinimapView(
                            lines: editor.text.components(separatedBy: "\n"),
                            tokens: editor.tokens, theme: theme,
                            lineHeight: appState.configuration.fontSize
                                * appState.configuration.lineHeightMultiple,
                            viewportHeight: 600, scrollOffset: $minimapScroll)
                    }
                }
                if editor.isCompletionVisible {
                    CompletionWidget(
                        items: editor.completionItems,
                        selectedIndex: $completion.selectedIndex,
                        theme: theme
                    ) { item in
                        editor.dismissCompletions()
                        _ = item
                    }
                    .padding(.leading, 80)
                    .padding(.top, 40)
                    .transition(.scale(scale: 0.96, anchor: .topLeading).combined(with: .opacity))
                }
            }
            .animation(Motion.quick, value: editor.isCompletionVisible)
        }
        .background(Palette.bg)
    }

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(appState.openDocuments) { doc in
                        TabView(
                            doc: doc,
                            isActive: doc.id == appState.activeDocumentID,
                            onSelect: { withAnimation(Motion.quick) { appState.activeDocumentID = doc.id } },
                            onClose: { withAnimation(Motion.snappy) { appState.closeDocument(doc.id) } })
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                tabAction("plus")
                tabAction("ellipsis")
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 38)
        .background(Palette.bgElevated)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1) }
    }

    private func tabAction(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.textTertiary)
            .frame(width: 26, height: 26)
            .hoverHighlight(cornerRadius: 6)
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            if let doc = appState.activeDocument {
                let icon = FileIconResolver.icon(for: doc.displayName)
                Image(systemName: icon.symbol).font(.system(size: 10)).foregroundStyle(icon.color)
                Text(doc.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
            } else {
                Text("No file open").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(Palette.bg)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1) }
    }
}

/// A single modern editor tab with active accent bar, dirty indicator, and hover close.
private struct TabView: View {
    let doc: EditorDocument
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovering = false
    @State private var closeHover = false

    var body: some View {
        let icon = FileIconResolver.icon(for: doc.displayName)
        HStack(spacing: 7) {
            Image(systemName: icon.symbol).font(.system(size: 11)).foregroundStyle(icon.color)
            Text(doc.displayName)
                .font(.system(size: 12.5))
                .foregroundStyle(isActive ? Palette.textPrimary : Palette.textSecondary)
                .lineLimit(1)
            ZStack {
                if doc.isDirty && !closeHover {
                    Circle().fill(Palette.textSecondary).frame(width: 7, height: 7)
                } else {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(closeHover ? Palette.textPrimary : Palette.textTertiary)
                            .frame(width: 16, height: 16)
                            .background(
                                Circle().fill(closeHover ? Color.white.opacity(0.1) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .opacity(hovering || isActive ? 1 : 0)
                    .onHover { closeHover = $0 }
                }
            }
            .frame(width: 16, height: 16)
        }
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(isActive ? Palette.bg : (hovering ? Color.white.opacity(0.03) : Palette.bgElevated))
        .overlay(alignment: .top) {
            if isActive {
                Rectangle()
                    .fill(Palette.accent)
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .trailing) {
            if !isActive {
                Rectangle().fill(Palette.border).frame(width: 1).padding(.vertical, 8)
            }
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
        .onTapGesture(perform: onSelect)
    }
}

/// The bottom panel with tabs (Problems / Output / Debug Console / Terminal).
public struct PanelView: View {
    @ObservedObject var appState: AppState
    var theme: Theme
    @ObservedObject var terminal: TerminalViewModel
    var problems: [String]

    public init(appState: AppState, theme: Theme, terminal: TerminalViewModel, problems: [String]) {
        self.appState = appState
        self.theme = theme
        self.terminal = terminal
        self.problems = problems
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(PanelTab.allCases) { tab in
                    panelTabButton(tab)
                }
                Spacer()
                Button {
                    withAnimation(Motion.snappy) { appState.isPanelVisible = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 26, height: 26)
                        .hoverHighlight(cornerRadius: 6)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Palette.bgElevated)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1) }

            Group {
                switch appState.activePanelTab {
                case .terminal:
                    TerminalView(model: terminal, theme: theme)
                case .problems:
                    if problems.isEmpty {
                        emptyState(
                            icon: "checkmark.seal",
                            tint: Palette.success,
                            title: "No problems detected",
                            message: "Errors and warnings in your workspace will appear here.")
                    } else {
                        problemsList(problems)
                    }
                case .output:
                    emptyState(
                        icon: "text.alignleft",
                        tint: Palette.info,
                        title: "No output yet",
                        message: "Build and task output will be shown in this panel.")
                case .debugConsole:
                    emptyState(
                        icon: "ladybug",
                        tint: Palette.accentOrange,
                        title: "Debug console is idle",
                        message: "Start a debug session to evaluate expressions and read logs.")
                }
            }
        }
        .frame(height: 240)
        .background(Palette.bg)
    }

    private func panelTabButton(_ tab: PanelTab) -> some View {
        let isActive = appState.activePanelTab == tab
        return Button {
            withAnimation(Motion.quick) { appState.activePanelTab = tab }
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                    Text(tab.title.uppercased())
                        .font(.system(size: 11, weight: isActive ? .bold : .medium))
                        .tracking(0.4)
                    if tab == .problems, !problems.isEmpty {
                        Text("\(problems.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.bg)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Palette.danger))
                    }
                }
                .foregroundStyle(isActive ? Palette.textPrimary : Palette.textTertiary)
                Rectangle()
                    .fill(isActive ? AnyShapeStyle(Palette.accentBarGradient) : AnyShapeStyle(Color.clear))
                    .frame(height: 2)
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
        }
        .buttonStyle(.plain)
    }

    private func problemsList(_ items: [String]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.warning)
                            .padding(.top, 1)
                        Text(item)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Palette.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hoverHighlight(cornerRadius: 6)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
        }
    }

    private func emptyState(icon: String, tint: Color, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(tint.opacity(0.9))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
    }
}
