import Foundation

/// Errors thrown while parsing a VSCode-compatible JSON theme.
public enum ThemeParseError: Error, Equatable, Sendable {
    case invalidJSON
    case missingName
}

/// Parses VSCode `.json` color themes into the resolved ``Theme`` model.
///
/// Supports the standard VSCode theme schema:
/// ```json
/// {
///   "name": "My Theme",
///   "type": "dark",
///   "colors": { "editor.background": "#1E1E1E" },
///   "tokenColors": [
///     { "scope": "keyword", "settings": { "foreground": "#C586C0", "fontStyle": "bold" } }
///   ]
/// }
/// ```
/// The `scope` field may be a single string or an array of strings.
public struct ThemeParser: Sendable {
    public init() {}

    public func parse(data: Data) throws -> Theme {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ThemeParseError.invalidJSON
        }
        return try parse(object: root)
    }

    public func parse(jsonString: String) throws -> Theme {
        guard let data = jsonString.data(using: .utf8) else { throw ThemeParseError.invalidJSON }
        return try parse(data: data)
    }

    public func parse(object root: [String: Any]) throws -> Theme {
        let name = (root["name"] as? String) ?? "Untitled"
        let typeRaw = (root["type"] as? String) ?? "dark"
        let type = Theme.Kind(rawValue: typeRaw) ?? .dark

        var colors: [String: VSSwiftColor] = [:]
        if let rawColors = root["colors"] as? [String: Any] {
            for (key, value) in rawColors {
                if let hex = value as? String, let color = VSSwiftColor(hex: hex) {
                    colors[key] = color
                }
            }
        }

        var rules: [Theme.TokenRule] = []
        if let tokenColors = root["tokenColors"] as? [[String: Any]] {
            for entry in tokenColors {
                let scopes = Self.normalizeScopes(entry["scope"])
                guard !scopes.isEmpty else { continue }
                guard let settings = entry["settings"] as? [String: Any] else { continue }

                let fg = (settings["foreground"] as? String).flatMap { VSSwiftColor(hex: $0) }
                let bg = (settings["background"] as? String).flatMap { VSSwiftColor(hex: $0) }
                let fontStyle = (settings["fontStyle"] as? String).map { FontStyle(parsing: $0) } ?? []
                rules.append(.init(scopes: scopes, style: TokenStyle(foreground: fg, background: bg, fontStyle: fontStyle)))
            }
        }

        return Theme(name: name, type: type, colors: colors, tokenRules: rules)
    }

    private static func normalizeScopes(_ raw: Any?) -> [String] {
        if let s = raw as? String {
            // VSCode allows a comma-separated scope string.
            return s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if let arr = raw as? [String] {
            return arr.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return []
    }
}
