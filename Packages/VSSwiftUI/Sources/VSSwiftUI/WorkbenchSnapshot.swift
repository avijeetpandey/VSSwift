import SwiftUI
import AppKit
import VSSwiftCore

/// Headless snapshot utility used to render the workbench (including the AppKit text
/// canvas) to a PNG for visual QA. Uses a real `NSWindow` + `cacheDisplay` so the
/// `NSTextView`-backed editor is captured faithfully (unlike `ImageRenderer`, which
/// cannot snapshot `NSViewRepresentable`). Activated via `VSSWIFT_RENDER`.
@MainActor
public enum WorkbenchSnapshot {
    public static func render(to path: String, size: CGSize = CGSize(width: 1280, height: 820)) {
        let model = WorkbenchModel()
        model.appState.isPanelVisible = true

        let view = WorkbenchView(model: model)
            .frame(width: size.width, height: size.height)

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)

        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
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
}
