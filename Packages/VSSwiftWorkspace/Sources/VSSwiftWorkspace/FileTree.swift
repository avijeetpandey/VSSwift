import Foundation

/// A node in a workspace file tree. Children are loaded lazily to keep large
/// directory trees cheap; `loadChildren` reads one directory level off the main thread.
public struct FileNode: Sendable, Hashable, Identifiable {
    public var url: URL
    public var isDirectory: Bool
    public var name: String

    public var id: URL { url }

    public init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
        self.name = url.lastPathComponent
    }
}

/// Reads file-system directory structure asynchronously.
public struct FileTreeLoader: Sendable {
    public var ignoredNames: Set<String>

    public init(ignoredNames: Set<String> = [".git", ".build", "node_modules", ".DS_Store"]) {
        self.ignoredNames = ignoredNames
    }

    /// Lists the immediate children of `directory`, directories first then files,
    /// each alphabetically. Ignored names are skipped.
    public func children(of directory: URL) async throws -> [FileNode] {
        try await Task.detached(priority: .utility) { [ignoredNames] in
            let fm = FileManager.default
            let contents = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])

            var nodes: [FileNode] = []
            for url in contents {
                if ignoredNames.contains(url.lastPathComponent) { continue }
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                nodes.append(FileNode(url: url, isDirectory: isDir))
            }
            return nodes.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }.value
    }
}

/// Manages one or more workspace roots (multi-root workspaces).
public actor WorkspaceManager {
    public private(set) var roots: [URL]
    private let loader: FileTreeLoader

    public init(roots: [URL] = [], loader: FileTreeLoader = FileTreeLoader()) {
        self.roots = roots
        self.loader = loader
    }

    public func addRoot(_ url: URL) {
        if !roots.contains(url) { roots.append(url) }
    }

    /// Replaces the entire set of workspace roots (used when opening a new folder).
    public func setRoots(_ urls: [URL]) {
        roots = urls
    }

    public func removeRoot(_ url: URL) {
        roots.removeAll { $0 == url }
    }

    public func children(of directory: URL) async throws -> [FileNode] {
        try await loader.children(of: directory)
    }

    public func rootNodes() -> [FileNode] {
        roots.map { FileNode(url: $0, isDirectory: true) }
    }
}
