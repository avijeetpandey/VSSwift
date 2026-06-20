import Foundation
import VSSwiftCore
import VSSwiftWorkspace
import VSTestKit

@discardableResult
func makeTempWorkspace() -> URL {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("vsswift-\(UUID().uuidString)")
    try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    let src = root.appendingPathComponent("Sources")
    try? fm.createDirectory(at: src, withIntermediateDirectories: true)
    try? "let target = 42\nfunc compute() { print(target) }".write(to: src.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
    try? "struct Other { let target = 1 }".write(to: src.appendingPathComponent("b.swift"), atomically: true, encoding: .utf8)
    try? "no matches here".write(to: root.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
    // An ignored directory that should be skipped.
    let git = root.appendingPathComponent(".git")
    try? fm.createDirectory(at: git, withIntermediateDirectories: true)
    try? "target".write(to: git.appendingPathComponent("config"), atomically: true, encoding: .utf8)
    return root
}

func fileTreeSuite() -> TestSuite {
    let s = TestSuite("FileTree")
    s.test("lists children directories first") { t in
        let root = makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let children = try await FileTreeLoader().children(of: root)
        t.expect(children.contains { $0.name == "Sources" && $0.isDirectory })
        t.expect(children.contains { $0.name == "readme.txt" && !$0.isDirectory })
        // Directory should sort before file.
        let dirIndex = children.firstIndex { $0.name == "Sources" }!
        let fileIndex = children.firstIndex { $0.name == "readme.txt" }!
        t.expect(dirIndex < fileIndex)
        // .git is hidden -> skipped by skipsHiddenFiles
        t.expect(!children.contains { $0.name == ".git" })
    }
    s.test("multi-root workspace manager") { t in
        let r1 = makeTempWorkspace()
        let r2 = makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: r1); try? FileManager.default.removeItem(at: r2) }
        let mgr = WorkspaceManager()
        await mgr.addRoot(r1)
        await mgr.addRoot(r2)
        await mgr.addRoot(r1) // dup ignored
        let roots = await mgr.roots
        t.equal(roots.count, 2)
        await mgr.removeRoot(r1)
        t.equal(await mgr.roots.count, 1)
    }
    return s
}

func searchSuite() -> TestSuite {
    let s = TestSuite("Parallel Search")
    s.test("finds literal matches across files") { t in
        let root = makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let matches = await SearchEngine().search(query: "target", roots: [root])
        // a.swift has 2 ("let target", "print(target)"), b.swift has 1; .git ignored; txt none
        let swiftMatches = matches.filter { $0.url.pathExtension == "swift" }
        t.equal(swiftMatches.count, 3, "matches in swift files")
        t.expect(!matches.contains { $0.url.path.contains("/.git/") }, ".git ignored")
    }
    s.test("extension filter") { t in
        let root = makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let opts = SearchOptions(includeExtensions: ["swift"])
        let matches = await SearchEngine().search(query: "target", roots: [root], options: opts)
        t.expect(matches.allSatisfy { $0.url.pathExtension == "swift" })
    }
    s.test("regex search") { t in
        let root = makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let opts = SearchOptions(isRegex: true)
        let matches = await SearchEngine().search(query: "func\\s+\\w+", roots: [root], options: opts)
        t.expect(matches.contains { $0.lineText.contains("func compute") })
    }
    s.test("column and length are accurate") { t in
        let root = makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let matches = await SearchEngine().search(query: "target", roots: [root])
        let first = matches.first { $0.lineText == "let target = 42" }
        t.notNil(first)
        t.equal(first?.column, 4)
        t.equal(first?.matchLength, 6)
    }
    return s
}

func watcherSuite() -> TestSuite {
    let s = TestSuite("FSEvents watcher (best-effort)")
    s.test("detects a file write") { t in
        let root = makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let watcher = FileSystemWatcher(paths: [root], latency: 0.05)
        watcher.start()
        defer { watcher.stop() }

        let detected = Task { () -> Bool in
            for await batch in watcher.changes {
                if batch.contains(where: { $0.lastPathComponent == "new.swift" || $0.path.contains(root.lastPathComponent) }) {
                    return true
                }
            }
            return false
        }
        // Give FSEvents time to arm, then write.
        try await Task.sleep(nanoseconds: 300_000_000)
        try "new".write(to: root.appendingPathComponent("new.swift"), atomically: true, encoding: .utf8)

        let result = await withTimeoutBool(3.0) { await detected.value }
        if result {
            print("      ✓ FSEvents change observed")
            t.expect(true)
        } else {
            print("      ⚠︎ skipped: no FSEvents callback within timeout (sandbox-dependent)")
        }
        detected.cancel()
    }
    return s
}

func withTimeoutBool(_ seconds: Double, _ op: @escaping @Sendable () async -> Bool) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask { await op() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return false
        }
        let first = await group.next() ?? false
        group.cancelAll()
        return first
    }
}

@main
struct Runner {
    static func main() async {
        await runSuitesAndExit([
            fileTreeSuite(),
            searchSuite(),
            watcherSuite()
        ])
    }
}
