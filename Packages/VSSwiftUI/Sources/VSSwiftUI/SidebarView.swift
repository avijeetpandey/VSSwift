import SwiftUI
import VSSwiftCore
import VSSwiftWorkspace

/// The collapsible sidebar; content depends on the active activity item. Modernized
/// with a styled header, file-type icons, hover rows, and a polished search panel.
public struct SidebarView: View {
    @ObservedObject var appState: AppState
    var theme: Theme
    @ObservedObject var explorer: ExplorerModel
    @Binding var searchQuery: String
    var searchResults: [SearchMatch]
    var onSearch: (String) -> Void
    var onOpenFile: (URL) -> Void

    public init(appState: AppState, theme: Theme, explorer: ExplorerModel,
                searchQuery: Binding<String>, searchResults: [SearchMatch],
                onSearch: @escaping (String) -> Void, onOpenFile: @escaping (URL) -> Void) {
        self.appState = appState
        self.theme = theme
        self.explorer = explorer
        self._searchQuery = searchQuery
        self.searchResults = searchResults
        self.onSearch = onSearch
        self.onOpenFile = onOpenFile
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                if appState.activeActivityItem == .explorer {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 36)

            content
        }
        .frame(width: 270)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.border).frame(width: 1) }
    }

    private var title: String {
        switch appState.activeActivityItem {
        case .explorer: return "Explorer"
        case .search: return "Search"
        case .sourceControl: return "Source Control"
        case .debug: return "Run and Debug"
        case .extensions: return "Extensions"
        case .settings: return "Settings"
        }
    }

    @ViewBuilder private var content: some View {
        switch appState.activeActivityItem {
        case .explorer:
            FileExplorerView(explorer: explorer, onOpenFile: onOpenFile)
        case .search:
            searchPanel
        default:
            emptyState
        }
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                TextField("Search files", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textPrimary)
                    .onSubmit { onSearch(searchQuery) }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Palette.borderStrong, lineWidth: 1)
            )
            .padding(.horizontal, 12)

            if !searchResults.isEmpty {
                Text("\(searchResults.count) RESULTS")
                    .font(.system(size: 10, weight: .bold)).tracking(0.5)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.horizontal, 14)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(searchResults.enumerated()), id: \.offset) { _, match in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                let icon = FileIconResolver.icon(for: match.url.lastPathComponent)
                                Image(systemName: icon.symbol).font(.system(size: 11)).foregroundStyle(icon.color)
                                Text(match.url.lastPathComponent)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Palette.textPrimary)
                                Spacer(minLength: 0)
                                Text("\(match.line + 1)")
                                    .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                            }
                            Text(match.lineText.trimmingCharacters(in: .whitespaces))
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hoverHighlight(cornerRadius: 6)
                        .padding(.horizontal, 6)
                        .onTapGesture { onOpenFile(match.url) }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.top, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: iconForActivity)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text("\(title)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
            Text("Coming soon in this build.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var iconForActivity: String {
        appState.activeActivityItem.systemImage
    }
}

/// Observable model backing the lazy file explorer tree.
@MainActor
public final class ExplorerModel: ObservableObject {
    @Published public var roots: [FileNode] = []
    @Published public var childrenByURL: [URL: [FileNode]] = [:]
    @Published public var expanded: Set<URL> = []
    @Published public var selected: URL?

    private let manager: WorkspaceManager

    public init(manager: WorkspaceManager) {
        self.manager = manager
    }

    public func loadRoots() async {
        roots = await manager.rootNodes()
        for root in roots {
            expanded.insert(root.url)
            await loadChildren(of: root.url)
        }
    }

    public func loadChildren(of url: URL) async {
        if let children = try? await manager.children(of: url) {
            childrenByURL[url] = children
        }
    }

    public func toggle(_ node: FileNode) async {
        guard node.isDirectory else { return }
        if expanded.contains(node.url) {
            expanded.remove(node.url)
        } else {
            expanded.insert(node.url)
            if childrenByURL[node.url] == nil { await loadChildren(of: node.url) }
        }
    }
}

/// Renders the recursive file tree with modern icons, hover and selection states.
public struct FileExplorerView: View {
    @ObservedObject var explorer: ExplorerModel
    var onOpenFile: (URL) -> Void

    public init(explorer: ExplorerModel, onOpenFile: @escaping (URL) -> Void) {
        self.explorer = explorer
        self.onOpenFile = onOpenFile
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(explorer.roots) { root in
                    AnyView(nodeRows(for: root, depth: 0))
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private func nodeRows(for node: FileNode, depth: Int) -> some View {
        row(node, depth: depth)
        if node.isDirectory, explorer.expanded.contains(node.url),
           let children = explorer.childrenByURL[node.url] {
            ForEach(children) { child in
                AnyView(nodeRows(for: child, depth: depth + 1))
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func row(_ node: FileNode, depth: Int) -> some View {
        let isExpanded = explorer.expanded.contains(node.url)
        let isSelected = explorer.selected == node.url
        return HStack(spacing: 5) {
            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 12)
                let folder = FileIconResolver.folder(expanded: isExpanded)
                Image(systemName: folder.symbol).font(.system(size: 12)).foregroundStyle(folder.color)
            } else {
                Spacer().frame(width: 12)
                let icon = FileIconResolver.icon(for: node.name)
                Image(systemName: icon.symbol).font(.system(size: 12)).foregroundStyle(icon.color)
            }
            Text(node.name)
                .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * 13 + 6)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .hoverHighlight(cornerRadius: 6, isActive: isSelected)
        .onTapGesture {
            explorer.selected = node.url
            if node.isDirectory {
                withAnimation(Motion.smooth) { Task { await explorer.toggle(node) } }
            } else {
                onOpenFile(node.url)
            }
        }
    }
}
