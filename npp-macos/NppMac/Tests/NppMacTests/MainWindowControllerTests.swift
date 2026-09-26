import AppKit
import XCTest
@testable import NppMac

/// Drives the real window controller (no nib, no run loop beyond short spins).
final class MainWindowControllerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        _ = NSApplication.shared
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nppmac-wc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ name: String, _ body: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func spin(_ seconds: TimeInterval = 0.3) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func textView(of wc: MainWindowController) throws -> NSTextView {
        func find(_ v: NSView) -> NSTextView? {
            if let tv = v as? NSTextView { return tv }
            for s in v.subviews { if let tv = find(s) { return tv } }
            return nil
        }
        return try XCTUnwrap(wc.window?.contentView.flatMap(find))
    }

    func testWindowExistsWithoutNib() throws {
        let wc = MainWindowController(documents: DocumentStore())
        // Regression: overriding loadWindow() without a nib left `window` nil (app stuck in Dock).
        XCTAssertNotNil(wc.window)
        XCTAssertNoThrow(try textView(of: wc))
    }

    func testOpenReplacesFreshTabAndDoesNotDuplicate() throws {
        let store = DocumentStore()
        let wc = MainWindowController(documents: store)
        let url = try write("a.rs", "fn main() {}\n")
        wc.openPaths([url.path])
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.title(at: 0), "a.rs")
        XCTAssertEqual(try textView(of: wc).string, "fn main() {}\n")
        wc.openPaths([url.path])
        XCTAssertEqual(store.count, 1)
        wc.close()
    }

    func testTypingSyncsAndSavePreservesCRLF() throws {
        let store = DocumentStore()
        let wc = MainWindowController(documents: store)
        let url = try write("crlf.txt", "one\r\ntwo\r\n")
        wc.openPaths([url.path])
        let tv = try textView(of: wc)
        XCTAssertEqual(tv.string, "one\ntwo\n")
        tv.setSelectedRange(NSRange(location: 3, length: 0))
        tv.insertText("!", replacementRange: tv.selectedRange())
        spin()
        XCTAssertTrue(store.isDirty(at: 0))
        wc.fileSave(nil)
        XCTAssertFalse(store.isDirty(at: 0))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "one!\r\ntwo\r\n")
        wc.close()
    }

    func testUndoIsPerDocumentAndCoversLineOps() throws {
        let store = DocumentStore()
        let wc = MainWindowController(documents: store)
        let a = try write("a.txt", "alpha\nbeta\n")
        let b = try write("b.txt", "gamma\n")
        wc.openPaths([a.path, b.path])
        let tv = try textView(of: wc)
        XCTAssertEqual(store.selectedIndex, 1)

        // Line op in b is undoable.
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        wc.editDuplicateLine(nil)
        XCTAssertEqual(tv.string, "gamma\ngamma\n")
        tv.undoManager?.undo()
        XCTAssertEqual(tv.string, "gamma\n")
        tv.undoManager?.redo()
        spin()

        // Switching to a (re-open selects the existing tab): b's history must not apply to a.
        wc.openPaths([a.path])
        XCTAssertEqual(store.selectedIndex, 0)
        XCTAssertEqual(tv.string, "alpha\nbeta\n")
        XCTAssertFalse(tv.undoManager?.canUndo ?? true)

        // Move line down, then undo.
        wc.editMoveDown(nil)
        XCTAssertEqual(tv.string, "beta\nalpha\n")
        tv.undoManager?.undo()
        XCTAssertEqual(tv.string, "alpha\nbeta\n")
        spin()
        XCTAssertFalse(store.isDirty(at: 0))
        XCTAssertTrue(store.isDirty(at: 1))
        wc.close()
    }

    func testHighlightAppliesColors() throws {
        let wc = MainWindowController(documents: DocumentStore())
        let url = try write("h.rs", "// comment\nlet s = \"x\";\n")
        wc.openPaths([url.path])
        spin()
        let storage = try XCTUnwrap(try textView(of: wc).textStorage)
        let color = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.systemGray)
        wc.close()
    }

    /// Renders the window to `$NPP_SNAPSHOT` for manual layout review.
    func testSnapshotWhenRequested() throws {
        guard let out = ProcessInfo.processInfo.environment["NPP_SNAPSHOT"] else { throw XCTSkip("NPP_SNAPSHOT unset") }
        let wc = MainWindowController(documents: DocumentStore())
        // cacheDisplay skips the window background; light mode keeps labels legible.
        wc.window?.appearance = NSAppearance(named: .aqua)
        let url = try write("snap.rs","fn main() {\n    // hi\n    let s = \"x\";\n}\n")
        wc.openPaths([url.path, try write("other.txt", "x\n").path])
        wc.searchFind(nil)
        spin()
        let view = try XCTUnwrap(wc.window?.contentView)
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: out))
        wc.close()
    }
}
