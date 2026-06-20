import Foundation
import VSSwiftCore

/// Computes minimap geometry: a 1:N scaled-down representation of the document with
/// a draggable viewport slider, mirroring VSCode's minimap behavior.
public struct MinimapMetrics: Sendable {
    public var lineCount: Int
    public var lineHeight: Double      // editor line height in points
    public var minimapScale: Double    // e.g. 0.1 for 1:10
    public var viewportHeight: Double  // visible editor height in points
    public var minimapHeight: Double   // available minimap strip height in points

    public init(lineCount: Int, lineHeight: Double, minimapScale: Double = 0.1,
                viewportHeight: Double, minimapHeight: Double) {
        self.lineCount = lineCount
        self.lineHeight = lineHeight
        self.minimapScale = minimapScale
        self.viewportHeight = viewportHeight
        self.minimapHeight = minimapHeight
    }

    /// Height of one line as drawn in the minimap.
    public var minimapLineHeight: Double { lineHeight * minimapScale }

    /// Total document height in editor points.
    public var documentHeight: Double { Double(lineCount) * lineHeight }

    /// Total minimap content height; clamped so it never exceeds the strip.
    public var minimapContentHeight: Double {
        min(Double(lineCount) * minimapLineHeight, minimapHeight)
    }

    /// The height of the slider (the box representing the visible viewport).
    public var sliderHeight: Double {
        guard documentHeight > 0 else { return minimapHeight }
        let fraction = min(1.0, viewportHeight / documentHeight)
        return max(8.0, minimapContentHeight * fraction)
    }

    /// The slider's top y-position given the editor's scroll offset.
    public func sliderY(forScrollOffset scrollOffset: Double) -> Double {
        let maxScroll = max(0, documentHeight - viewportHeight)
        guard maxScroll > 0 else { return 0 }
        let progress = (scrollOffset.clamped(to: 0...maxScroll)) / maxScroll
        let travel = max(0, minimapContentHeight - sliderHeight)
        return progress * travel
    }

    /// Converts a click/drag at minimap y-position into an editor scroll offset,
    /// centering the viewport on the clicked location.
    public func scrollOffset(forMinimapY y: Double) -> Double {
        let maxScroll = max(0, documentHeight - viewportHeight)
        guard minimapContentHeight > 0, maxScroll > 0 else { return 0 }
        let travel = max(1e-6, minimapContentHeight - sliderHeight)
        let progress = (y - sliderHeight / 2).clamped(to: 0...travel) / travel
        return progress * maxScroll
    }
}
