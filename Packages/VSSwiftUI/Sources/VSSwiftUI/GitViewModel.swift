import Foundation
import Combine
import VSSwiftGit

/// Observable Source Control state bridging the actor-isolated ``GitService`` to SwiftUI.
/// Owns the current repository root, the latest status snapshot, and the commit message.
@MainActor
public final class GitViewModel: ObservableObject {
    @Published public private(set) var status: GitStatus = .notARepository
    @Published public var commitMessage: String = ""
    @Published public private(set) var isWorking: Bool = false
    @Published public private(set) var lastError: String?

    private let service = GitService()
    private var root: URL

    /// Invoked on the main actor whenever a fresh status snapshot is available
    /// (used to mirror the active branch into the status bar).
    public var onStatusChanged: ((GitStatus) -> Void)?

    public init(root: URL) {
        self.root = root
    }

    /// The repository root reported by git, falling back to the workspace root.
    private var repoRoot: URL { status.root ?? root }

    /// Points the view model at a new workspace folder and refreshes.
    public func setRoot(_ url: URL) {
        root = url
        refresh()
    }

    /// Reloads the status snapshot from git.
    public func refresh() {
        let dir = root
        Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.service.status(for: dir)
            self.status = snapshot
            self.onStatusChanged?(snapshot)
        }
    }

    // MARK: - Mutations

    public func stage(_ change: GitFileChange) {
        perform { try await $0.stage(change.path, root: self.repoRoot) }
    }

    public func unstage(_ change: GitFileChange) {
        perform { try await $0.unstage(change.path, root: self.repoRoot) }
    }

    public func stageAll() {
        perform { try await $0.stageAll(root: self.repoRoot) }
    }

    public func unstageAll() {
        perform { try await $0.unstageAll(root: self.repoRoot) }
    }

    public func discard(_ change: GitFileChange) {
        perform { try await $0.discard(change, root: self.repoRoot) }
    }

    public func commit() {
        let message = commitMessage
        perform(onSuccess: { self.commitMessage = "" }) {
            try await $0.commit(message: message, root: self.repoRoot)
        }
    }

    public var canCommit: Bool {
        !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !status.staged.isEmpty
    }

    // MARK: - Helpers

    /// Runs a mutating git operation, then refreshes; surfaces any error message.
    private func perform(onSuccess: (() -> Void)? = nil,
                         _ body: @escaping (GitService) async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        let service = self.service
        Task { [weak self] in
            guard let self else { return }
            do {
                try await body(service)
                onSuccess?()
            } catch {
                if case let GitError.commandFailed(_, message) = error {
                    self.lastError = message
                } else {
                    self.lastError = error.localizedDescription
                }
            }
            self.isWorking = false
            self.refresh()
        }
    }
}
