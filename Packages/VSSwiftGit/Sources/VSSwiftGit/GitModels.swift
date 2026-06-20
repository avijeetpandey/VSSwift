import Foundation

/// The semantic state of a changed file, used to pick an icon/letter in the UI.
public enum GitFileState: String, Sendable, Hashable {
    case modified
    case added
    case deleted
    case renamed
    case copied
    case untracked
    case ignored
    case conflicted
    case unknown

    /// A single-letter badge mirroring VSCode's Source Control gutter (M, A, D, U…).
    public var badge: String {
        switch self {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        case .renamed: return "R"
        case .copied: return "C"
        case .untracked: return "U"
        case .ignored: return "I"
        case .conflicted: return "!"
        case .unknown: return "?"
        }
    }

    /// Maps a git porcelain status character to a semantic state.
    public static func from(code: Character) -> GitFileState {
        switch code {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        case "U": return .conflicted
        case "?": return .untracked
        case "!": return .ignored
        default: return .unknown
        }
    }
}

/// A single changed file in the working tree or index.
public struct GitFileChange: Sendable, Hashable, Identifiable {
    /// Path relative to the repository root.
    public var path: String
    /// Absolute URL of the file.
    public var url: URL
    /// Whether this entry represents a staged (index) change.
    public var isStaged: Bool
    /// Semantic state used for the badge/icon.
    public var state: GitFileState
    /// Original path for renames (relative to repo root), if any.
    public var originalPath: String?

    public var id: String { (isStaged ? "staged:" : "unstaged:") + path }

    public var name: String { (path as NSString).lastPathComponent }

    public init(path: String, url: URL, isStaged: Bool, state: GitFileState, originalPath: String? = nil) {
        self.path = path
        self.url = url
        self.isStaged = isStaged
        self.state = state
        self.originalPath = originalPath
    }
}

/// A snapshot of a repository's status: branch, tracking info, and changes.
public struct GitStatus: Sendable, Hashable {
    public var isRepository: Bool
    public var root: URL?
    public var branch: String?
    public var upstream: String?
    public var ahead: Int
    public var behind: Int
    public var hasNoCommitsYet: Bool
    public var staged: [GitFileChange]
    public var unstaged: [GitFileChange]

    public init(isRepository: Bool = false,
                root: URL? = nil,
                branch: String? = nil,
                upstream: String? = nil,
                ahead: Int = 0,
                behind: Int = 0,
                hasNoCommitsYet: Bool = false,
                staged: [GitFileChange] = [],
                unstaged: [GitFileChange] = []) {
        self.isRepository = isRepository
        self.root = root
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.hasNoCommitsYet = hasNoCommitsYet
        self.staged = staged
        self.unstaged = unstaged
    }

    /// A non-repository placeholder.
    public static let notARepository = GitStatus(isRepository: false)

    /// Total number of changed entries across the index and work tree.
    public var changeCount: Int { staged.count + unstaged.count }
}
