import SwiftUI
import AppKit
import VSSwiftCore

/// Headless snapshot utility used to render the workbench (including the AppKit text
/// canvas) to a PNG for visual QA and documentation. Uses a real `NSWindow` +
/// `cacheDisplay` so the `NSTextView`-backed editor is captured faithfully (unlike
/// `ImageRenderer`, which cannot snapshot `NSViewRepresentable`). Activated via the
/// `VSSWIFT_RENDER` environment variable; the optional `VSSWIFT_RENDER_SCENE` selects
/// which view to showcase.
@MainActor
public enum WorkbenchSnapshot {

    /// The view configuration to capture.
    public enum Scene: String {
        case editor          // Explorer + editor + terminal panel
        case sourceControl   // Source Control panel
        case search          // Search results panel

        public init(name: String?) {
            self = name.flatMap(Scene.init(rawValue:)) ?? .editor
        }
    }

    public static func render(to path: String,
                              scene: Scene = .editor,
                              size: CGSize = CGSize(width: 1280, height: 820)) {
        let model = WorkbenchModel()
        configure(model, for: scene)

        let view = WorkbenchView(model: model)
            .frame(width: size.width, height: size.height)

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)

        // Allow async work (git status, search, terminal output) to settle before capture.
        let settle: TimeInterval
        switch scene {
        case .editor: settle = 0.8
        case .sourceControl: settle = 1.6
        case .search: settle = 2.8
        }
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            FileHandle.standardError.write("snapshot: failed to make rep\n".data(using: .utf8)!)
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("snapshot: failed to encode png\n".data(using: .utf8)!)
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write("snapshot: wrote \(path)\n".data(using: .utf8)!)
    }

    private static func configure(_ model: WorkbenchModel, for scene: Scene) {
        switch scene {
        case .editor:
            model.appState.isPanelVisible = true
            model.appState.activePanelTab = .terminal
        case .sourceControl:
            model.appState.activeActivityItem = .sourceControl
            model.appState.isSidebarVisible = true
            model.git.refresh()
        case .search:
            model.appState.activeActivityItem = .search
            model.appState.isSidebarVisible = true
            model.searchQuery = "func greet"
            // The explorer roots load asynchronously after init; run the search once
            // they are available so results are present for the capture.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                model.runSearch()
            }
        }
    }
}
