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

    func testLanguageCatalogAndSet() {
        let store = DocumentStore()
        let langs = store.languages()
        XCTAssertGreaterThan(langs.count, 50)
        XCTAssertEqual(langs.first?.key, "normal")
        XCTAssertTrue(langs.contains(where: { $0.key == "cpp" && $0.display == "C++" }))
        store.setLanguage("cpp")
        XCTAssertEqual(store.selectedMeta()?.language, "cpp")
        XCTAssertEqual(store.selectedMeta()?.languageDisplay, "C++")
        let tokens = store.highlight(language: "cpp", text: "// c\nint main() { return 0; }\n")
        XCTAssertFalse(tokens.isEmpty)
        XCTAssertTrue(tokens.contains(where: { $0.scope == 4 })) // comment
        XCTAssertTrue(tokens.contains(where: { $0.scope == 1 })) // keyword
    }

    func testOpenDocumentHonorsLanguage() {
        let store = DocumentStore()
        store.openDocument(title: "x", url: nil, text: "print(1)", language: "python")
        XCTAssertEqual(store.selectedMeta()?.language, "python")
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

    func testUDLMarkdownRoundTrip() throws {
        // …/npp-macos/NppMac/Tests/NppMacTests/NppMacTests.swift → repo root (notepad-plus-plus)
        let md = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // NppMacTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // NppMac
            .deletingLastPathComponent() // npp-macos
            .deletingLastPathComponent() // notepad-plus-plus
            .appendingPathComponent("PowerEditor/bin/userDefineLangs/markdown._preinstalled.udl.xml")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: md.path), "markdown UDL fixture missing at \(md.path)")

        let langs = try UDLXML.parse(contentsOf: md)
        XCTAssertEqual(langs.count, 1)
        let lang = try XCTUnwrap(langs.first)
        XCTAssertEqual(lang.name, "Markdown (preinstalled)")
        XCTAssertEqual(lang.ext, "md markdown")
        XCTAssertEqual(lang.udlVersion, "2.1")
        XCTAssertTrue(lang.caseIgnored)
        XCTAssertTrue(lang.prefix[0])
        XCTAssertFalse(lang.prefix[7])
        XCTAssertTrue(lang.keyword("Comments").contains("00#"))
        XCTAssertEqual(lang.commentFields[0], "#")
        XCTAssertEqual(lang.commentFields[2], "((EOL))")
        XCTAssertEqual(lang.commentFields[3], "<!--")
        XCTAssertEqual(lang.commentFields[4], "-->")
        XCTAssertFalse(lang.keyword("Operators1").isEmpty)
        XCTAssertEqual(lang.delimiterFields[0][0], "![ [")
        let d4 = try XCTUnwrap(lang.styles.first(where: { $0.name == "DELIMITERS4" }))
        XCTAssertEqual(d4.nesting, 65600)

        let xml = UDLXML.serializeSingle(lang)
        let again = try UDLXML.parse(data: Data(xml.utf8))
        XCTAssertEqual(again.count, 1)
        let rt = try XCTUnwrap(again.first)
        XCTAssertEqual(rt.name, lang.name)
        XCTAssertEqual(rt.ext, lang.ext)
        XCTAssertEqual(rt.keyword("Comments"), lang.keyword("Comments"))
        XCTAssertEqual(rt.keyword("Delimiters"), lang.keyword("Delimiters"))
        XCTAssertEqual(rt.keyword("Keywords1"), lang.keyword("Keywords1"))
        XCTAssertEqual(rt.prefix, lang.prefix)
        XCTAssertEqual(
            rt.styles.first(where: { $0.name == "DELIMITERS4" })?.nesting,
            65600
        )
    }
}
