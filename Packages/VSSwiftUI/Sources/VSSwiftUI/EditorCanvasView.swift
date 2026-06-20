import SwiftUI
import AppKit
import VSSwiftCore

/// Maps ``TextPosition`` (line, Character column) values to UTF-16 offsets used by
/// `NSTextStorage`, so semantic tokens can be applied as attributes.
struct UTF16OffsetMap {
    private let lineStartUTF16: [Int]
    private let lines: [Substring]

    init(_ text: String) {
        var starts: [Int] = [0]
        var utf16Count = 0
        var slices: [Substring] = []
        var lineStart = text.startIndex
        var idx = text.startIndex
        while idx < text.endIndex {
            let ch = text[idx]
            if ch == "\n" {
                slices.append(text[lineStart..<idx])
                utf16Count += String(ch).utf16.count
                starts.append(utf16Count)
                lineStart = text.index(after: idx)
            } else {
                utf16Count += String(ch).utf16.count
            }
            idx = text.index(after: idx)
        }
        slices.append(text[lineStart..<text.endIndex])
        self.lineStartUTF16 = starts
        self.lines = slices
    }

    func utf16Offset(of position: TextPosition) -> Int {
        guard position.line < lineStartUTF16.count else { return lineStartUTF16.last ?? 0 }
        let lineStart = lineStartUTF16[position.line]
        let line = lines[position.line]
        var col = 0
        var utf16 = 0
        var i = line.startIndex
        while i < line.endIndex && col < position.column {
            utf16 += String(line[i]).utf16.count
            col += 1
            i = line.index(after: i)
        }
        return lineStart + utf16
    }

    func nsRange(for range: VSSwiftRange) -> NSRange {
        let s = utf16Offset(of: range.start)
        let e = utf16Offset(of: range.end)
        return NSRange(location: s, length: max(0, e - s))
    }
}

/// A high-performance editing surface bridging AppKit's TextKit 2 `NSTextView` into
/// SwiftUI. NSTextView (macOS 13+) is backed by `NSTextLayoutManager` /
/// `NSTextViewportLayoutController`, giving viewport-virtualized layout for large files.
public struct EditorCanvasView: NSViewRepresentable {
    @ObservedObject var model: EditorViewModel
    var theme: Theme
    var configuration: EditorConfiguration

    public init(model: EditorViewModel, theme: Theme, configuration: EditorConfiguration) {
        self.model = model
        self.theme = theme
        self.configuration = configuration
    }

    public func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let contentSize = scrollView.contentSize

        // Build a TextKit 1 stack so the in-view gutter can draw via `draw(_:)` and
        // measure line rects with `NSLayoutManager` (TextKit 2 renders text in layers,
        // which bypasses `draw(_:)` and would leave the gutter blank).
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: contentSize.width,
                                                         height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(textContainer)

        let textView = GutterTextView(frame: NSRect(origin: .zero, size: contentSize),
                                      textContainer: textContainer)
        textView.showsGutter = configuration.showLineNumbers
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.usesFindBar = true
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 0, height: 8)

        // Critical sizing configuration for a text view embedded in a scroll view.
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textContainer.widthTracksTextView = false
        textContainer.lineFragmentPadding = 5

        textView.string = model.text

        scrollView.documentView = textView

        // Line-number gutter via NSRulerView (reliable, correctly aligned vertically).
        // The text is additionally inset by `gutterWidth` through GutterTextView's
        // `textContainerOrigin`, so numbers never overlap the text horizontally.
        if configuration.showLineNumbers {
            let ruler = LineNumberRulerView(textView: textView, thickness: textView.gutterWidth)
            scrollView.verticalRulerView = ruler
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
            context.coordinator.ruler = ruler
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(ruler, selector: #selector(LineNumberRulerView.redraw),
                                                   name: NSText.didChangeNotification, object: textView)
            NotificationCenter.default.addObserver(ruler, selector: #selector(LineNumberRulerView.redraw),
                                                   name: NSView.boundsDidChangeNotification,
                                                   object: scrollView.contentView)
        }

        context.coordinator.textView = textView
        applyStyling(textView)
        applyTokens(textView)
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != model.text {
            let selected = textView.selectedRanges
            textView.string = model.text
            let len = (textView.string as NSString).length
            textView.selectedRanges = selected.compactMap { value in
                let r = value.rangeValue
                guard r.location <= len else { return nil }
                return NSValue(range: NSRange(location: r.location, length: min(r.length, len - r.location)))
            }
        }
        applyStyling(textView)
        applyTokens(textView)
        context.coordinator.ruler?.needsDisplay = true
    }

    private func applyStyling(_ textView: NSTextView) {
        let font = NSFont(name: configuration.fontName, size: configuration.fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
        textView.font = font
        let bg = theme.nsColor("editor.background", fallback: .init(red: 0.12, green: 0.12, blue: 0.12))
        let fg = theme.nsColor("editor.foreground", fallback: .init(red: 0.83, green: 0.83, blue: 0.83))
        textView.backgroundColor = bg
        textView.textColor = fg
        textView.insertionPointColor = theme.nsColor("editorCursor.foreground", fallback: .init(red: 0.7, green: 0.7, blue: 0.7))
        textView.enclosingScrollView?.backgroundColor = bg
    }

    private func applyTokens(_ textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
        let fullText = textView.string
        let map = UTF16OffsetMap(fullText)
        let fullRange = NSRange(location: 0, length: (fullText as NSString).length)

        storage.beginEditing()
        let baseColor = theme.nsColor("editor.foreground", fallback: .init(red: 0.83, green: 0.83, blue: 0.83))
        storage.addAttribute(.foregroundColor, value: baseColor, range: fullRange)
        storage.addAttribute(.font, value: font, range: fullRange)

        for token in model.tokens {
            let style = theme.style(forScope: token.scope)
            let nsRange = map.nsRange(for: token.range)
            guard nsRange.location + nsRange.length <= fullRange.length, nsRange.length > 0 else { continue }
            if let fg = style.foreground {
                storage.addAttribute(.foregroundColor, value: NSColor(fg), range: nsRange)
            }
            if !style.fontStyle.isEmpty {
                storage.addAttribute(.font, value: style.fontStyle.apply(to: font), range: nsRange)
            }
            if style.fontStyle.contains(.underline) {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
            }
        }
        storage.endEditing()
    }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        let model: EditorViewModel
        weak var textView: NSTextView?
        weak var ruler: LineNumberRulerView?

        init(model: EditorViewModel) { self.model = model }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            model.updateText(textView.string)
            ruler?.needsDisplay = true
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let nsRange = textView.selectedRange()
            let nsString = textView.string as NSString
            let prefix = nsString.substring(to: min(nsRange.location, nsString.length))
            let line = prefix.components(separatedBy: "\n").count - 1
            let lastNewline = prefix.range(of: "\n", options: .backwards)
            let column: Int
            if let r = lastNewline {
                column = prefix.distance(from: r.upperBound, to: prefix.endIndex)
            } else {
                column = prefix.count
            }
            let pos = TextPosition(line: line, column: column)
            model.selection.setPrimary(VSSwiftRange(start: pos, end: pos))
            ruler?.currentLine = line
            ruler?.needsDisplay = true
        }
    }
}

