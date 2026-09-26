import AppKit
import Foundation

/// Document facade over the Rust engine (`npp-core` / `npp-fs` via FFI).
final class DocumentStore {
    struct Document {
        var title: String
        var fileURL: URL?
        var text: String
        var isDirty: Bool
        var encodingLabel: String
        var language: String
    }

    /// Lightweight tab metadata (avoids pulling full buffer text for every tab redraw).
    struct TabInfo {
        var title: String
        var isDirty: Bool
        var fileURL: URL?
    }

    private let engine: NppEngine
    /// Per-document editor undo history, index-aligned with the engine's documents.
    private var undoManagers: [UndoManager]

    init(engine: NppEngine = NppEngine()) {
        self.engine = engine
        undoManagers = (0..<engine.count).map { _ in UndoManager() }
    }

    func undoManager(at index: Int) -> UndoManager? {
        undoManagers.indices.contains(index) ? undoManagers[index] : nil
    }

    var count: Int { engine.count }

    var documents: [Document] {
        (0..<engine.count).map { snapshot(at: $0) }
    }

    var tabs: [TabInfo] {
        (0..<engine.count).map { index in
            let path = engine.path(at: index)
            return TabInfo(
                title: engine.title(at: index),
                isDirty: engine.isDirty(at: index),
                fileURL: path.map { URL(fileURLWithPath: $0) }
            )
        }
    }

    var selectedIndex: Int {
        get { engine.selectedIndex }
        set { _ = engine.select(at: newValue) }
    }

    var selected: Document? {
        let i = selectedIndex
        guard i >= 0, i < engine.count else { return nil }
        return snapshot(at: i, includeText: true)
    }

    /// Tab/status metadata without copying the full buffer (avoids double-load on refresh).
    func selectedMeta() -> (title: String, isDirty: Bool, encodingLabel: String, language: String, languageDisplay: String, eolLabel: String, fileURL: URL?)? {
        let i = selectedIndex
        guard i >= 0, i < engine.count else { return nil }
        let path = engine.path(at: i)
        let lang = engine.language(at: i)
        return (
            engine.title(at: i),
            engine.isDirty(at: i),
            engine.encoding(at: i).label,
            lang,
            NppEngine.displayName(for: lang),
            engine.eol(at: i).label,
            path.map { URL(fileURLWithPath: $0) }
        )
    }

    private func snapshot(at index: Int, includeText: Bool = true) -> Document {
        let path = engine.path(at: index)
        return Document(
            title: engine.title(at: index),
            fileURL: path.map { URL(fileURLWithPath: $0) },
            text: includeText ? engine.text(at: index) : "",
            isDirty: engine.isDirty(at: index),
            encodingLabel: engine.encoding(at: index).label,
            language: engine.language(at: index)
        )
    }

    func newDocument() {
        _ = engine.newDocument()
        undoManagers.append(UndoManager())
    }

    @discardableResult
    func openDocument(url: URL) -> Bool {
        let path = url.withUnsafeFileSystemRepresentation { ptr -> String? in
            guard let ptr else { return nil }
            return String(cString: ptr)
        } ?? url.path
        guard engine.open(path: path) != nil else { return false }
        undoManagers.append(UndoManager())
        return true
    }

    /// Re-read `index`'s file from disk in place (close + reopen pattern).
    @discardableResult
    func reloadFromDisk(at index: Int) -> Bool {
        guard tabs.indices.contains(index), let url = tabs[index].fileURL else { return false }
        guard openDocument(url: url) else { return false }
        moveTab(from: count - 1, to: index)
        close(at: index + 1)
        select(at: index)
        return true
    }

    /// Index of an open document backed by `url`, if any.
    func index(of url: URL) -> Int? {
        let target = url.standardizedFileURL.resolvingSymlinksInPath()
        return tabs.firstIndex { $0.fileURL?.standardizedFileURL.resolvingSymlinksInPath() == target }
    }

