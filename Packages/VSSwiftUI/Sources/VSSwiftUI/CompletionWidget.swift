import SwiftUI
import VSSwiftCore
import VSSwiftLSP

/// A floating IntelliSense list, anchored below the caret. Modernized with colored
/// kind glyphs, a material background, rounded corners, and smooth selection tracking.
public struct CompletionWidget: View {
    let items: [CompletionItem]
    @Binding var selectedIndex: Int
    var theme: Theme
    var onCommit: (CompletionItem) -> Void

    public init(items: [CompletionItem], selectedIndex: Binding<Int>, theme: Theme,
                onCommit: @escaping (CompletionItem) -> Void) {
        self.items = items
        self._selectedIndex = selectedIndex
        self.theme = theme
        self.onCommit = onCommit
    }

    public var body: some View {
        listView
            .frame(width: 360, height: panelHeight)
            .background(.ultraThinMaterial)
            .background(Palette.surface.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.borderStrong, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
    }

    private var panelHeight: CGFloat {
        min(CGFloat(items.count) * 30 + 10, 260)
    }

    private var listView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        CompletionRow(item: item, isSelected: index == selectedIndex)
                            .contentShape(Rectangle())
                            .onTapGesture { onCommit(item) }
                            .id(index)
                    }
                }
                .padding(5)
            }
            .onChange(of: selectedIndex) { _, newValue in
                withAnimation(Motion.quick) { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    static func kindInfo(_ kind: Int?) -> (symbol: String, color: Color) {
        switch kind {
        case 2, 3:  return ("function", Palette.accent)
        case 5:     return ("f.cursive", Palette.info)
        case 6:     return ("v.square", Palette.accentOrange)
        case 9:     return ("shippingbox", Palette.warning)
        case 7:     return ("c.square.fill", Palette.success)
        case 8:     return ("point.3.connected.trianglepath.dotted", Palette.info)
        case 13:    return ("list.bullet.indent", Palette.accentPink)
        case 14:    return ("key.fill", Palette.accentPink)
        case 22:    return ("s.square", Palette.success)
        default:    return ("circle.fill", Palette.textTertiary)
        }
    }

    public static func iconName(forKind kind: Int?) -> String { kindInfo(kind).symbol }
}

/// A single completion row with a colored kind glyph and selection highlight.
private struct CompletionRow: View {
    let item: CompletionItem
    let isSelected: Bool

    var body: some View {
        let kind = CompletionWidget.kindInfo(item.kind)
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(kind.color.opacity(0.18))
                    .frame(width: 18, height: 18)
                Image(systemName: kind.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(kind.color)
            }
            Text(item.label)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let detail = item.detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .overlay(alignment: .leading) { selectionBar }
    }

    @ViewBuilder private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected ? Palette.accentSoft : Color.clear)
    }

    @ViewBuilder private var selectionBar: some View {
        if isSelected {
            Capsule().fill(Palette.accentBarGradient)
                .frame(width: 2.5, height: 16).offset(x: 1)
        }
    }
}

/// Tracks completion widget keyboard navigation state.
@MainActor
public final class CompletionController: ObservableObject {
    @Published public var selectedIndex: Int = 0

    public init() {}

    public func moveDown(count: Int) {
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + 1) % count
    }

    public func moveUp(count: Int) {
        guard count > 0 else { return }
        selectedIndex = (selectedIndex - 1 + count) % count
    }

    public func reset() { selectedIndex = 0 }
}