/// A TextKit 1 `NSTextView` that reserves a left gutter strip by offsetting its text
/// container origin so a vertical `NSRulerView` gutter never overlaps the text, even if
/// the scroll view fails to reserve ruler space.
public final class GutterTextView: NSTextView {
    var showsGutter: Bool = true
    var gutterWidth: CGFloat = 56
    var rightPadding: CGFloat = 8

    private var leftInset: CGFloat { showsGutter ? gutterWidth : rightPadding }

    public override var textContainerOrigin: NSPoint {
        NSPoint(x: leftInset, y: textContainerInset.height)
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let available = max(0, newSize.width - leftInset - rightPadding)
        textContainer?.size = NSSize(width: available, height: CGFloat.greatestFiniteMagnitude)
    }
}

/// A line-number gutter ruler drawn by `NSScrollView`. It enumerates `NSLayoutManager`
/// line fragments to place right-aligned numbers aligned with each visible line and
/// highlights the caret's current line.
public final class LineNumberRulerView: NSRulerView {
    weak var lineTextView: GutterTextView?
    var currentLine: Int = 0
    private let numberFont = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
    private let textColor = NSColor(srgbRed: 0.42, green: 0.43, blue: 0.52, alpha: 1)
    private let currentColor = NSColor(srgbRed: 0.86, green: 0.86, blue: 0.92, alpha: 1)
    private let bgColor = NSColor(srgbRed: 0.078, green: 0.082, blue: 0.110, alpha: 1)

    init(textView: GutterTextView, thickness: CGFloat) {
        self.lineTextView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = thickness
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc func redraw() { needsDisplay = true }

    public override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = lineTextView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        bgColor.setFill()
        bounds.fill()
        NSColor.white.withAlphaComponent(0.06).setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()

        let yInset = textView.textContainerInset.height
        let relativePoint = self.convert(NSPoint.zero, from: textView)
        let visibleRect = textView.visibleRect
        let text = (textView.string as NSString)

        var lineNumber = 1
        var charIndex = 0
        while charIndex <= text.length {
            let lineRange = text.lineRange(for: NSRange(location: charIndex, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)

            if lineRect.maxY >= visibleRect.minY && lineRect.minY <= visibleRect.maxY {
                let isCurrent = (lineNumber - 1) == currentLine
                let y = lineRect.minY + relativePoint.y + yInset
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: numberFont,
                    .foregroundColor: isCurrent ? currentColor : textColor
                ]
                let str = NSAttributedString(string: "\(lineNumber)", attributes: attrs)
                let strSize = str.size()
                let drawRect = NSRect(x: bounds.width - strSize.width - 12,
                                      y: y + (lineRect.height - strSize.height) / 2,
                                      width: strSize.width, height: strSize.height)
                str.draw(in: drawRect)
            }

            if lineRect.minY > visibleRect.maxY { break }
            let next = NSMaxRange(lineRange)
            if next == charIndex { break }
            charIndex = next
            lineNumber += 1
        }
    }
}

