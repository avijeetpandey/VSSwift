import Foundation

/// Font style flags parseable from a TextMate/VSCode `fontStyle` string ("bold italic underline").
public struct FontStyle: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let bold = FontStyle(rawValue: 1 << 0)
    public static let italic = FontStyle(rawValue: 1 << 1)
    public static let underline = FontStyle(rawValue: 1 << 2)
    public static let strikethrough = FontStyle(rawValue: 1 << 3)

    public init(parsing string: String) {
        var style: FontStyle = []
        for token in string.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }) {
            switch token {
            case "bold": style.insert(.bold)
            case "italic": style.insert(.italic)
            case "underline": style.insert(.underline)
            case "strikethrough": style.insert(.strikethrough)
            default: break
            }
        }
        self = style
    }
}

/// The visual styling applied to a single semantic token scope.
public struct TokenStyle: Sendable, Hashable, Codable {
    public var foreground: VSSwiftColor?
    public var background: VSSwiftColor?
    public var fontStyle: FontStyle

    public init(foreground: VSSwiftColor? = nil, background: VSSwiftColor? = nil, fontStyle: FontStyle = []) {
        self.foreground = foreground
        self.background = background
        self.fontStyle = fontStyle
    }
}

/// A fully-resolved theme: workbench UI colors keyed by VSCode color id, plus token scope rules.
public struct Theme: Sendable, Hashable {
    public var name: String
    public var type: Kind
    /// Workbench colors, e.g. "editor.background" -> color.
    public var colors: [String: VSSwiftColor]
    /// Ordered token rules; later, more specific scopes win during resolution.
    public var tokenRules: [TokenRule]

    public enum Kind: String, Sendable, Codable {
        case light, dark, highContrast = "hc"
    }

    public struct TokenRule: Sendable, Hashable, Codable {
        public var scopes: [String]
        public var style: TokenStyle
        public init(scopes: [String], style: TokenStyle) {
            self.scopes = scopes
            self.style = style
        }
    }

    public init(name: String, type: Kind, colors: [String: VSSwiftColor], tokenRules: [TokenRule]) {
        self.name = name
        self.type = type
        self.colors = colors
        self.tokenRules = tokenRules
    }

    /// Looks up a workbench color by id, falling back to `fallback`.
    public func color(_ id: String, fallback: VSSwiftColor) -> VSSwiftColor {
        colors[id] ?? fallback
    }

    /// Resolves the style for a TextMate-style scope, e.g. "keyword.control.swift".
    /// Uses longest-prefix scope matching, the standard TextMate resolution rule.
    public func style(forScope scope: String) -> TokenStyle {
        var best: (matchLength: Int, style: TokenStyle)? = nil
        for rule in tokenRules {
            for ruleScope in rule.scopes {
                if scope == ruleScope || scope.hasPrefix(ruleScope + ".") {
                    let len = ruleScope.count
                    if best == nil || len > best!.matchLength {
                        best = (len, rule.style)
                    }
                }
            }
        }
        return best?.style ?? TokenStyle()
    }
}
