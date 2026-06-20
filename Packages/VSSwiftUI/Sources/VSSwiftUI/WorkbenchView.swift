import SwiftUI
import VSSwiftCore
import VSSwiftWorkspace
import VSSwiftLSP

/// Top-level coordinator wiring together state, theme, editor, terminal, explorer,
/// search, and (optionally) the language server. Owned by the app and injected into
/// the workbench view hierarchy.
@MainActor
public final class WorkbenchModel: ObservableObject {
    public let appState = AppState()
    public let themeEngine = ThemeEngine()
    public let completion = CompletionController()
    public let terminal = TerminalViewModel()
    @Published public var editor = EditorViewModel(text: sampleSwift, languageID: "swift")
    public let explorer: ExplorerModel
    public let workspace: WorkspaceManager

    @Published public var searchQuery: String = ""
    @Published public var searchResults: [SearchMatch] = []

    private let searchEngine = SearchEngine()
    private var watcher: FileSystemWatcher?

    public init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let manager = WorkspaceManager(roots: [root])
        self.workspace = manager
        self.explorer = ExplorerModel(manager: manager)
        appState.gitBranch = "main"
        appState.openDocument(EditorDocument(url: root.appendingPathComponent("Untitled.swift"), languageID: "swift"))
        Task { await explorer.loadRoots() }
        startWatching(root: root)
    }

    private func startWatching(root: URL) {
        let watcher = FileSystemWatcher(paths: [root])
        watcher.start()
        self.watcher = watcher
        Task { [weak self] in
            for await _ in watcher.changes {
                await self?.explorer.loadRoots()
            }
        }
    }

    public func runSearch() {
        let roots = explorer.roots.map { $0.url }
        let query = searchQuery
        Task { [weak self] in
            guard let self else { return }
            let results = await self.searchEngine.search(query: query, roots: roots)
            await MainActor.run { self.searchResults = results }
        }
    }

    public func openFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return }
        let lang = url.pathExtension == "swift" ? "swift" : "plaintext"
        appState.openDocument(EditorDocument(url: url, languageID: lang))
        editor = EditorViewModel(text: text, fileURL: url, languageID: lang)
    }
}

/// The root workbench layout faithfully recreating the VSCode hierarchy.
public struct WorkbenchView: View {
    @ObservedObject var model: WorkbenchModel

    public init(model: WorkbenchModel) {
        self.model = model
    }

    public var body: some View {
        let theme = model.themeEngine.current
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ActivityBarView(appState: model.appState, theme: theme)
                if model.appState.isSidebarVisible {
                    SidebarView(appState: model.appState, theme: theme, explorer: model.explorer,
                                searchQuery: $model.searchQuery, searchResults: model.searchResults,
                                onSearch: { _ in model.runSearch() },
                                onOpenFile: { model.openFile($0) })
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                VStack(spacing: 0) {
                    EditorAreaView(appState: model.appState, theme: theme,
                                   editor: model.editor, completion: model.completion)
                        .frame(maxHeight: .infinity)
                    if model.appState.isPanelVisible {
                        PanelView(appState: model.appState, theme: theme,
                                  terminal: model.terminal, problems: [])
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            StatusBarView(appState: model.appState, theme: theme)
        }
        .frame(minWidth: 920, minHeight: 620)
        .background(Palette.bg)
        .animation(Motion.sidebar, value: model.appState.isSidebarVisible)
        .animation(Motion.snappy, value: model.appState.isPanelVisible)
        .toolbar {
            ToolbarItemGroup {
                Button { withAnimation(Motion.sidebar) { model.appState.toggleSidebar() } } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar (⌘B)")
                Button { withAnimation(Motion.snappy) { model.appState.togglePanel() } } label: {
                    Image(systemName: "rectangle.bottomthird.inset.filled")
                }
                .help("Toggle Panel (⌘J)")
            }
        }
    }
}

let sampleSwift = """
import Foundation

/// A sample Swift file demonstrating VSSwift semantic highlighting.
struct Greeter {
    let name: String

    func greet() -> String {
        return "Hello, \\(name)!"
    }
}

let greeter = Greeter(name: "World")
print(greeter.greet())
"""
