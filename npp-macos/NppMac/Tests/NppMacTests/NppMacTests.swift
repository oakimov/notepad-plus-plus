import XCTest
@testable import NppMac

final class DocumentStoreTests: XCTestCase {
    func testOpenSelectClose() {
        let store = DocumentStore()
        XCTAssertEqual(store.documents.count, 1)
        store.newDocument()
        XCTAssertEqual(store.selectedIndex, 1)
        store.openDocument(title: "a.txt", url: nil, text: "hi", language: "normal")
        XCTAssertEqual(store.selected?.title, "a.txt")
        store.select(at: 0)
        XCTAssertEqual(store.selectedIndex, 0)
        store.close(at: 0)
        XCTAssertEqual(store.documents.count, 2)
    }

    func testDirtyLifecycle() {
        let store = DocumentStore()
        XCTAssertFalse(store.selected?.isDirty ?? true)
        store.updateSelected(text: "x")
        XCTAssertTrue(store.selected?.isDirty ?? false)
        store.markSaved(at: 0, title: "s.txt", url: nil)
        XCTAssertFalse(store.selected?.isDirty ?? true)
        XCTAssertEqual(store.selected?.title, "s.txt")
    }

    func testMoveTabKeepsSelection() {
        let store = DocumentStore()
        store.newDocument()
        store.newDocument()
        store.select(at: 0)
        store.moveTab(from: 0, to: 2)
        XCTAssertEqual(store.selectedIndex, 2)
        XCTAssertEqual(store.documents.count, 3)
    }

    func testOpenRealFileAndHighlight() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nppmac-swift-qa", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("sample.rs")
        try "fn main() {\n  let s = \"hi\";\n  // c\n}\n".write(to: url, atomically: true, encoding: .utf8)

        let store = DocumentStore()
        XCTAssertTrue(store.openDocument(url: url))
        let doc = try XCTUnwrap(store.selected)
        XCTAssertEqual(doc.title, "sample.rs")
        XCTAssertEqual(doc.language, "rust")
        XCTAssertTrue(doc.text.contains("fn main"))
        XCTAssertFalse(doc.isDirty)

        // Highlight/free repeatedly — regressions here crashed the app after Open.
        for _ in 0..<30 {
            let tokens = store.highlight(language: doc.language, text: doc.text)
            XCTAssertFalse(tokens.isEmpty)
        }
    }

    func testUndoManagersFollowTabs() {
        let store = DocumentStore()
        store.newDocument()
        store.newDocument()
        let first = store.undoManager(at: 0)
        let last = store.undoManager(at: 2)
        store.moveTab(from: 0, to: 2)
        XCTAssertTrue(store.undoManager(at: 2) === first)
        XCTAssertTrue(store.undoManager(at: 1) === last)
        store.close(at: 0)
        store.close(at: 0)
        store.close(at: 0)
        // Engine reopens a fresh document after the last close; it needs its own manager.
        XCTAssertEqual(store.count, 1)
        XCTAssertNotNil(store.undoManager(at: 0))
    }

    func testTabsDoNotRequireFullText() {
        let store = DocumentStore()
        store.openDocument(title: "x", url: nil, text: String(repeating: "a\n", count: 10_000), language: "normal")
        let tabs = store.tabs
        XCTAssertEqual(tabs.last?.title, "x")
        XCTAssertFalse(tabs.isEmpty)
    }
}
