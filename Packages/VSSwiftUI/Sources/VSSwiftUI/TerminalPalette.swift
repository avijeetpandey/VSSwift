import SwiftUI
import VSSwiftCore

/// Maps the emulator's UI-agnostic `TerminalColor` values onto concrete SwiftUI colors,
/// using a palette tuned to match VSSwift's violet/pink dark theme.
enum TerminalPalette {

    /// The 16 standard ANSI colors (0–7 normal, 8–15 bright).
    static let ansi: [Color] = [
        Color(hex: 0x2A2C3A),  // 0  black (slightly lifted so it stays visible on bg)
        Color(hex: 0xFF5C72),  // 1  red
        Color(hex: 0x3DD68C),  // 2  green
        Color(hex: 0xFFB454),  // 3  yellow
        Color(hex: 0x4CA6FF),  // 4  blue
        Color(hex: 0xC792EA),  // 5  magenta
        Color(hex: 0x56D4DD),  // 6  cyan
        Color(hex: 0xE8E8F0),  // 7  white
        Color(hex: 0x66677E),  // 8  bright black (grey)
        Color(hex: 0xFF7A8C),  // 9  bright red
        Color(hex: 0x6BE5A8),  // 10 bright green
        Color(hex: 0xFFC978),  // 11 bright yellow
        Color(hex: 0x78BBFF),  // 12 bright blue
        Color(hex: 0xDDB0F6),  // 13 bright magenta
        Color(hex: 0x7FE4EB),  // 14 bright cyan
        Color(hex: 0xFFFFFF),  // 15 bright white
    ]

    static func color(for terminalColor: TerminalColor) -> Color {
        switch terminalColor {
        case .ansi(let index):
            return ansi[min(max(index, 0), ansi.count - 1)]
        case .rgb(let r, let g, let b):
            return Color(
                .sRGB,
                red: Double(r) / 255.0,
                green: Double(g) / 255.0,
                blue: Double(b) / 255.0)
        case .palette(let index):
            return paletteColor(index)
        }
    }

    /// Resolves an xterm 256-color index into an sRGB color.
    private static func paletteColor(_ index: Int) -> Color {
        let i = min(max(index, 0), 255)
        if i < 16 { return ansi[i] }
        if i >= 232 {
            // 24-step grayscale ramp.
            let level = Double(8 + (i - 232) * 10) / 255.0
            return Color(.sRGB, red: level, green: level, blue: level, opacity: 1)
        }
        // 6×6×6 color cube.
        let cube = i - 16
        let steps = [0, 95, 135, 175, 215, 255]
        let r = steps[(cube / 36) % 6]
        let g = steps[(cube / 6) % 6]
        let b = steps[cube % 6]
        return Color(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0)
    }
}

extension TerminalStyle {
    /// The resolved foreground color, honoring inverse video and dim attributes.
    func resolvedForeground(default base: Color) -> Color {
        if inverse {
            return background.map(TerminalPalette.color(for:)) ?? Palette.bg
        }
        let color = foreground.map(TerminalPalette.color(for:)) ?? base
        return dim ? color.opacity(0.65) : color
    }

    /// The resolved background color, honoring inverse video. Returns nil when transparent.
    func resolvedBackground() -> Color? {
        if inverse {
            return foreground.map(TerminalPalette.color(for:)) ?? Palette.textPrimary
        }
        return background.map(TerminalPalette.color(for:))
    }
}
