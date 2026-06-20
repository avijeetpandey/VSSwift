import SwiftUI
import VSSwiftCore
import VSSwiftEngine

/// A scaled-down minimap of the document drawn as colored blocks per token,
/// with a draggable viewport slider. Uses ``MinimapMetrics`` for geometry math.
public struct MinimapView: View {
    var lines: [String]
    var tokens: [VSSwiftToken]
    var theme: Theme
    var lineHeight: Double
    var viewportHeight: Double
    @Binding var scrollOffset: Double

    public init(lines: [String], tokens: [VSSwiftToken], theme: Theme,
                lineHeight: Double, viewportHeight: Double, scrollOffset: Binding<Double>) {
        self.lines = lines
        self.tokens = tokens
        self.theme = theme
        self.lineHeight = lineHeight
        self.viewportHeight = viewportHeight
        self._scrollOffset = scrollOffset
    }

    public var body: some View {
        GeometryReader { geo in
            let metrics = MinimapMetrics(lineCount: max(lines.count, 1), lineHeight: lineHeight,
                                         minimapScale: 0.1, viewportHeight: viewportHeight,
                                         minimapHeight: geo.size.height)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let mlh = metrics.minimapLineHeight
                    let fg = theme.color("editor.foreground", fallback: .init(red: 0.5, green: 0.5, blue: 0.5))
                    let maxLines = min(lines.count, Int(size.height / max(mlh, 0.5)))
                    for i in 0..<maxLines {
                        let y = Double(i) * mlh
                        let length = min(Double(lines[i].count) * 0.8, Double(size.width) - 2)
                        let indent = Double(lines[i].prefix(while: { $0 == " " }).count) * 0.8
                        if length > indent {
                            let rect = CGRect(x: 2 + indent, y: y, width: length - indent, height: max(mlh - 0.5, 0.6))
                            context.fill(Path(rect), with: .color(Color(fg).opacity(0.45)))
                        }
                    }
                }
                // Viewport slider.
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.accent.opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Palette.accent.opacity(0.30), lineWidth: 1))
                    .frame(height: metrics.sliderHeight)
                    .offset(y: metrics.sliderY(forScrollOffset: scrollOffset))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        scrollOffset = metrics.scrollOffset(forMinimapY: value.location.y)
                    }
            )
        }
        .frame(width: 72)
        .background(Palette.bg)
        .overlay(alignment: .leading) { Rectangle().fill(Palette.border).frame(width: 1) }
    }
}
