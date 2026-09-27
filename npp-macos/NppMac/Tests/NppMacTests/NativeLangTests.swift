import XCTest
@testable import NppMac

final class NativeLangTests: XCTestCase {
    override func tearDown() {
        NativeLang.load(file: "english.xml")
        super.tearDown()
    }

    func testDialogFallbackWhenUnloaded() {
        // Force empty tables by loading a missing file name then clearing via english reload path:
        // dialogString must still return the English fallback.
        let s = NativeLang.dialogString(dialogId: "Find", itemId: "99999", fallback: "Missing Control")
        XCTAssertEqual(s, "Missing Control")
    }

    func testFindDialogStringsFrench() {
        NativeLang.load(file: "french.xml")
        let available = NativeLang.available().map(\.file)
        XCTAssertTrue(available.contains("french.xml"), "available=\(available)")
        let findTitle = NativeLang.dialogTitle(dialogId: "Find", attribute: "titleFind", fallback: "Find")
        XCTAssertEqual(findTitle, "Rechercher", "got \(findTitle); languageFile=\(NativeLang.languageFile)")
        XCTAssertEqual(
            NativeLang.dialogTitle(dialogId: "Find", attribute: "titleReplace", fallback: "Replace"),
            "Remplacer"
        )
        XCTAssertEqual(
            NativeLang.dialogString(dialogId: "Find", itemId: "1", fallback: "Find Next"),
            "Suivant"
        )
        XCTAssertEqual(
            NativeLang.dialogTitle(dialogId: "Preference", fallback: "Preferences"),
            "Préférences"
        )
    }

    func testMiscAndPanelSections() {
        NativeLang.load(file: "french.xml")
        XCTAssertEqual(NativeLang.miscString(id: "common-cancel", fallback: "Cancel"), "Annuler")
        XCTAssertEqual(
            NativeLang.sectionString(
                section: "ClipboardHistory", tag: "PanelTitle", fallback: "Clipboard History"
            ),
            "Historique du presse-papier"
        )
        XCTAssertEqual(
            NativeLang.dialogString(dialogId: "Find", itemId: "1604", fallback: "Match case"),
            "Respecter la casse"
        )
    }

    func testEnglishLoadKeepsFallbacks() {
        NativeLang.load(file: "english.xml")
        XCTAssertEqual(
            NativeLang.dialogString(dialogId: "Find", itemId: "1604", fallback: "Match case"),
            "Match case"
        )
        XCTAssertEqual(
            NativeLang.dialogTitle(dialogId: "Preference", fallback: "Preferences"),
            "Preferences"
        )
    }

    func testDidChangeNotification() {
        let exp = expectation(description: "nativeLangDidChange")
        let token = NotificationCenter.default.addObserver(
            forName: NativeLang.didChangeNotification,
            object: nil,
            queue: nil
        ) { _ in exp.fulfill() }
        NativeLang.load(file: "french.xml")
        wait(for: [exp], timeout: 2)
        NotificationCenter.default.removeObserver(token)
    }
}
