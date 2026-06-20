import Foundation
import VSSwiftCore

/// JSON-RPC 2.0 request id (LSP allows int or string).
public enum RequestID: Codable, Sendable, Hashable {
    case number(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .number(i) }
        else { self = .string(try c.decode(String.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let i): try c.encode(i)
        case .string(let s): try c.encode(s)
        }
    }
}

/// LSP `Position`: zero-based line and UTF-16 character offset.
public struct LSPPosition: Codable, Sendable, Hashable {
    public var line: Int
    public var character: Int
    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
    public init(_ p: TextPosition) {
        self.line = p.line
        self.character = p.column
    }
}

public struct LSPRange: Codable, Sendable, Hashable {
    public var start: LSPPosition
    public var end: LSPPosition
    public init(start: LSPPosition, end: LSPPosition) {
        self.start = start
        self.end = end
    }
}

// MARK: - Outbound request/notification envelopes

/// A JSON-RPC request with typed params.
public struct LSPRequest<Params: Codable & Sendable>: Codable, Sendable {
    public let jsonrpc: String
    public let id: RequestID
    public let method: String
    public let params: Params
    public init(id: RequestID, method: String, params: Params) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

/// A JSON-RPC notification (no id, no response expected).
public struct LSPNotification<Params: Codable & Sendable>: Codable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: Params
    public init(method: String, params: Params) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

/// Header used to peek at any inbound message and decide how to route it.
public struct InboundHeader: Codable, Sendable {
    public let id: RequestID?
    public let method: String?
}

// MARK: - Lifecycle payloads

public struct ClientCapabilities: Codable, Sendable {
    public struct TextDocumentClientCapabilities: Codable, Sendable {
        public struct CompletionCapabilities: Codable, Sendable {
            public var dynamicRegistration: Bool
            public init(dynamicRegistration: Bool = false) { self.dynamicRegistration = dynamicRegistration }
        }
        public struct PublishDiagnosticsCapabilities: Codable, Sendable {
            public var relatedInformation: Bool
            public init(relatedInformation: Bool = true) { self.relatedInformation = relatedInformation }
        }
        public var completion: CompletionCapabilities
        public var publishDiagnostics: PublishDiagnosticsCapabilities
        public init(completion: CompletionCapabilities = .init(),
                    publishDiagnostics: PublishDiagnosticsCapabilities = .init()) {
            self.completion = completion
            self.publishDiagnostics = publishDiagnostics
        }
    }
    public var textDocument: TextDocumentClientCapabilities
    public init(textDocument: TextDocumentClientCapabilities = .init()) {
        self.textDocument = textDocument
    }
}

public struct InitializeParams: Codable, Sendable {
    public var processId: Int?
    public var rootUri: String?
    public var capabilities: ClientCapabilities
    public var clientInfo: ClientInfo?

    public struct ClientInfo: Codable, Sendable {
        public var name: String
        public var version: String
        public init(name: String, version: String) { self.name = name; self.version = version }
    }

    public init(processId: Int?, rootUri: String?, capabilities: ClientCapabilities = .init(),
                clientInfo: ClientInfo? = .init(name: "VSSwift", version: "1.0")) {
        self.processId = processId
        self.rootUri = rootUri
        self.capabilities = capabilities
        self.clientInfo = clientInfo
    }
}

public struct TextDocumentItem: Codable, Sendable {
    public var uri: String
    public var languageId: String
    public var version: Int
    public var text: String
    public init(uri: String, languageId: String, version: Int, text: String) {
        self.uri = uri
        self.languageId = languageId
        self.version = version
        self.text = text
    }
}

public struct DidOpenTextDocumentParams: Codable, Sendable {
    public var textDocument: TextDocumentItem
    public init(textDocument: TextDocumentItem) { self.textDocument = textDocument }
}

public struct VersionedTextDocumentIdentifier: Codable, Sendable {
    public var uri: String
    public var version: Int
    public init(uri: String, version: Int) { self.uri = uri; self.version = version }
}

public struct TextDocumentContentChangeEvent: Codable, Sendable {
    /// Omitted for full-document sync; present for incremental deltas.
    public var range: LSPRange?
    public var text: String
    public init(range: LSPRange?, text: String) { self.range = range; self.text = text }
}

public struct DidChangeTextDocumentParams: Codable, Sendable {
    public var textDocument: VersionedTextDocumentIdentifier
    public var contentChanges: [TextDocumentContentChangeEvent]
    public init(textDocument: VersionedTextDocumentIdentifier, contentChanges: [TextDocumentContentChangeEvent]) {
        self.textDocument = textDocument
        self.contentChanges = contentChanges
    }
}

public struct TextDocumentIdentifier: Codable, Sendable {
    public var uri: String
    public init(uri: String) { self.uri = uri }
}

public struct CompletionParams: Codable, Sendable {
    public var textDocument: TextDocumentIdentifier
    public var position: LSPPosition
    public init(textDocument: TextDocumentIdentifier, position: LSPPosition) {
        self.textDocument = textDocument
        self.position = position
    }
}

// MARK: - Inbound results

public struct CompletionItem: Codable, Sendable, Hashable {
    public var label: String
    public var kind: Int?
    public var detail: String?
    public var insertText: String?
    public var sortText: String?
    public init(label: String, kind: Int? = nil, detail: String? = nil, insertText: String? = nil, sortText: String? = nil) {
        self.label = label
        self.kind = kind
        self.detail = detail
        self.insertText = insertText
        self.sortText = sortText
    }
}

public struct CompletionList: Codable, Sendable {
    public var isIncomplete: Bool
    public var items: [CompletionItem]
}

/// Decodes a `completion` result which may be a bare array or a `CompletionList`.
public enum CompletionResult {
    public static func decode(_ data: Data) throws -> [CompletionItem] {
        let decoder = JSONDecoder()
        if let list = try? decoder.decode(CompletionList.self, from: data) {
            return list.items
        }
        return (try? decoder.decode([CompletionItem].self, from: data)) ?? []
    }
}

public struct Diagnostic: Codable, Sendable, Hashable {
    public enum Severity: Int, Codable, Sendable { case error = 1, warning, information, hint }
    public var range: LSPRange
    public var severity: Severity?
    public var message: String
    public var source: String?
    public init(range: LSPRange, severity: Severity?, message: String, source: String? = nil) {
        self.range = range
        self.severity = severity
        self.message = message
        self.source = source
    }
}

public struct PublishDiagnosticsParams: Codable, Sendable {
    public var uri: String
    public var diagnostics: [Diagnostic]
}
