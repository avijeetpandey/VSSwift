import Foundation
import VSSwiftCore
import SwiftSyntax
import SwiftParser

/// Walks a Swift syntax tree and maps nodes/tokens to normalized ``VSSwiftToken``
/// values carrying TextMate-style scopes that the theme engine can color.
final class TokenizingVisitor: SyntaxVisitor {
    private let converter: UTF8PositionConverter
    private(set) var tokens: [VSSwiftToken] = []
    private var overrides: [SyntaxIdentifier: String] = [:]

    private static let controlKeywords: Set<String> = [
        "if", "else", "for", "while", "repeat", "switch", "case", "default",
        "break", "continue", "return", "guard", "defer", "do", "catch", "throw",
        "throws", "rethrows", "try", "fallthrough", "where", "in", "async", "await", "yield"
    ]

    init(source: String, converter: UTF8PositionConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    private func record(_ token: TokenSyntax, _ scope: String) {
        overrides[token.id] = scope
    }

    private func emit(byteStart: Int, byteEnd: Int, scope: String) {
        guard byteEnd > byteStart else { return }
        let start = converter.position(utf8Offset: byteStart)
        let end = converter.position(utf8Offset: byteEnd)
        tokens.append(VSSwiftToken(range: VSSwiftRange(start: start, end: end), scope: scope))
    }

    // MARK: - Declarations (assign richer scopes to their name tokens)

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name, "entity.name.type"); return .visitChildren
    }
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name, "entity.name.type"); return .visitChildren
    }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name, "entity.name.type"); return .visitChildren
    }
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name, "entity.name.type"); return .visitChildren
    }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name, "entity.name.type"); return .visitChildren
    }
    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name, "entity.name.type"); return .visitChildren
    }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name, "entity.name.function"); return .visitChildren
    }
    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        record(node.firstName, "variable.parameter"); return .visitChildren
    }
    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        record(node.name, "entity.name.type"); return .visitChildren
    }
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let ref = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            record(ref.baseName, "entity.name.function")
        } else if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            record(member.declName.baseName, "entity.name.function")
        }
        return .visitChildren
    }

    // MARK: - Token-level classification + comments

    override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
        emitComments(in: token)

        let trimmedStart = token.positionAfterSkippingLeadingTrivia.utf8Offset
        let trimmedEnd = trimmedStart + token.trimmedLength.utf8Length

        if let scope = overrides[token.id] {
            emit(byteStart: trimmedStart, byteEnd: trimmedEnd, scope: scope)
            return .skipChildren
        }

        let scope: String?
        switch token.tokenKind {
        case .keyword:
            scope = Self.controlKeywords.contains(token.text) ? "keyword.control" : "keyword"
        case .integerLiteral, .floatLiteral:
            scope = "constant.numeric"
        case .stringQuote, .multilineStringQuote, .stringSegment,
             .rawStringPoundDelimiter, .singleQuote:
            scope = "string"
        case .regexLiteralPattern, .regexSlash:
            scope = "string.regexp"
        default:
            scope = nil
        }
        if let scope {
            emit(byteStart: trimmedStart, byteEnd: trimmedEnd, scope: scope)
        }
        return .skipChildren
    }

    private func emitComments(in token: TokenSyntax) {
        var offset = token.position.utf8Offset
        for piece in token.leadingTrivia {
            let len = piece.sourceLength.utf8Length
            if isComment(piece) { emit(byteStart: offset, byteEnd: offset + len, scope: "comment") }
            offset += len
        }
        // Trailing trivia begins right after the trimmed token text.
        offset = token.positionAfterSkippingLeadingTrivia.utf8Offset + token.trimmedLength.utf8Length
        for piece in token.trailingTrivia {
            let len = piece.sourceLength.utf8Length
            if isComment(piece) { emit(byteStart: offset, byteEnd: offset + len, scope: "comment") }
            offset += len
        }
    }

    private func isComment(_ piece: TriviaPiece) -> Bool {
        switch piece {
        case .lineComment, .blockComment, .docLineComment, .docBlockComment: return true
        default: return false
        }
    }
}

/// Actor-isolated semantic tokenizer. Parsing happens off the main thread; results
/// are tagged with a document version so stale batches can be discarded by the UI.
public actor SwiftTokenParser {
    public init() {}

    /// Parses `text` and returns its semantic tokens, sorted by start position.
    public func parse(_ text: String, version: Int) -> TokenBatch {
        let tree = Parser.parse(source: text)
        let converter = UTF8PositionConverter(source: text)
        let visitor = TokenizingVisitor(source: text, converter: converter)
        visitor.walk(tree)
        let sorted = visitor.tokens.sorted { $0.range.start < $1.range.start }
        return TokenBatch(documentVersion: version, tokens: sorted)
    }
}
