import SwiftUI
import AppKit
import VSSwiftCore

public extension Color {
    /// Bridges a parsed theme color into SwiftUI.
    init(_ c: VSSwiftColor) {
        self = Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }
}

public extension NSColor {
    /// Bridges a parsed theme color into AppKit for text rendering.
    convenience init(_ c: VSSwiftColor) {
        self.init(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
}

public extension Theme {
    func swiftUIColor(_ id: String, fallback: VSSwiftColor) -> Color {
        Color(color(id, fallback: fallback))
    }
    func nsColor(_ id: String, fallback: VSSwiftColor) -> NSColor {
        NSColor(color(id, fallback: fallback))
    }
}

public extension FontStyle {
    /// Applies bold/italic traits to a base font for token rendering.
    func apply(to font: NSFont) -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if contains(.bold) { traits.insert(.bold) }
        if contains(.italic) { traits.insert(.italic) }
        guard !traits.isEmpty else { return font }
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }
}
