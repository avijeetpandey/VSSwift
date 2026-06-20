import Foundation
import Combine
import VSSwiftCore
import VSSwiftEngine
import VSSwiftSyntax
import VSSwiftLSP

/// Drives a single editor: owns the text, multi-cursor selection, semantic tokens,
/// and the debounced background re-parse. Lives on the `MainActor`; heavy work is
/// delegated to the ``SwiftTokenParser`` actor and (optionally) the ``LSPClient``.
@MainActor
public final class EditorViewModel: ObservableObject {
    @Published public private(set) var text: String
    @Published public private(set) var tokens: [VSSwiftToken] = []
    @Published public private(set) var diagnostics: [Diagnostic] = []
    @Published public var selection: SelectionManager = SelectionManager()
    @Published public var completionItems: [CompletionItem] = []
    @Published public var isCompletionVisible: Bool = false

    public let fileURL: URL?
    public let languageID: String

    private var version: Int = 0
    private var latestAppliedVersion: Int = -1
    private let parser = SwiftTokenParser()
    private var reparseTask: Task<Void, Never>?
    private let debounceNanos: UInt64

    public init(text: String = "", fileURL: URL? = nil, languageID: String = "swift",
                debounceMilliseconds: UInt64 = 20) {
        self.text = text
        self.fileURL = fileURL
        self.languageID = languageID
        self.debounceNanos = debounceMilliseconds * 1_000_000
        scheduleReparse()
    }

    /// Replaces the full text (e.g., from the editor canvas) and triggers a re-parse.
    public func updateText(_ newText: String) {
        text = newText
        version += 1
        scheduleReparse()
    }

    /// Debounced background re-parse. Stale results (older version) are discarded.
    public func scheduleReparse() {
        guard languageID == "swift" else { return }
        let snapshotText = text
        let snapshotVersion = version
        reparseTask?.cancel()
        reparseTask = Task { [weak self, parser, debounceNanos] in
            try? await Task.sleep(nanoseconds: debounceNanos)
            if Task.isCancelled { return }
            let batch = await parser.parse(snapshotText, version: snapshotVersion)
            await MainActor.run {
                guard let self else { return }
                // Generation-token guard: ignore results from an outdated snapshot.
                if batch.documentVersion >= self.latestAppliedVersion {
                    self.latestAppliedVersion = batch.documentVersion
                    self.tokens = batch.tokens
                }
            }
        }
    }

    public func applyDiagnostics(_ diags: [Diagnostic]) {
        diagnostics = diags
    }

    public func showCompletions(_ items: [CompletionItem]) {
        completionItems = items
        isCompletionVisible = !items.isEmpty
    }

    public func dismissCompletions() {
        isCompletionVisible = false
        completionItems = []
    }
}
