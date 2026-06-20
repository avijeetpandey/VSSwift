import Foundation

/// A normalized semantic token: a text range tagged with a TextMate-style scope.
public struct VSSwiftToken: Sendable, Hashable, Codable {
    public var range: VSSwiftRange
    public var scope: String

    public init(range: VSSwiftRange, scope: String) {
        self.range = range
        self.scope = scope
    }
}

/// A versioned batch of tokens for a document. The `version` is used to discard
/// stale results produced from an older buffer snapshot (generation-token pattern).
public struct TokenBatch: Sendable {
    public var documentVersion: Int
    public var tokens: [VSSwiftToken]

    public init(documentVersion: Int, tokens: [VSSwiftToken]) {
        self.documentVersion = documentVersion
        self.tokens = tokens
    }
}
