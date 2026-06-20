import SwiftUI
import VSSwiftCore

/// The far-left activity bar with primary view switchers. Modernized with an animated
/// accent indicator pill, hover feedback, and a gradient logo mark at the top.
public struct ActivityBarView: View {
    @ObservedObject var appState: AppState
    var theme: Theme

    public init(appState: AppState, theme: Theme) {
        self.appState = appState
        self.theme = theme
    }

    private var topItems: [ActivityItem] { [.explorer, .search, .sourceControl, .debug, .extensions] }

    public var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.accentGradient)
                    .frame(width: 30, height: 30)
                    .shadow(color: Palette.accent.opacity(0.5), radius: 8, y: 2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 10)
            .padding(.bottom, 6)

            ForEach(topItems) { item in
                itemButton(item)
            }
            Spacer()
            itemButton(.settings)
                .padding(.bottom, 8)
        }
        .frame(width: 52)
        .frame(maxHeight: .infinity)
        .background(Palette.activityBar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Palette.border).frame(width: 1)
        }
    }

    @ViewBuilder
    private func itemButton(_ item: ActivityItem) -> some View {
        let isActive = item == appState.activeActivityItem && appState.isSidebarVisible
        Button {
            withAnimation(Motion.sidebar) { appState.selectActivity(item) }
        } label: {
            ZStack(alignment: .leading) {
                if isActive {
                    Capsule()
                        .fill(Palette.accentBarGradient)
                        .frame(width: 3, height: 22)
                        .offset(x: -1)
                }
                Image(systemName: item.systemImage)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(isActive ? Palette.textPrimary : Palette.textTertiary)
                    .frame(width: 52, height: 40)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .buttonStyle(ActivityButtonStyle(isActive: isActive))
        .help(item.rawValue.replacingOccurrences(of: "sourceControl", with: "Source Control").capitalized)
    }
}

private struct ActivityButtonStyle: ButtonStyle {
    let isActive: Bool
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background((hovering && !isActive) ? Color.white.opacity(0.04) : Color.clear)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
            .onHover { h in withAnimation(Motion.quick) { hovering = h } }
    }
}

/// The bottom status bar: branch, LSP status, cursor position, indentation, language.
/// Modernized with a subtle gradient, sectioned items, hover affordances, and icons.
public struct StatusBarView: View {
    @ObservedObject var appState: AppState
    var theme: Theme

    public init(appState: AppState, theme: Theme) {
        self.appState = appState
        self.theme = theme
    }

    public var body: some View {
        HStack(spacing: 0) {
            if let branch = appState.gitBranch {
                statusItem(icon: "arrow.triangle.branch", text: branch, accent: true)
            }
            statusItem(icon: "checkmark.circle.fill", text: appState.languageServerStatus,
                       color: Palette.success.opacity(0.95))

            Spacer()

            let sel = appState.statusSelection
            if sel.selectionCount > 1 {
                statusItem(icon: "cursorarrow.rays", text: "\(sel.selectionCount) selections")
            }
            statusItem(text: "Ln \(sel.line), Col \(sel.column)")
            statusItem(text: appState.configuration.insertSpaces
                       ? "Spaces: \(appState.configuration.tabSize)"
                       : "Tab Size: \(appState.configuration.tabSize)")
            statusItem(icon: "chevron.left.forwardslash.chevron.right",
                       text: appState.activeDocument?.languageID.capitalized ?? "Plain Text")
            statusItem(icon: "bell", text: "")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Palette.textSecondary)
        .frame(height: 26)
        .background(
            ZStack {
                Palette.titlebar
                LinearGradient(colors: [Palette.accent.opacity(0.10), Palette.accentPink.opacity(0.05)],
                               startPoint: .leading, endPoint: .trailing)
            }
        )
        .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
    }

    @ViewBuilder
    private func statusItem(icon: String? = nil, text: String,
                            accent: Bool = false, color: Color? = nil) -> some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .semibold)) }
            if !text.isEmpty { Text(text) }
        }
        .foregroundStyle(color ?? (accent ? Palette.textPrimary : Palette.textSecondary))
        .padding(.horizontal, 9)
        .frame(height: 26)
        .hoverHighlight(cornerRadius: 0, hoverColor: Color.white.opacity(0.06))
    }
}
