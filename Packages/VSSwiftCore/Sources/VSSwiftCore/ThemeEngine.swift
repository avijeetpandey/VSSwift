import Foundation
import Combine

/// Holds the active theme and the catalog of available themes.
///
/// `ObservableObject` so SwiftUI chrome can observe it; also exposes a plain
/// snapshot the AppKit canvas reads for token attributes (single source of truth).
@MainActor
public final class ThemeEngine: ObservableObject {
    @Published public private(set) var current: Theme
    @Published public private(set) var available: [Theme]

    public init(current: Theme = BuiltinThemes.darkPlus,
                available: [Theme] = [BuiltinThemes.darkPlus, BuiltinThemes.lightPlus]) {
        self.current = current
        self.available = available
    }

    public func select(named name: String) {
        if let match = available.first(where: { $0.name == name }) {
            current = match
        }
    }

    public func select(_ theme: Theme) {
        current = theme
        if !available.contains(where: { $0.name == theme.name }) {
            available.append(theme)
        }
    }

    /// Loads and registers a theme from VSCode-compatible JSON, making it current.
    @discardableResult
    public func loadTheme(fromJSON data: Data) throws -> Theme {
        let theme = try ThemeParser().parse(data: data)
        select(theme)
        return theme
    }
}
