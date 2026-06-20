import Foundation
import VSSwiftCore

/// A single search hit within a file.
public struct SearchMatch: Sendable, Hashable {
    public var url: URL
    public var line: Int           // zero-based
    public var column: Int         // zero-based character offset
    public var lineText: String
    public var matchLength: Int

    public init(url: URL, line: Int, column: Int, lineText: String, matchLength: Int) {
        self.url = url
        self.line = line
        self.column = column
        self.lineText = lineText
        self.matchLength = matchLength
    }
}

/// Options controlling a workspace search.
public struct SearchOptions: Sendable {
    public var isRegex: Bool
    public var caseSensitive: Bool
    public var wholeWord: Bool
    public var includeExtensions: Set<String>?   // nil = all text files
    public var ignoredDirectories: Set<String>
    public var maxFileSizeBytes: Int

    public init(isRegex: Bool = false, caseSensitive: Bool = false, wholeWord: Bool = false,
                includeExtensions: Set<String>? = nil,
                ignoredDirectories: Set<String> = [".git", ".build", "node_modules"],
                maxFileSizeBytes: Int = 5_000_000) {
        self.isRegex = isRegex
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
        self.includeExtensions = includeExtensions
        self.ignoredDirectories = ignoredDirectories
        self.maxFileSizeBytes = maxFileSizeBytes
    }
}

/// A highly parallel, line-scanning workspace search (ripgrep-style) that fans work
/// out across a `TaskGroup` so the main thread never blocks.
public struct SearchEngine: Sendable {
    public init() {}

    /// Compiles the query into a matcher. Returns nil if a regex query is invalid.
    private func makeRegex(_ query: String, _ options: SearchOptions) -> NSRegularExpression? {
        var pattern = options.isRegex ? query : NSRegularExpression.escapedPattern(for: query)
        if options.wholeWord { pattern = "\\b\(pattern)\\b" }
        var flags: NSRegularExpression.Options = []
        if !options.caseSensitive { flags.insert(.caseInsensitive) }
        return try? NSRegularExpression(pattern: pattern, options: flags)
    }

    /// Enumerates candidate files under `roots` honoring ignore/extension filters.
    private func candidateFiles(roots: [URL], options: SearchOptions) -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if values?.isDirectory == true {
                    if options.ignoredDirectories.contains(url.lastPathComponent) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                if let ext = options.includeExtensions, !ext.contains(url.pathExtension) { continue }
                if let size = values?.fileSize, size > options.maxFileSizeBytes { continue }
                files.append(url)
            }
        }
        return files
    }

    /// Searches a single file's contents.
    private func search(file url: URL, regex: NSRegularExpression) -> [SearchMatch] {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else { return [] }
        var matches: [SearchMatch] = []
        let lines = content.components(separatedBy: "\n")
        for (lineIndex, line) in lines.enumerated() {
            if line.isEmpty { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            regex.enumerateMatches(in: line, options: [], range: range) { result, _, _ in
                guard let result, let r = Range(result.range, in: line) else { return }
                let column = line.distance(from: line.startIndex, to: r.lowerBound)
                let length = line.distance(from: r.lowerBound, to: r.upperBound)
                matches.append(SearchMatch(url: url, line: lineIndex, column: column,
                                           lineText: line, matchLength: length))
            }
        }
        return matches
    }

    /// Runs a parallel search across all roots, returning matches grouped by discovery.
    public func search(query: String, roots: [URL], options: SearchOptions = SearchOptions()) async -> [SearchMatch] {
        guard !query.isEmpty, let regex = makeRegex(query, options) else { return [] }
        let files = candidateFiles(roots: roots, options: options)

        return await withTaskGroup(of: [SearchMatch].self) { group in
            for file in files {
                group.addTask { self.search(file: file, regex: regex) }
            }
            var all: [SearchMatch] = []
            for await fileMatches in group {
                all.append(contentsOf: fileMatches)
            }
            // Stable ordering: by path, then line, then column.
            return all.sorted {
                if $0.url.path != $1.url.path { return $0.url.path < $1.url.path }
                if $0.line != $1.line { return $0.line < $1.line }
                return $0.column < $1.column
            }
        }
    }
}
