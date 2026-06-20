import Foundation

/// Actor-isolated façade over the `git` command line. All repository inspection and
/// mutation (status, stage, unstage, discard, commit, diff) flows through here so the
/// main thread never blocks on git I/O. Mirrors VSCode's Source Control operations.
public actor GitService {
    private let runner: GitRunner

    public init(gitPath: String = "/usr/bin/git") {
        self.runner = GitRunner(gitPath: gitPath)
    }

    // MARK: - Discovery

    /// Returns the repository root containing `directory`, or `nil` if not a repo.
    public func repositoryRoot(for directory: URL) -> URL? {
        guard let result = try? runner.run(["rev-parse", "--show-toplevel"], in: directory),
              result.succeeded else { return nil }
        let path = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    /// True if `directory` is inside a git work tree.
    public func isRepository(_ directory: URL) -> Bool {
        repositoryRoot(for: directory) != nil
    }

    // MARK: - Status

    /// Computes the full status snapshot for the repository containing `directory`.
    public func status(for directory: URL) -> GitStatus {
        guard let root = repositoryRoot(for: directory) else { return .notARepository }
        guard let result = try? runner.run(["status", "--porcelain", "--branch"], in: root),
              result.succeeded else {
            return GitStatus(isRepository: true, root: root)
        }
        return GitStatusParser.parse(porcelain: result.standardOutput, root: root)
    }

    /// The current branch name (short), or `nil` outside a repository.
    public func currentBranch(for directory: URL) -> String? {
        guard let root = repositoryRoot(for: directory) else { return nil }
        guard let result = try? runner.run(["rev-parse", "--abbrev-ref", "HEAD"], in: root),
              result.succeeded else { return nil }
        let name = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : (name == "HEAD" ? "HEAD (detached)" : name)
    }

    // MARK: - Staging

    /// Stages a single path (adds new/modified, records deletions).
    public func stage(_ path: String, root: URL) throws {
        try expectSuccess(runner.run(["add", "--", path], in: root))
    }

    /// Stages every change in the work tree.
    public func stageAll(root: URL) throws {
        try expectSuccess(runner.run(["add", "-A"], in: root))
    }

    /// Unstages a single path, leaving the work-tree change intact.
    public func unstage(_ path: String, root: URL) throws {
        try expectSuccess(runner.run(["reset", "-q", "HEAD", "--", path], in: root))
    }

    /// Unstages everything currently in the index.
    public func unstageAll(root: URL) throws {
        try expectSuccess(runner.run(["reset", "-q", "HEAD"], in: root))
    }

    // MARK: - Discard

    /// Discards work-tree changes for `path`. Untracked files are deleted; tracked
    /// files are restored from HEAD. This is destructive, like VSCode's "Discard".
    public func discard(_ change: GitFileChange, root: URL) throws {
        if change.state == .untracked {
            try? FileManager.default.removeItem(at: change.url)
            return
        }
        try expectSuccess(runner.run(["checkout", "--", change.path], in: root))
    }

    // MARK: - Commit

    /// Commits the staged changes with `message`. Returns the resulting summary line.
    @discardableResult
    public func commit(message: String, root: URL) throws -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitError.commandFailed(code: 1, message: "Commit message cannot be empty.")
        }
        let result = try runner.run(["commit", "-m", trimmed], in: root)
        guard result.succeeded else {
            throw GitError.commandFailed(code: result.exitCode,
                                         message: combinedMessage(result))
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Diff

    /// Returns the unified diff for `path`. When `staged` is true the index diff
    /// (`git diff --staged`) is returned, otherwise the work-tree diff.
    public func diff(path: String, staged: Bool, root: URL) -> String {
        var args = ["diff"]
        if staged { args.append("--staged") }
        args.append(contentsOf: ["--", path])
        guard let result = try? runner.run(args, in: root), result.succeeded else { return "" }
        return result.standardOutput
    }

    // MARK: - Helpers

    private func expectSuccess(_ result: GitCommandResult) throws {
        guard result.succeeded else {
            throw GitError.commandFailed(code: result.exitCode, message: combinedMessage(result))
        }
    }

    private func combinedMessage(_ result: GitCommandResult) -> String {
        let err = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        let out = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return err.isEmpty ? out : err
    }
}
