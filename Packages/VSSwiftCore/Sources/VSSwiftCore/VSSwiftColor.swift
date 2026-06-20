import Foundation

/// A platform-independent RGBA color (0...1 components) parsed from theme JSON.
public struct VSSwiftColor: Sendable, Hashable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parses a CSS-style hex string: `#RGB`, `#RGBA`, `#RRGGBB`, or `#RRGGBBAA`.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.allSatisfy({ $0.isHexDigit }) else { return nil }

        func component(_ substring: Substring) -> Double? {
            guard let v = Int(substring, radix: 16) else { return nil }
            return Double(v) / 255.0
        }

        let chars = Array(s)
        switch chars.count {
        case 3, 4:
            // Expand shorthand: each nibble duplicated.
            var expanded = ""
            for c in chars { expanded.append(c); expanded.append(c) }
            self.init(hex: "#" + expanded)
            return
        case 6, 8:
            guard
                let r = component(s.prefix(2)),
                let g = component(s.dropFirst(2).prefix(2)),
                let b = component(s.dropFirst(4).prefix(2))
            else { return nil }
            let a: Double = chars.count == 8 ? (component(s.dropFirst(6).prefix(2)) ?? 1.0) : 1.0
            self.init(red: r, green: g, blue: b, alpha: a)
        default:
            return nil
        }
    }

    /// Serializes back to `#RRGGBBAA` (alpha omitted when opaque -> `#RRGGBB`).
    public var hexString: String {
        func byte(_ v: Double) -> Int { Int((v * 255.0).rounded()).clamped(to: 0...255) }
        let r = byte(red), g = byte(green), b = byte(blue), a = byte(alpha)
        if a == 255 {
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}

extension Comparable {
    public func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
