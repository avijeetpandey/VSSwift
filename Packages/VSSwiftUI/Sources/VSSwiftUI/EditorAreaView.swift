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
                        MinimapView(lines: editor.text.components(separatedBy: "\n"),
                                    tokens: editor.tokens, theme: theme,
                                    lineHeight: appState.configuration.fontSize * appState.configuration.lineHeightMultiple,
                                    viewportHeight: 600, scrollOffset: $minimapScroll)
                    }
                }
                if editor.isCompletionVisible {
                    CompletionWidget(items: editor.completionItems,
                                     selectedIndex: $completion.selectedIndex,
                                     theme: theme) { item in
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
                        TabView(doc: doc,
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
                Button { withAnimation(Motion.snappy) { appState.isPanelVisible = false } } label: {
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
                    listView(problems.isEmpty ? ["No problems have been detected in the workspace."] : problems)
                case .output, .debugConsole:
                    listView(["(\(appState.activePanelTab.title) output)"])
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
                Text(tab.title.uppercased())
                    .font(.system(size: 11, weight: isActive ? .bold : .medium))
                    .tracking(0.4)
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

    private func listView(_ items: [String]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
    }
}
