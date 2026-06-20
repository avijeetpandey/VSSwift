import Foundation
import Combine

/// Identifies a primary view in the activity bar / sidebar.
public enum ActivityItem: String, Sendable, CaseIterable, Identifiable {
    case explorer, search, sourceControl, debug, extensions, settings
    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .explorer: return "doc.on.doc"
        case .search: return "magnifyingglass"
        case .sourceControl: return "arrow.triangle.branch"
        case .debug: return "ladybug"
        case .extensions: return "puzzlepiece.extension"
        case .settings: return "gearshape"
        }
    }
}

/// Bottom panel tabs.
public enum PanelTab: String, Sendable, CaseIterable, Identifiable {
    case problems, output, debugConsole, terminal
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .problems: return "Problems"
        case .output: return "Output"
        case .debugConsole: return "Debug Console"
        case .terminal: return "Terminal"
        }
    }

    /// SF Symbol used in the panel tab bar.
    public var systemImage: String {
        switch self {
        case .problems: return "exclamationmark.triangle"
        case .output: return "text.alignleft"
        case .debugConsole: return "ladybug"
        case .terminal: return "terminal"
        }
    }
}

/// An open editor document descriptor (UI-level; the buffer lives in VSSwiftEngine).
public struct EditorDocument: Sendable, Hashable, Identifiable {
    public var id: URL { url }
    public var url: URL
    public var displayName: String
    public var isDirty: Bool
    public var languageID: String

    public init(url: URL, isDirty: Bool = false, languageID: String = "plaintext") {
        self.url = url
        self.displayName = url.lastPathComponent
        self.isDirty = isDirty
        self.languageID = languageID
    }
}

/// Cursor/selection summary surfaced in the status bar.
public struct StatusSelectionInfo: Sendable, Hashable {
    public var line: Int
    public var column: Int
    public var selectionCount: Int

    public init(line: Int = 1, column: Int = 1, selectionCount: Int = 1) {
        self.line = line
        self.column = column
        self.selectionCount = selectionCount
    }
}

/// The observable workbench state driving the SwiftUI shell.
@MainActor
public final class AppState: ObservableObject {
    @Published public var activeActivityItem: ActivityItem = .explorer
    @Published public var isSidebarVisible: Bool = true
    @Published public var isPanelVisible: Bool = false
    @Published public var activePanelTab: PanelTab = .terminal
    @Published public var openDocuments: [EditorDocument] = []
    @Published public var activeDocumentID: URL?
    @Published public var configuration: EditorConfiguration = .default
    @Published public var statusSelection: StatusSelectionInfo = .init()
    @Published public var gitBranch: String?
    @Published public var languageServerStatus: String = "Ready"

    public init() {}

    public var activeDocument: EditorDocument? {
        guard let id = activeDocumentID else { return nil }
        return openDocuments.first { $0.id == id }
    }

    public func toggleSidebar() { isSidebarVisible.toggle() }
    public func togglePanel() { isPanelVisible.toggle() }

    public func selectActivity(_ item: ActivityItem) {
        if activeActivityItem == item && isSidebarVisible {
            isSidebarVisible = false
        } else {
            activeActivityItem = item
            isSidebarVisible = true
        }
    }

    /// Reveals an activity view, always showing the sidebar (used by keyboard
    /// shortcuts like ⌘⇧E / ⌘⇧F / ⌃⇧G which "show" rather than toggle).
    public func revealActivity(_ item: ActivityItem) {
        activeActivityItem = item
        isSidebarVisible = true
    }

    /// Shows the bottom panel focused on `tab`.
    public func showPanel(_ tab: PanelTab) {
        activePanelTab = tab
        isPanelVisible = true
    }

    /// Toggles the integrated terminal (⌘`): hides the panel if the terminal is
    /// already showing, otherwise reveals the panel on the terminal tab.
    public func toggleTerminal() {
        if isPanelVisible && activePanelTab == .terminal {
            isPanelVisible = false
        } else {
            activePanelTab = .terminal
            isPanelVisible = true
        }
    }

    @discardableResult
    public func openDocument(_ document: EditorDocument) -> EditorDocument {
        if !openDocuments.contains(where: { $0.id == document.id }) {
            openDocuments.append(document)
        }
        activeDocumentID = document.id
        return document
    }

    public func closeDocument(_ id: URL) {
        openDocuments.removeAll { $0.id == id }
        if activeDocumentID == id {
            activeDocumentID = openDocuments.last?.id
        }
    }
}
