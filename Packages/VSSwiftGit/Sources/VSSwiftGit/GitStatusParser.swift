import Foundation

/// Parses the output of `git status --porcelain --branch` into a ``GitStatus``.
/// Kept as a pure, dependency-free function so it is trivially unit-testable.
public enum GitStatusParser {

    public static func parse(porcelain: String, root: URL) -> GitStatus {
        var status = GitStatus(isRepository: true, root: root)
        let lines = porcelain.split(separator: "\n", omittingEmptySubsequences: false)

        for rawLine in lines {
            let line = String(rawLine)
            if line.isEmpty { continue }
            if line.hasPrefix("## ") {
                parseBranch(String(line.dropFirst(3)), into: &status)
            } else {
                parseEntry(line, root: root, into: &status)
            }
        }
        return status
    }

    // MARK: - Branch header

    private static func parseBranch(_ text: String, into status: inout GitStatus) {
        if text.hasPrefix("No commits yet on ") {
            status.hasNoCommitsYet = true
            status.branch = String(text.dropFirst("No commits yet on ".count))
            return
        }
        if text.hasPrefix("HEAD (no branch)") {
            status.branch = "HEAD (detached)"
            return
        }

        var remainder = text
        // Tracking section: "main...origin/main [ahead 1, behind 2]"
        if let bracket = remainder.firstIndex(of: "[") {
            let tracking = remainder[remainder.index(after: bracket)...]
                .prefix(while: { $0 != "]" })
            status.ahead = number(after: "ahead", in: String(tracking))
            status.behind = number(after: "behind", in: String(tracking))
            remainder = String(remainder[..<bracket]).trimmingCharacters(in: .whitespaces)
        }

        if let range = remainder.range(of: "...") {
            status.branch = String(remainder[..<range.lowerBound])
            status.upstream = String(remainder[range.upperBound...])
        } else {
            status.branch = remainder.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func number(after keyword: String, in text: String) -> Int {
        guard let range = text.range(of: keyword) else { return 0 }
        let digits = text[range.upperBound...].drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
        return Int(digits) ?? 0
    }

    // MARK: - File entries

    private static func parseEntry(_ line: String, root: URL, into status: inout GitStatus) {
        guard line.count >= 3 else { return }
        let chars = Array(line)
        let index = chars[0]
        let worktree = chars[1]
        let payload = String(chars[3...])

        var path = payload
        var original: String? = nil
        if let range = payload.range(of: " -> ") {
            original = String(payload[..<range.lowerBound])
            path = String(payload[range.upperBound...])
        }
        let url = root.appendingPathComponent(path)

        // Untracked files.
        if index == "?" && worktree == "?" {
            status.unstaged.append(GitFileChange(path: path, url: url, isStaged: false, state: .untracked))
            return
        }

        // Merge conflicts (e.g. UU, AA, DD) surface as a single unstaged entry.
        if index == "U" || worktree == "U" {
            status.unstaged.append(GitFileChange(path: path, url: url, isStaged: false, state: .conflicted, originalPath: original))
            return
        }

        if index != " " {
            status.staged.append(GitFileChange(path: path, url: url, isStaged: true,
                                               state: GitFileState.from(code: index), originalPath: original))
        }
        if worktree != " " {
            status.unstaged.append(GitFileChange(path: path, url: url, isStaged: false,
                                                 state: GitFileState.from(code: worktree), originalPath: original))
        }
    }
}
