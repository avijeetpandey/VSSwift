import Foundation

/// Encodes and decodes the LSP base protocol framing:
/// `Content-Length: <N>\r\n\r\n<json-bytes>`.
public enum MessageFraming {
    public static let headerTerminator = Data("\r\n\r\n".utf8)

    /// Wraps a JSON payload in a Content-Length framed message.
    public static func encode(payload: Data) -> Data {
        var data = Data("Content-Length: \(payload.count)\r\n\r\n".utf8)
        data.append(payload)
        return data
    }

    /// The header string for a payload of `length` bytes (used in tests/diagnostics).
    public static func header(forLength length: Int) -> String {
        "Content-Length: \(length)\r\n\r\n"
    }
}

/// Errors raised while parsing the LSP wire protocol.
public enum FramingError: Error, Equatable, Sendable {
    case malformedHeader
    case missingContentLength
}

/// Incrementally parses a byte stream into complete JSON-RPC payloads, tolerating
/// messages that arrive split across multiple reads.
public struct MessageParser: Sendable {
    private var buffer = Data()

    public init() {}

    /// Appends newly-read bytes and returns any complete payloads now available.
    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var payloads: [Data] = []
        while let payload = try extractOne() {
            payloads.append(payload)
        }
        return payloads
    }

    private mutating func extractOne() throws -> Data? {
        guard let headerRange = buffer.range(of: MessageFraming.headerTerminator) else {
            return nil // header not complete yet
        }
        let headerData = buffer.subdata(in: buffer.startIndex..<headerRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw FramingError.malformedHeader
        }

        var contentLength: Int?
        for line in headerString.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0].lowercased() == "content-length" {
                contentLength = Int(parts[1])
            }
        }
        guard let length = contentLength else { throw FramingError.missingContentLength }

        let bodyStart = headerRange.upperBound
        let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
        guard available >= length else { return nil } // body not fully arrived

        let bodyEnd = buffer.index(bodyStart, offsetBy: length)
        let payload = buffer.subdata(in: bodyStart..<bodyEnd)
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)
        return payload
    }
}
