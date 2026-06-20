import Foundation
import VSSwiftCore

/// Errors from the language server client.
public enum LSPError: Error, Sendable {
    case notRunning
    case launchFailed(String)
    case decodeFailed
    case serverError(code: Int, message: String)
    case timeout
}

/// An actor-isolated JSON-RPC 2.0 client for a language server subprocess
/// (e.g. `xcrun sourcekit-lsp`). All protocol state is confined to the actor, so
/// the main thread never blocks on a pipe read or a pending response.
public actor LSPClient {
    private let executableURL: URL
    private let arguments: [String]

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var parser = MessageParser()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]

    private var diagnosticsContinuation: AsyncStream<PublishDiagnosticsParams>.Continuation?
    public let diagnostics: AsyncStream<PublishDiagnosticsParams>

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()
    private let decoder = JSONDecoder()

    public init(executable: URL = URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: [String] = ["sourcekit-lsp"]) {
        self.executableURL = executable
        self.arguments = arguments
        var cont: AsyncStream<PublishDiagnosticsParams>.Continuation!
        self.diagnostics = AsyncStream { cont = $0 }
        self.diagnosticsContinuation = cont
    }

    public var isRunning: Bool { process?.isRunning ?? false }

    // MARK: - Lifecycle

    public func start() throws {
        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = arguments

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.ingest(data) }
        }

        do {
            try proc.run()
        } catch {
            throw LSPError.launchFailed(error.localizedDescription)
        }

        self.process = proc
        self.stdinHandle = stdin.fileHandleForWriting
    }

    public func stop() {
        process?.terminate()
        process = nil
        stdinHandle = nil
        for (_, cont) in pending { cont.resume(throwing: LSPError.notRunning) }
        pending.removeAll()
        diagnosticsContinuation?.finish()
    }

    // MARK: - Sending

    private func write(_ payload: Data) throws {
        guard let handle = stdinHandle else { throw LSPError.notRunning }
        try handle.write(contentsOf: MessageFraming.encode(payload: payload))
    }

    /// Sends a request and awaits the typed result.
    @discardableResult
    public func sendRequest<P: Codable & Sendable, R: Decodable>(
        method: String, params: P, resultType: R.Type
    ) async throws -> R {
        let data = try await sendRequestRaw(method: method, params: params)
        do {
            // The result is nested under "result"; extract then decode.
            let envelope = try decoder.decode(ResultEnvelope.self, from: data)
            guard let resultData = envelope.resultData else { throw LSPError.decodeFailed }
            return try decoder.decode(R.self, from: resultData)
        } catch {
            throw LSPError.decodeFailed
        }
    }

    /// Sends a request and returns the raw response payload (the full JSON object).
    public func sendRequestRaw<P: Codable & Sendable>(method: String, params: P) async throws -> Data {
        nextID += 1
        let id = nextID
        let request = LSPRequest(id: .number(id), method: method, params: params)
        let payload = try encoder.encode(request)
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try write(payload) }
            catch {
                pending[id] = nil
                continuation.resume(throwing: error)
            }
        }
    }

    public func sendNotification<P: Codable & Sendable>(method: String, params: P) throws {
        let notification = LSPNotification(method: method, params: params)
        try write(try encoder.encode(notification))
    }

    // MARK: - Receiving

    private func ingest(_ data: Data) {
        let payloads: [Data]
        do { payloads = try parser.append(data) }
        catch { return }
        for payload in payloads { route(payload) }
    }

    private func route(_ payload: Data) {
        guard let header = try? decoder.decode(InboundHeader.self, from: payload) else { return }

        if let method = header.method {
            // Notification (or server->client request, which we currently ignore).
            if method == "textDocument/publishDiagnostics",
               let env = try? decoder.decode(NotificationEnvelope<PublishDiagnosticsParams>.self, from: payload) {
                diagnosticsContinuation?.yield(env.params)
            }
            return
        }

        if let id = header.id, case .number(let n) = id, let continuation = pending[n] {
            pending[n] = nil
            // Surface server errors as thrown errors.
            if let errEnv = try? decoder.decode(ErrorEnvelope.self, from: payload), let err = errEnv.error {
                continuation.resume(throwing: LSPError.serverError(code: err.code, message: err.message))
            } else {
                continuation.resume(returning: payload)
            }
        }
    }

    // MARK: - High-level convenience

    @discardableResult
    public func initialize(rootURI: String?) async throws -> Data {
        let params = InitializeParams(processId: Int(ProcessInfo.processInfo.processIdentifier), rootUri: rootURI)
        let result = try await sendRequestRaw(method: "initialize", params: params)
        try sendNotification(method: "initialized", params: EmptyParams())
        return result
    }

    public func didOpen(uri: String, languageId: String = "swift", version: Int = 1, text: String) throws {
        let params = DidOpenTextDocumentParams(
            textDocument: TextDocumentItem(uri: uri, languageId: languageId, version: version, text: text))
        try sendNotification(method: "textDocument/didOpen", params: params)
    }

    public func didChange(uri: String, version: Int, fullText: String) throws {
        let params = DidChangeTextDocumentParams(
            textDocument: VersionedTextDocumentIdentifier(uri: uri, version: version),
            contentChanges: [TextDocumentContentChangeEvent(range: nil, text: fullText)])
        try sendNotification(method: "textDocument/didChange", params: params)
    }

    public func didChange(uri: String, version: Int, delta: TextDocumentContentChangeEvent) throws {
        let params = DidChangeTextDocumentParams(
            textDocument: VersionedTextDocumentIdentifier(uri: uri, version: version),
            contentChanges: [delta])
        try sendNotification(method: "textDocument/didChange", params: params)
    }

    public func completion(uri: String, position: LSPPosition) async throws -> [CompletionItem] {
        let params = CompletionParams(textDocument: TextDocumentIdentifier(uri: uri), position: position)
        let raw = try await sendRequestRaw(method: "textDocument/completion", params: params)
        let envelope = try decoder.decode(ResultEnvelope.self, from: raw)
        guard let resultData = envelope.resultData else { return [] }
        return try CompletionResult.decode(resultData)
    }
}

// MARK: - Decoding envelopes

struct EmptyParams: Codable, Sendable {}

private struct NotificationEnvelope<P: Codable & Sendable>: Codable, Sendable {
    let params: P
}

/// Decodes only the `result` field, preserving its raw JSON for later typed decoding.
private struct ResultEnvelope: Decodable {
    let resultData: Data?
    private enum CodingKeys: String, CodingKey { case result }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.result) {
            let value = try container.decode(JSONValue.self, forKey: .result)
            resultData = try JSONEncoder().encode(value)
        } else {
            resultData = nil
        }
    }
}

private struct ErrorEnvelope: Decodable {
    struct ErrorObject: Decodable { let code: Int; let message: String }
    let error: ErrorObject?
}
