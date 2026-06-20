import SwiftUI

/// Centralized modern design tokens for the VSSwift workbench chrome. Inspired by the
/// app icon's charcoal→violet palette with an orange→pink→violet accent gradient.
public enum Palette {
    public static let bg            = Color(hex: 0x14151C)
    public static let bgElevated    = Color(hex: 0x1B1C26)
    public static let surface       = Color(hex: 0x1E2030)
    public static let surfaceHigh   = Color(hex: 0x262839)
    public static let sidebar       = Color(hex: 0x181922)
    public static let activityBar   = Color(hex: 0x101017)
    public static let titlebar      = Color(hex: 0x121219)

    public static let border        = Color.white.opacity(0.055)
    public static let borderStrong  = Color.white.opacity(0.10)

    public static let textPrimary   = Color(hex: 0xE8E8F0)
    public static let textSecondary = Color(hex: 0x9A9BB2)
    public static let textTertiary  = Color(hex: 0x66677E)

    public static let accent        = Color(hex: 0x7C4DFF)
    public static let accentPink    = Color(hex: 0xFF3CAC)
    public static let accentOrange  = Color(hex: 0xFF8A4C)
    public static let accentSoft    = Color(hex: 0x7C4DFF).opacity(0.18)

    public static let danger        = Color(hex: 0xFF5C72)
    public static let warning       = Color(hex: 0xFFB454)
    public static let success       = Color(hex: 0x3DD68C)
    public static let info          = Color(hex: 0x4CA6FF)

    public static let accentGradient = LinearGradient(
        colors: [accentOrange, accentPink, accent],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    public static let accentBarGradient = LinearGradient(
        colors: [accentPink, accent],
        startPoint: .top, endPoint: .bottom)
}

public extension Color {
    /// Hex literal initializer, e.g. `Color(hex: 0x7C4DFF)`.
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

/// Standard animation curves used across the workbench for a consistent feel.
public enum Motion {
    public static let snappy   = Animation.spring(response: 0.32, dampingFraction: 0.82)
    public static let smooth   = Animation.easeInOut(duration: 0.22)
    public static let quick    = Animation.easeOut(duration: 0.14)
    public static let sidebar  = Animation.spring(response: 0.38, dampingFraction: 0.86)
}

/// Maps file names / directories to a colored SF Symbol for the explorer, giving the
/// tree a modern icon-pack feel without bundling an icon font.
public enum FileIconResolver {
    public static func folder(expanded: Bool) -> (symbol: String, color: Color) {
        (expanded ? "folder.fill" : "folder.fill", Palette.accent.opacity(0.85))
    }

    public static func icon(for fileName: String) -> (symbol: String, color: Color) {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "swift":               return ("swift", Palette.accentOrange)
        case "json":                return ("curlybraces", Palette.warning)
        case "md", "markdown":      return ("text.alignleft", Palette.info)
        case "txt", "log":          return ("doc.text", Palette.textSecondary)
        case "yml", "yaml", "toml": return ("slider.horizontal.3", Palette.success)
        case "sh", "bash", "zsh":   return ("terminal", Palette.success)
        case "png", "jpg", "jpeg", "gif", "svg", "icns":
            return ("photo", Palette.accentPink)
        case "js", "ts", "jsx", "tsx":
            return ("chevron.left.forwardslash.chevron.right", Palette.warning)
        case "html", "xml":         return ("chevron.left.slash.chevron.right", Palette.accentOrange)
        case "css", "scss":         return ("paintbrush", Palette.info)
        case "lock", "resolved":    return ("lock.fill", Palette.textTertiary)
        case "h", "hpp", "c", "cpp", "m", "mm":
            return ("c.square", Palette.info)
        case "py":                  return ("ladybug", Palette.warning)
        default:
            if fileName.lowercased().hasPrefix("package") { return ("shippingbox.fill", Palette.accentOrange) }
            if fileName.lowercased() == "readme.md" { return ("book.fill", Palette.info) }
            return ("doc", Palette.textSecondary)
        }
    }
}

/// A reusable hover-highlight container used by list rows and toolbar buttons.
public struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    let hoverColor: Color
    let isActive: Bool
    let activeColor: Color
    @State private var hovering = false

    public init(cornerRadius: CGFloat = 6,
                hoverColor: Color = Color.white.opacity(0.05),
                isActive: Bool = false,
                activeColor: Color = Palette.accentSoft) {
        self.cornerRadius = cornerRadius
        self.hoverColor = hoverColor
        self.isActive = isActive
        self.activeColor = activeColor
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isActive ? activeColor : (hovering ? hoverColor : Color.clear))
            )
            .contentShape(Rectangle())
            .onHover { h in
                withAnimation(Motion.quick) { hovering = h }
            }
    }
}

public extension View {
    func hoverHighlight(cornerRadius: CGFloat = 6,
                        hoverColor: Color = Color.white.opacity(0.05),
                        isActive: Bool = false,
                        activeColor: Color = Palette.accentSoft) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, hoverColor: hoverColor,
                                isActive: isActive, activeColor: activeColor))
    }
}
