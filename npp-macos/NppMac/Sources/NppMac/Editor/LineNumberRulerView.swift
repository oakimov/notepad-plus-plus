import AppKit

/// Vertical line-number gutter for the editor scroll view.
final class LineNumberRulerView: NSRulerView {
    private weak var editor: NSTextView?
    private var bookmarks: Set<Int> = []

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.editor = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setBookmarks(_ lines: Set<Int>) {
        bookmarks = lines
        needsDisplay = true
    }

    override var requiredThickness: CGFloat { 40 }

    override func drawHashMarksAndLabels(in _: NSRect) {
        guard let editor,
              let layout = editor.layoutManager,
              let container = editor.textContainer,
              let scroll = scrollView
        else { return }

        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        let visible = scroll.contentView.bounds
        let textVisible = editor.convert(visible, from: scroll.contentView)
        let glyphRange = layout.glyphRange(forBoundingRect: textVisible, in: container)
        let charRange = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let ns = editor.string as NSString

        var index = charRange.location
        let end = NSMaxRange(charRange)
        let attrsBase: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        ]

        while index < end && index < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            let lineNumber = ns.lineNumber(for: lineRange.location)
            var glyphRect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: NSRange(location: lineRange.location, length: 0), actualCharacterRange: nil), in: container)
            glyphRect.origin.x = editor.textContainerOrigin.x
            glyphRect.origin.y += editor.textContainerOrigin.y
            let pointInRuler = editor.convert(NSPoint(x: 0, y: glyphRect.minY), to: self)

            let label = "\(lineNumber + 1)" as NSString
            var attrs = attrsBase
            attrs[.foregroundColor] = bookmarks.contains(lineNumber)
                ? NSColor.systemOrange
                : NSColor.secondaryLabelColor
            let size = label.size(withAttributes: attrs)
            label.draw(
                at: NSPoint(x: ruleThickness - size.width - 6, y: pointInRuler.y),
                withAttributes: attrs
            )
            index = NSMaxRange(lineRange)
        }
    }
}

private extension NSString {
    func lineNumber(for utf16Location: Int) -> Int {
        var line = 0
        var idx = 0
        while idx < utf16Location && idx < length {
            let range = lineRange(for: NSRange(location: idx, length: 0))
            if range.location >= utf16Location { break }
            idx = NSMaxRange(range)
            line += 1
            if range.length == 0 { break }
        }
        return line
    }
}