    /// Insert an in-memory document (e.g. Find-in-Files results).
    func openDocument(title: String, url: URL?, text: String, language: String) {
        newDocument()
        let idx = engine.selectedIndex
        engine.setText(at: idx, text)
        engine.markSaved(at: idx, title: title, path: url?.path)
        _ = engine.setLanguage(at: idx, language)
    }

    func setLanguage(_ language: String) {
        let i = selectedIndex
        guard i >= 0 else { return }
        _ = engine.setLanguage(at: i, language)
    }

    func languages() -> [(key: String, display: String)] {
        engine.languages()
    }

    @discardableResult
    func loadUDL(path: String) throws -> Int {
        try engine.loadUDL(path: path)
    }

    func language(forPath path: String) -> String {
        engine.language(forPath: path)
    }

    func color(forScope scope: Int32, language: String) -> NSColor {
        engine.color(forScope: scope, language: language)
    }

    func findAll(in text: String, pattern: String, caseSensitive: Bool, wholeWord: Bool, regex: Bool) throws -> [NppEngine.Match] {
        try engine.findAll(in: text, pattern: pattern, caseSensitive: caseSensitive, wholeWord: wholeWord, regex: regex)
    }

    func findCount(in text: String, pattern: String, caseSensitive: Bool, wholeWord: Bool, regex: Bool) throws -> Int {
        try engine.findCount(in: text, pattern: pattern, caseSensitive: caseSensitive, wholeWord: wholeWord, regex: regex)
    }

    func replaceAll(in text: String, pattern: String, replacement: String, caseSensitive: Bool, wholeWord: Bool, regex: Bool) throws -> (String, Int) {
        try engine.replaceAll(in: text, pattern: pattern, replacement: replacement, caseSensitive: caseSensitive, wholeWord: wholeWord, regex: regex)
    }

    func updateSelected(text: String) {
        let i = selectedIndex
        guard i >= 0 else { return }
        engine.setText(at: i, text)
    }

    func markSaved(at index: Int, title: String? = nil, url: URL? = nil) {
        engine.markSaved(at: index, title: title, path: url?.path)
    }

    func select(at index: Int) {
        _ = engine.select(at: index)
    }

    func moveTab(from: Int, to: Int) {
        guard engine.moveTab(from: from, to: to) else { return }
        undoManagers.insert(undoManagers.remove(at: from), at: to)
    }

    func close(at index: Int) {
        guard engine.close(at: index) else { return }
        undoManagers.remove(at: index)
        // Closing the last tab makes the engine open a fresh "new N" document.
        while undoManagers.count < engine.count {
            undoManagers.append(UndoManager())
        }
    }

    func save(at index: Int, to url: URL? = nil) throws {
        let path = url.flatMap { u in
            u.withUnsafeFileSystemRepresentation { ptr -> String? in
                guard let ptr else { return nil }
                return String(cString: ptr)
            } ?? u.path
        }
        try engine.save(at: index, path: path)
    }

    func setEncoding(_ enc: DocEncoding) {
        let i = selectedIndex
        guard i >= 0 else { return }
        engine.setEncoding(at: i, enc)
    }

    func encoding(at index: Int) -> DocEncoding {
        engine.encoding(at: index)
    }

    func setEol(_ eol: DocEol) {
        let i = selectedIndex
        guard i >= 0 else { return }
        engine.setEol(at: i, eol)
    }

    func eol(at index: Int) -> DocEol {
        engine.eol(at: index)
    }

    func highlight(language: String, text: String) -> [NppEngine.Token] {
        engine.highlight(language: language, text: text)
    }

    func text(at index: Int) -> String {
        engine.text(at: index)
    }

    func isDirty(at index: Int) -> Bool {
        engine.isDirty(at: index)
    }

    func title(at index: Int) -> String {
        engine.title(at: index)
    }
}
