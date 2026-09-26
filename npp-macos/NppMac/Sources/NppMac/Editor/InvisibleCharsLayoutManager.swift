import AppKit

/// Draws middots / arrows for spaces and tabs when enabled.
final class InvisibleCharsLayoutManager: NSLayoutManager {
    var showInvisibles = false

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard showInvisibles, let ts = textStorage, let container = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard charRange.length > 0 else { return }
        let ns = ts.string as NSString
        let font = (ts.attribute(.font, at: charRange.location, effectiveRange: nil) as? NSFont)
            ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let color = NSColor.tertiaryLabelColor
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        for i in charRange.location..<NSMaxRange(charRange) {
            let ch = ns.character(at: i)
            let mark: String?
            if ch == 0x20 { mark = "·" }
            else if ch == 0x09 { mark = "→" }
            else if ch == 0x0A { mark = "¬" }
            else { mark = nil }
            guard let mark else { continue }
            let g = glyphIndexForCharacter(at: i)
            var rect = boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: container)
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            (mark as NSString).draw(at: rect.origin, withAttributes: attrs)
        }
    }
}
