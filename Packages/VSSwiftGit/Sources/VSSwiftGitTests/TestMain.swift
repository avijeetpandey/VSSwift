import Foundation
import VSSwiftCore
import VSSwiftGit
import VSTestKit

// MARK: - Test helpers

@discardableResult
func runGit(_ args: [String], in dir: URL) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = args
    p.currentDirectoryURL = dir
    var env = ProcessInfo.processInfo.environment
    env["GIT_CONFIG_COUNT"] = "0"
    p.environment = env
    p.standardOutput = Pipe()
    p.standardError = Pipe()
    try? p.run()
    p.waitUntilExit()
    return p.terminationStatus
}

func makeTempRepo() -> URL {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("vsswift-git-\(UUID().uuidString)")
    try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    runGit(["init", "-q", "-b", "main"], in: root)
    runGit(["config", "user.email", "test@example.com"], in: root)
    runGit(["config", "user.name", "Test User"], in: root)
    runGit(["config", "commit.gpgsign", "false"], in: root)
    return root
}

func write(_ text: String, to name: String, in dir: URL) {
    try? text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
}

// MARK: - Parser suite (pure)

func parserSuite() -> TestSuite {
    let s = TestSuite("Git Status Parser")
    let root = URL(fileURLWithPath: "/tmp/repo")

    s.test("parses branch with ahead and behind") { t in
        let porcelain = "## main...origin/main [ahead 2, behind 3]\n"
        let status = GitStatusParser.parse(porcelain: porcelain, root: root)
        t.equal(status.branch, "main")
        t.equal(status.upstream, "origin/main")
        t.equal(status.ahead, 2)
        t.equal(status.behind, 3)
    }

    s.test("parses simple branch with no upstream") { t in
        let status = GitStatusParser.parse(porcelain: "## develop\n", root: root)
        t.equal(status.branch, "develop")
        t.isNil(status.upstream)
        t.equal(status.ahead, 0)
    }

    s.test("parses no-commits-yet header") { t in
        let status = GitStatusParser.parse(porcelain: "## No commits yet on main\n", root: root)
        t.expect(status.hasNoCommitsYet)
        t.equal(status.branch, "main")
    }

    s.test("splits staged and unstaged changes") { t in
        let porcelain = """
        ## main
        M  staged.swift
         M dirty.swift
        ?? new.swift
        MM both.swift
        """
        let status = GitStatusParser.parse(porcelain: porcelain, root: root)
        t.expect(status.staged.contains { $0.path == "staged.swift" && $0.state == .modified })
        t.expect(status.unstaged.contains { $0.path == "dirty.swift" && $0.state == .modified })
        t.expect(status.unstaged.contains { $0.path == "new.swift" && $0.state == .untracked })
        // "MM" => staged + unstaged entries for the same file.
        t.expect(status.staged.contains { $0.path == "both.swift" })
        t.expect(status.unstaged.contains { $0.path == "both.swift" })
    }

    s.test("parses rename entries") { t in
        let status = GitStatusParser.parse(porcelain: "## main\nR  old.swift -> new.swift\n", root: root)
        let change = status.staged.first
        t.notNil(change)
        t.equal(change?.path, "new.swift")
        t.equal(change?.originalPath, "old.swift")
        t.equal(change?.state, .renamed)
    }
    return s
}

// MARK: - Service integration suite

func serviceSuite() -> TestSuite {
    let s = TestSuite("Git Service")

    s.test("detects repository root") { t in
        let root = makeTempRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = GitService()
        let detected = await service.repositoryRoot(for: root)
        t.notNil(detected)
        t.equal(detected?.standardizedFileURL.path, root.standardizedFileURL.path)
        t.expect(await service.isRepository(root))
    }

    s.test("reports non-repository directories") { t in
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vsswift-plain-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = GitService()
        t.expect(!(await service.isRepository(dir)))
        t.equal(await service.status(for: dir).isRepository, false)
    }

    s.test("stage, unstage and commit lifecycle") { t in
        let root = makeTempRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = GitService()
        write("let answer = 42\n", to: "a.swift", in: root)

        var status = await service.status(for: root)
        t.expect(status.unstaged.contains { $0.path == "a.swift" && $0.state == .untracked })

        try await service.stage("a.swift", root: root)
        status = await service.status(for: root)
        t.expect(status.staged.contains { $0.path == "a.swift" })
        t.expect(!status.unstaged.contains { $0.path == "a.swift" })

        try await service.unstage("a.swift", root: root)
        status = await service.status(for: root)
        t.expect(status.unstaged.contains { $0.path == "a.swift" })

        try await service.stageAll(root: root)
        let summary = try await service.commit(message: "Add a.swift", root: root)
        t.expect(!summary.isEmpty)

        status = await service.status(for: root)
        t.equal(status.changeCount, 0, "clean tree after commit")
        t.equal(status.branch, "main")
    }

    s.test("empty commit message throws") { t in
        let root = makeTempRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = GitService()
        await t.throwsAsync { try await service.commit(message: "   ", root: root) }
    }

    s.test("discard restores a modified tracked file") { t in
        let root = makeTempRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = GitService()
        write("original\n", to: "f.txt", in: root)
        try await service.stageAll(root: root)
        try await service.commit(message: "init", root: root)

        write("changed\n", to: "f.txt", in: root)
        var status = await service.status(for: root)
        let change = status.unstaged.first { $0.path == "f.txt" }
        t.notNil(change)
        try await service.discard(change!, root: root)

        status = await service.status(for: root)
        t.equal(status.changeCount, 0, "discard cleans the change")
        let restored = (try? String(contentsOf: root.appendingPathComponent("f.txt"), encoding: .utf8)) ?? ""
        t.equal(restored, "original\n")
    }

    s.test("diff reports work-tree changes") { t in
        let root = makeTempRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = GitService()
        write("one\n", to: "d.txt", in: root)
        try await service.stageAll(root: root)
        try await service.commit(message: "init", root: root)
        write("one\ntwo\n", to: "d.txt", in: root)

        let diff = await service.diff(path: "d.txt", staged: false, root: root)
        t.expect(diff.contains("+two"), "diff shows the added line")
    }
    return s
}

// MARK: - Async-throw helper

extension TestContext {
    /// Asserts that the async `body` throws.
    func throwsAsync(_ body: @Sendable () async throws -> Void,
                     _ message: @autoclosure () -> String = "expected throw",
                     file: StaticString = #file, line: UInt = #line) async {
        do {
            try await body()
            expect(false, message(), file: file, line: line)
        } catch {
            // expected
        }
    }
}

@main
struct Runner {
    static func main() async {
        await runSuitesAndExit([
            parserSuite(),
            serviceSuite()
        ])
    }
}
