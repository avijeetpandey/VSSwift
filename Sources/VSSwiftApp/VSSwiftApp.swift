import SwiftUI
import AppKit
import VSSwiftUI
import VSSwiftCore

/// The VSSwift application entry point. Hosts the workbench in a single window and
/// wires up the VSCode-style keyboard shortcuts for toggling the sidebar and panel.
@main
struct VSSwiftApp: App {
    @StateObject private var model = WorkbenchModel(rootDirectory: VSSwiftApp.initialRoot())
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Resolves the folder to open at launch. The `vsswift` CLI passes the target
    /// directory via the `VSSWIFT_OPEN` environment variable; a directory given as a
    /// command-line argument is also honored. Falls back to the current directory.
    static func initialRoot() -> URL? {
        let fm = FileManager.default
        func directory(at path: String) -> URL? {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }
        if let path = ProcessInfo.processInfo.environment["VSSWIFT_OPEN"], !path.isEmpty,
           let url = directory(at: path) {
            return url
        }
        for arg in CommandLine.arguments.dropFirst() {
            if let url = directory(at: arg) { return url }
        }
        return nil
    }

    var body: some Scene {
        WindowGroup {
            WorkbenchView(model: model)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Folder…") {
                    if let url = FolderPicker.presentOpenFolder() {
                        model.openFolder(url)
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") { model.appState.toggleSidebar() }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Toggle Panel") { model.appState.togglePanel() }
                    .keyboardShortcut("j", modifiers: .command)
                Button("Toggle Terminal") { model.appState.toggleTerminal() }
                    .keyboardShortcut("`", modifiers: .command)

                Divider()

                Button("Show Explorer") { model.appState.revealActivity(.explorer) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Show Search") { model.appState.revealActivity(.search) }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Show Source Control") { model.appState.revealActivity(.sourceControl) }
                    .keyboardShortcut("g", modifiers: [.control, .shift])
                Button("Show Run and Debug") { model.appState.revealActivity(.debug) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Show Extensions") { model.appState.revealActivity(.extensions) }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
            }
        }
    }
}

/// Applies the bundled application icon at runtime. When the editor is launched via
/// `swift run` there is no `.app` bundle to carry the icon, so we load it from the
/// SwiftPM resource bundle and assign it to the running application.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }
        if let path = ProcessInfo.processInfo.environment["VSSWIFT_RENDER"] {
            let scene = WorkbenchSnapshot.Scene(name: ProcessInfo.processInfo.environment["VSSWIFT_RENDER_SCENE"])
            WorkbenchSnapshot.render(to: path, scene: scene)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSApplication.shared.terminate(nil)
            }
            return
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
