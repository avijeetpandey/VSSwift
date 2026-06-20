import SwiftUI
import VSSwiftCore
import VSSwiftGit

/// The Source Control panel: commit box plus staged/unstaged change lists with inline
/// stage / unstage / discard actions. Faithfully mirrors VSCode's SCM view.
public struct SourceControlView: View {
    @ObservedObject var git: GitViewModel
    var onOpenFile: (URL) -> Void

    public init(git: GitViewModel, onOpenFile: @escaping (URL) -> Void) {
        self.git = git
        self.onOpenFile = onOpenFile
    }

    public var body: some View {
        if git.status.isRepository {
            repositoryBody
        } else {
            notARepository
        }
    }

    // MARK: - Repository content

    private var repositoryBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            commitBox
            if let error = git.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.danger)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !git.status.staged.isEmpty {
                        sectionHeader(title: "Staged Changes", count: git.status.staged.count) {
                            actionIcon("minus", help: "Unstage All Changes") { git.unstageAll() }
                        }
                        ForEach(git.status.staged) { change in
                            changeRow(change, staged: true)
                        }
                    }
                    if !git.status.unstaged.isEmpty {
                        sectionHeader(title: "Changes", count: git.status.unstaged.count) {
                            actionIcon("plus", help: "Stage All Changes") { git.stageAll() }
                        }
                        ForEach(git.status.unstaged) { change in
                            changeRow(change, staged: false)
                        }
                    }
                    if git.status.changeCount == 0 {
                        Text("No changes detected.")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var commitBox: some View {
        VStack(spacing: 8) {
            TextField("Message (⌘Enter to commit)", text: $git.commitMessage, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1...4)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Palette.borderStrong, lineWidth: 1))
                .onSubmit { git.commit() }

            Button(action: { git.commit() }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text(commitTitle).font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(git.canCommit ? AnyShapeStyle(Palette.accentGradient) : AnyShapeStyle(Palette.surfaceHigh))
                )
                .foregroundStyle(git.canCommit ? .white : Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!git.canCommit)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var commitTitle: String {
        let branch = git.status.branch ?? "HEAD"
        return "Commit to \(branch)"
    }

    @ViewBuilder
    private func sectionHeader<Trailing: View>(title: String, count: Int,
                                               @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold)).tracking(0.5)
                .foregroundStyle(Palette.textTertiary)
            trailing()
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(Palette.surfaceHigh))
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private func changeRow(_ change: GitFileChange, staged: Bool) -> some View {
        ChangeRow(change: change, staged: staged,
                  onOpen: { onOpenFile(change.url) },
                  onStage: { git.stage(change) },
                  onUnstage: { git.unstage(change) },
                  onDiscard: { git.discard(change) })
    }

    private func actionIcon(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 18, height: 18)
                .hoverHighlight(cornerRadius: 4)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var notARepository: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text("No Source Control")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
            Text("The open folder is not a Git repository.")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }
}

/// A single change row with hover-revealed stage / unstage / discard actions.
private struct ChangeRow: View {
    let change: GitFileChange
    let staged: Bool
    let onOpen: () -> Void
    let onStage: () -> Void
    let onUnstage: () -> Void
    let onDiscard: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            let icon = FileIconResolver.icon(for: change.name)
            Image(systemName: icon.symbol).font(.system(size: 12)).foregroundStyle(icon.color)
            Text(change.name)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            let dir = (change.path as NSString).deletingLastPathComponent
            if !dir.isEmpty {
                Text(dir)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if hovering {
                if staged {
                    rowAction("minus", help: "Unstage Changes", action: onUnstage)
                } else {
                    rowAction("arrow.uturn.backward", help: "Discard Changes",
                              color: Palette.danger, action: onDiscard)
                    rowAction("plus", help: "Stage Changes", action: onStage)
                }
            }
            Text(change.state.badge)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(badgeColor)
                .frame(width: 14)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .hoverHighlight(cornerRadius: 6)
        .padding(.horizontal, 6)
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
        .onTapGesture(perform: onOpen)
    }

    private func rowAction(_ symbol: String, help: String,
                           color: Color = Palette.textSecondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var badgeColor: Color {
        switch change.state {
        case .modified: return Palette.warning
        case .added, .untracked, .copied: return Palette.success
        case .deleted: return Palette.danger
        case .renamed: return Palette.accent
        case .conflicted: return Palette.danger
        case .ignored, .unknown: return Palette.textTertiary
        }
    }
}
