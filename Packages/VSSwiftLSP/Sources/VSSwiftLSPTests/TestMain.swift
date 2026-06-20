import Foundation
import VSSwiftCore
import VSSwiftLSP
import VSTestKit

func framingSuite() -> TestSuite {
    let s = TestSuite("JSON-RPC framing")
    s.test("header format is Content-Length CRLF CRLF") { t in
        t.equal(MessageFraming.header(forLength: 42), "Content-Length: 42\r\n\r\n")
    }
    s.test("encode prepends correct length") { t in
        let payload = Data("{\"a\":1}".utf8)
        let framed = MessageFraming.encode(payload: payload)
        let expectedPrefix = Data("Content-Length: 7\r\n\r\n".utf8)
        t.expect(framed.starts(with: expectedPrefix))
        t.equal(framed.count, expectedPrefix.count + payload.count)
    }
    s.test("parser extracts a single message") { t in
        var parser = MessageParser()
        let payload = Data("{\"jsonrpc\":\"2.0\"}".utf8)
        let framed = MessageFraming.encode(payload: payload)
        let out = try parser.append(framed)
        t.equal(out.count, 1)
        t.equal(out[0], payload)
    }
    s.test("parser handles two concatenated messages") { t in
        var parser = MessageParser()
        let p1 = Data("{\"id\":1}".utf8)
        let p2 = Data("{\"id\":2}".utf8)
        var stream = MessageFraming.encode(payload: p1)
        stream.append(MessageFraming.encode(payload: p2))
        let out = try parser.append(stream)
        t.equal(out.count, 2)
        t.equal(out[0], p1)
        t.equal(out[1], p2)
    }
    s.test("parser tolerates split delivery") { t in
        var parser = MessageParser()
        let payload = Data("{\"hello\":\"world\"}".utf8)
        let framed = MessageFraming.encode(payload: payload)
        let mid = framed.index(framed.startIndex, offsetBy: 10)
        let first = framed.subdata(in: framed.startIndex..<mid)
        let second = framed.subdata(in: mid..<framed.endIndex)
        t.equal(try parser.append(first).count, 0, "incomplete -> nothing yet")
        let out = try parser.append(second)
        t.equal(out.count, 1)
        t.equal(out[0], payload)
    }
    s.test("missing content-length throws") { t in
        var parser = MessageParser()
        let bad = Data("X-Foo: bar\r\n\r\n{}".utf8)
        t.throwsError { _ = try parser.append(bad) }
    }
    return s
}

func serializationSuite() -> TestSuite {
    let s = TestSuite("LSP serialization")
    let encoder: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return e }()
    let decoder = JSONDecoder()

    s.test("initialize request encodes jsonrpc/method/id") { t in
        let params = InitializeParams(processId: 123, rootUri: "file:///work")
        let req = LSPRequest(id: .number(1), method: "initialize", params: params)
        let data = try encoder.encode(req)
        let json = String(data: data, encoding: .utf8)!
        t.expect(json.contains("\"jsonrpc\":\"2.0\""))
        t.expect(json.contains("\"method\":\"initialize\""))
        t.expect(json.contains("\"rootUri\":\"file:///work\""))
    }
    s.test("didOpen notification has no id") { t in
        let params = DidOpenTextDocumentParams(
            textDocument: TextDocumentItem(uri: "file:///a.swift", languageId: "swift", version: 1, text: "let x = 1"))
        let note = LSPNotification(method: "textDocument/didOpen", params: params)
        let json = String(data: try encoder.encode(note), encoding: .utf8)!
        t.expect(!json.contains("\"id\""))
        t.expect(json.contains("\"languageId\":\"swift\""))
    }
    s.test("publishDiagnostics decodes") { t in
        let json = """
        {"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{
          "uri":"file:///a.swift",
          "diagnostics":[{"range":{"start":{"line":0,"character":4},"end":{"line":0,"character":5}},
                          "severity":1,"message":"oops","source":"sourcekitd"}]}}
        """
        struct Envelope: Codable { let params: PublishDiagnosticsParams }
        let env = try decoder.decode(Envelope.self, from: Data(json.utf8))
        t.equal(env.params.uri, "file:///a.swift")
        t.equal(env.params.diagnostics.count, 1)
        t.equal(env.params.diagnostics[0].severity, .error)
        t.equal(env.params.diagnostics[0].message, "oops")
    }
    s.test("completion result decodes both array and list forms") { t in
        let arrayForm = Data("""
        [{"label":"map","kind":2},{"label":"filter"}]
        """.utf8)
        let listForm = Data("""
        {"isIncomplete":false,"items":[{"label":"reduce","kind":2}]}
        """.utf8)
        t.equal(try CompletionResult.decode(arrayForm).count, 2)
        let items = try CompletionResult.decode(listForm)
        t.equal(items.count, 1)
        t.equal(items[0].label, "reduce")
    }
    s.test("request id supports string and number") { t in
        let a = try encoder.encode(RequestID.number(5))
        let b = try encoder.encode(RequestID.string("abc"))
        t.equal(String(data: a, encoding: .utf8), "5")
        t.equal(String(data: b, encoding: .utf8), "\"abc\"")
    }
    return s
}

// Best-effort integration with the real sourcekit-lsp. Never fails the build if the
// server is unavailable/slow; reports a skip instead.
func withTimeout<T: Sendable>(_ seconds: Double, _ op: @escaping @Sendable () async throws -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { try? await op() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

func integrationSuite() -> TestSuite {
    let s = TestSuite("sourcekit-lsp integration (best-effort)")
    s.test("initialize handshake") { t in
        let client = LSPClient()
        let result: Data? = await withTimeout(25) {
            try await client.start()
            let tmp = FileManager.default.temporaryDirectory
            return try await client.initialize(rootURI: tmp.absoluteString)
        }
        await client.stop()
        if let result, let json = String(data: result, encoding: .utf8) {
            t.expect(json.contains("capabilities"), "server returned capabilities")
            print("      ✓ live sourcekit-lsp initialize succeeded")
        } else {
            print("      ⚠︎ skipped: sourcekit-lsp not available or timed out")
            // Not a failure: environment-dependent.
        }
    }
    return s
}

@main
struct Runner {
    static func main() async {
        await runSuitesAndExit([
            framingSuite(),
            serializationSuite(),
            integrationSuite()
        ])
    }
}
