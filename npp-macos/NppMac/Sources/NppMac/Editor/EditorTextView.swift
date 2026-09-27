import AppKit

/// NSTextView with Notepad++-style column (rectangular) selection via Option-drag
/// or an explicit Column Mode toggle, plus Cmd-click multi-caret editing.
final class EditorTextView: NSTextView {
    /// When true, ordinary drag also builds a rectangle selection.
    var columnModeEnabled = false

    /// Number of active carets / selection ranges (1 = normal editing).
    var caretCount: Int { selectedRanges.count }

    private var columnDragging = false
    private var columnAnchor: (line: Int, col: Int)?

    // MARK: - Mouse (column + multi-caret)

    override func mouseDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let option = flags.contains(.option)
        let command = flags.contains(.command)

        // Option / Column Mode wins over Cmd-click (rectangular select).
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

        // Cmd-click: add caret, or remove if one already exists at that index.
        if command && !flags.contains(.shift) && !flags.contains(.control) {
            columnDragging = false
            columnAnchor = nil
            window?.makeFirstResponder(self)
            let pt = convert(event.locationInWindow, from: nil)
            let idx = characterIndexForInsertion(at: pt)
            toggleCaret(at: idx)
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

    // MARK: - Multi-caret edits

    /// Insert `text` at every caret / selection range (end → start so offsets stay valid).
    func insertInColumn(_ text: String) {
        let ranges = selectedRanges.map(\.rangeValue)
        guard ranges.count > 1 else {
            super.insertText(text, replacementRange: selectedRange())
            return
        }
        let textLen = (text as NSString).length
        var newCarets: [NSRange] = []
        undoManager?.beginUndoGrouping()
        for r in ranges.sorted(by: { $0.location > $1.location }) {
            if shouldChangeText(in: r, replacementString: text) {
                textStorage?.replaceCharacters(in: r, with: text)
                didChangeText()
            }
            newCarets.append(NSRange(location: r.location + textLen, length: 0))
        }
        undoManager?.endUndoGrouping()
        selectedRanges = Self.uniqueSortedRanges(newCarets)
        needsDisplay = true
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
        if selectedRanges.count > 1 {
            insertInColumn(text)
            return
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        guard selectedRanges.count > 1 else {
            super.deleteBackward(sender)
            return
        }
        deleteAtAllCarets(forward: false)
    }

    override func deleteForward(_ sender: Any?) {
        guard selectedRanges.count > 1 else {
            super.deleteForward(sender)
            return
        }
        deleteAtAllCarets(forward: true)
    }

    override func paste(_ sender: Any?) {
        guard selectedRanges.count > 1 else {
            super.paste(sender)
            return
        }
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        insertInColumn(text)
    }

    // MARK: - Arrow keys (same delta at every caret)

    override func moveLeft(_ sender: Any?) {
        guard selectedRanges.count > 1 else {
            super.moveLeft(sender)
            return
        }
        moveAllCarets(horizontal: -1)
    }

    override func moveRight(_ sender: Any?) {
        guard selectedRanges.count > 1 else {
            super.moveRight(sender)
            return
        }
        moveAllCarets(horizontal: 1)
    }

    override func moveUp(_ sender: Any?) {
        guard selectedRanges.count > 1 else {
            super.moveUp(sender)
            return
        }
        moveAllCarets(vertical: -1)
    }

    override func moveDown(_ sender: Any?) {
        guard selectedRanges.count > 1 else {
            super.moveDown(sender)
            return
        }
        moveAllCarets(vertical: 1)
    }

    // MARK: - Escape clears extra carets

    override func cancelOperation(_ sender: Any?) {
        if selectedRanges.count > 1 {
            clearExtraCarets()
            return
        }
        super.cancelOperation(sender)
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(cancelOperation(_:)), selectedRanges.count > 1 {
            clearExtraCarets()
            return
        }
        super.doCommand(by: selector)
    }

    /// Keep the primary `selectedRange()` and drop the rest.
    func clearExtraCarets() {
        setSelectedRange(selectedRange())
        needsDisplay = true
    }

    // MARK: - Secondary caret drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawSecondaryCarets(in: dirtyRect)
    }

    private func drawSecondaryCarets(in dirtyRect: NSRect) {
        let ranges = selectedRanges.map(\.rangeValue)
        guard ranges.count > 1, let layoutManager, textContainer != nil else { return }
        let primary = selectedRange()
        let color = insertionPointColor.withAlphaComponent(0.85)
        let nsLen = (string as NSString).length

        for r in ranges {
            // AppKit draws non-empty selection highlights; only paint zero-length extras.
            guard r.length == 0 else { continue }
            if NSEqualRanges(r, primary) { continue }

            let loc = max(0, min(r.location, nsLen))
            let origin = textContainerOrigin
            let caretHeight: CGFloat
            let caretX: CGFloat
            let caretY: CGFloat

            if nsLen == 0 || layoutManager.numberOfGlyphs == 0 {
                caretHeight = font?.boundingRectForFont.height ?? 16
                caretX = origin.x
                caretY = origin.y
            } else {
                let glyphIndex: Int
                if loc >= nsLen {
                    glyphIndex = max(0, layoutManager.numberOfGlyphs - 1)
                } else {
                    glyphIndex = layoutManager.glyphIndexForCharacter(at: loc)
                }
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                caretHeight = max(lineRect.height, font?.boundingRectForFont.height ?? 14)
                caretY = origin.y + lineRect.origin.y
                if loc >= nsLen {
                    let used = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                    caretX = origin.x + used.maxX
                } else {
                    caretX = origin.x + layoutManager.location(forGlyphAt: glyphIndex).x
                }
            }

            let rect = NSRect(x: caretX, y: caretY, width: 1.5, height: caretHeight)
            if rect.intersects(dirtyRect) {
                color.setFill()
                rect.fill()
            }
        }
    }

    // MARK: - Helpers

    private func toggleCaret(at index: Int) {
        let nsLen = (string as NSString).length
        let idx = max(0, min(index, nsLen))
        var ranges = selectedRanges.map(\.rangeValue)

        if let existing = ranges.firstIndex(where: { $0.length == 0 && $0.location == idx }) {
            if ranges.count > 1 {
                ranges.remove(at: existing)
                selectedRanges = Self.uniqueSortedRanges(ranges)
            }
            needsDisplay = true
            return
        }

        ranges.append(NSRange(location: idx, length: 0))
        selectedRanges = Self.uniqueSortedRanges(ranges)
        needsDisplay = true
    }

    private func deleteAtAllCarets(forward: Bool) {
        let ns = string as NSString
        var newCarets: [NSRange] = []
        undoManager?.beginUndoGrouping()
        for r in selectedRanges.map(\.rangeValue).sorted(by: { $0.location > $1.location }) {
            if r.length > 0 {
                if shouldChangeText(in: r, replacementString: "") {
                    textStorage?.replaceCharacters(in: r, with: "")
                    didChangeText()
                }
                newCarets.append(NSRange(location: r.location, length: 0))
                continue
            }
            if forward {
                guard r.location < ns.length else {
                    newCarets.append(r)
                    continue
                }
                let del = ns.rangeOfComposedCharacterSequence(at: r.location)
                if shouldChangeText(in: del, replacementString: "") {
                    textStorage?.replaceCharacters(in: del, with: "")
                    didChangeText()
                }
                newCarets.append(NSRange(location: r.location, length: 0))
            } else {
                guard r.location > 0 else {
                    newCarets.append(r)
                    continue
                }
                let del = ns.rangeOfComposedCharacterSequence(at: r.location - 1)
                if shouldChangeText(in: del, replacementString: "") {
                    textStorage?.replaceCharacters(in: del, with: "")
                    didChangeText()
                }
                newCarets.append(NSRange(location: del.location, length: 0))
            }
        }
        undoManager?.endUndoGrouping()
        selectedRanges = Self.uniqueSortedRanges(newCarets)
        needsDisplay = true
    }

    private func moveAllCarets(horizontal delta: Int) {
        let nsLen = (string as NSString).length
        let moved: [NSRange] = selectedRanges.map(\.rangeValue).map { r in
            let point: Int
            if r.length == 0 {
                point = r.location
            } else if delta < 0 {
                point = r.location
            } else {
                point = NSMaxRange(r)
            }
            let loc = max(0, min(nsLen, point + delta))
            return NSRange(location: loc, length: 0)
        }
        selectedRanges = Self.uniqueSortedRanges(moved)
        if let first = selectedRanges.first?.rangeValue {
            scrollRangeToVisible(first)
        }
        needsDisplay = true
    }

    private func moveAllCarets(vertical lineDelta: Int) {
        let moved: [NSRange] = selectedRanges.map(\.rangeValue).map { r in
            let point = r.length == 0 ? r.location : (lineDelta < 0 ? r.location : NSMaxRange(r))
            let (line, col) = lineColumn(atCharIndex: point)
            let targetLine = max(0, line + lineDelta)
            let loc = charIndex(line: targetLine, column: col)
            return NSRange(location: loc, length: 0)
        }
        selectedRanges = Self.uniqueSortedRanges(moved)
        if let first = selectedRanges.first?.rangeValue {
            scrollRangeToVisible(first)
        }
        needsDisplay = true
    }

    private static func uniqueSortedRanges(_ ranges: [NSRange]) -> [NSValue] {
        var seenCaretLocs = Set<Int>()
        var out: [NSRange] = []
        for r in ranges.sorted(by: { $0.location < $1.location }) {
            if r.length == 0 {
                if seenCaretLocs.contains(r.location) { continue }
                seenCaretLocs.insert(r.location)
            }
            out.append(r)
        }
        return out.map { NSValue(range: $0) }
    }

    private func lineColumn(at point: NSPoint) -> (line: Int, col: Int)? {
        guard let layoutManager, let textContainer else { return nil }
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer, fractionOfDistanceThroughGlyph: nil)
        let charIdx = layoutManager.characterIndexForGlyph(at: glyph)
        return lineColumn(atCharIndex: charIdx)
    }

    private func lineColumn(atCharIndex charIdx: Int) -> (line: Int, col: Int) {
        let ns = string as NSString
        let clamped = max(0, min(charIdx, ns.length))
        var line = 0
        var col = 0
        var i = 0
        while i < clamped {
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

    private func charIndex(line: Int, column: Int) -> Int {
        let ns = string as NSString
        var currentLine = 0
        var lineStart = 0
        var i = 0
        while i <= ns.length {
            let atEnd = i == ns.length
            let isNL = !atEnd && ns.character(at: i) == 10
            if isNL || atEnd {
                if currentLine == line {
                    let lineLen = i - lineStart
                    return lineStart + min(column, lineLen)
                }
                if atEnd { break }
                currentLine += 1
                lineStart = i + 1
            }
            i += 1
        }
        // Past last line: clamp to end.
        return ns.length
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
            needsDisplay = true
        }
    }
}
