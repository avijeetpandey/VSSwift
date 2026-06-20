import AppKit

/// Presents the native macOS folder chooser, mirroring VSCode's "Open Folder…".
/// Lives in the UI layer because it is the only layer permitted to touch AppKit.
public enum FolderPicker {
    /// Runs a modal `NSOpenPanel` configured for a single directory selection.
    /// Returns the chosen folder URL, or `nil` if the user cancels.
    @MainActor
    public static func presentOpenFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Folder"
        panel.prompt = "Open"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
