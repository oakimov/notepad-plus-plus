import AppKit

/// NSTextView with Notepad++-style column (rectangular) selection via Option-drag
/// or an explicit Column Mode toggle.
final class EditorTextView: NSTextView {
    /// When true, ordinary drag also builds a rectangle selection.
    var columnModeEnabled = false

    private var columnDragging = false
    private var columnAnchor: (line: Int, col: Int)?

    override func mouseDown(with event: NSEvent) {
        let option = event.modifierFlags.contains(.option)
        if columnModeEnabled || option {
            columnDragging = true
            window?.makeFirstResponder(self)
            let pt = convert(event.locationInWindow, from: nil)
            columnAnchor = lineColumn(at: pt)
            if let a = columnAnchor {
                applyColumnSelection(from: a, to: a)
            }
            return
        }
        columnDragging = false
        columnAnchor = nil
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if columnDragging, let anchor = columnAnchor {
            let pt = convert(event.locationInWindow, from: nil)
            if let cur = lineColumn(at: pt) {
                applyColumnSelection(from: anchor, to: cur)
            }
            return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if columnDragging {
            columnDragging = false
            return
        }
        super.mouseUp(with: event)
    }

    /// Insert `text` at every caret in a rectangular selection (or normal insert).
    func insertInColumn(_ text: String) {
        let ranges = selectedRanges.map(\.rangeValue)
        guard ranges.count > 1 else {
            insertText(text, replacementRange: selectedRange())
            return
        }
        for r in ranges.sorted(by: { $0.location > $1.location }) {
            if shouldChangeText(in: r, replacementString: text) {
                textStorage?.replaceCharacters(in: r, with: text)
                didChangeText()
            }
        }
        if let first = ranges.min(by: { $0.location < $1.location }) {
            setSelectedRange(NSRange(location: first.location, length: (text as NSString).length))
        }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let text: String
        if let s = insertString as? String {
            text = s
        } else if let s = insertString as? NSString {
            text = s as String
        } else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }
        let ranges = selectedRanges.map(\.rangeValue)
        if ranges.count > 1 {
            insertInColumn(text)
            return
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    private func lineColumn(at point: NSPoint) -> (line: Int, col: Int)? {
        guard let layoutManager, let textContainer else { return nil }
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer, fractionOfDistanceThroughGlyph: nil)
        let charIdx = layoutManager.characterIndexForGlyph(at: glyph)
        let ns = string as NSString
        var line = 0
        var col = 0
        var i = 0
        while i < charIdx && i < ns.length {
            if ns.character(at: i) == 10 {
                line += 1
                col = 0
            } else {
                col += 1
            }
            i += 1
        }
        return (line, col)
    }

    private func applyColumnSelection(from a: (line: Int, col: Int), to b: (line: Int, col: Int)) {
        let line0 = min(a.line, b.line)
        let line1 = max(a.line, b.line)
        let col0 = min(a.col, b.col)
        let col1 = max(a.col, b.col)
        let ns = string as NSString
        var ranges: [NSValue] = []
        var line = 0
        var lineStart = 0
        var i = 0
        while i <= ns.length {
            let atEnd = i == ns.length
            let isNL = !atEnd && ns.character(at: i) == 10
            if isNL || atEnd {
                if line >= line0 && line <= line1 {
                    let lineLen = i - lineStart
                    let startCol = min(col0, lineLen)
                    let endCol = min(col1, lineLen)
                    let loc = lineStart + startCol
                    let len = max(0, endCol - startCol)
                    // Prefer at least a caret when columns equal.
                    ranges.append(NSValue(range: NSRange(location: loc, length: max(len, 0))))
                }
                if atEnd { break }
                line += 1
                lineStart = i + 1
            }
            i += 1
        }
        if !ranges.isEmpty {
            selectedRanges = ranges
        }
    }
}
