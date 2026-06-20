import Foundation

/// User-facing editor configuration, mirroring a subset of VSCode's `settings.json`.
public struct EditorConfiguration: Sendable, Hashable, Codable {
    public var fontSize: Double
    public var fontName: String
    public var lineHeightMultiple: Double
    public var tabSize: Int
    public var insertSpaces: Bool
    public var wordWrap: Bool
    public var showMinimap: Bool
    public var showLineNumbers: Bool
    public var multiCursorModifier: MultiCursorModifier
    public var themeName: String

    public enum MultiCursorModifier: String, Sendable, Codable, CaseIterable {
        case option   // Option+Click adds a cursor (VSCode default on macOS)
        case command  // Cmd+Click adds a cursor
    }

    public init(
        fontSize: Double = 13,
        fontName: String = "SF Mono",
        lineHeightMultiple: Double = 1.5,
        tabSize: Int = 4,
        insertSpaces: Bool = true,
        wordWrap: Bool = false,
        showMinimap: Bool = true,
        showLineNumbers: Bool = true,
        multiCursorModifier: MultiCursorModifier = .option,
        themeName: String = "Dark+"
    ) {
        self.fontSize = fontSize
        self.fontName = fontName
        self.lineHeightMultiple = lineHeightMultiple
        self.tabSize = tabSize
        self.insertSpaces = insertSpaces
        self.wordWrap = wordWrap
        self.showMinimap = showMinimap
        self.showLineNumbers = showLineNumbers
        self.multiCursorModifier = multiCursorModifier
        self.themeName = themeName
    }

    public static let `default` = EditorConfiguration()

    /// The whitespace inserted for one indentation level.
    public var indentUnit: String {
        insertSpaces ? String(repeating: " ", count: tabSize) : "\t"
    }
}

/// Loads/saves ``EditorConfiguration`` as JSON.
public struct ConfigurationStore: Sendable {
    public init() {}

    public func decode(from data: Data) throws -> EditorConfiguration {
        try JSONDecoder().decode(EditorConfiguration.self, from: data)
    }

    public func encode(_ config: EditorConfiguration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }
}
