import AppKit

/// Builds the native menubar: App/File/Edit/Search/View/Encoding/Language/Help.
enum MenuBuilder {
    private static var builtMenus: [NSMenu] = []

    static func build() {
        let mainMenu = NSMenu(title: "MainMenu")
        builtMenus = []

        // Application menu (Quit / Hide / Preferences).
        let appMenu = NSMenu(title: "NppMac")
        item(appMenu, "About NppMac", #selector(MainWindowController.helpAbout(_:)), "")
        appMenu.addItem(.separator())
        item(appMenu, "Preferences…", #selector(MainWindowController.openPreferences(_:)), ",")
        appMenu.addItem(.separator())
        let hide = appMenu.addItem(withTitle: "Hide NppMac", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp
        let hideOthers = appMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        hideOthers.target = NSApp
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(withTitle: "Quit NppMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        let appItem = mainMenu.addItem(withTitle: "NppMac", action: nil, keyEquivalent: "")
        mainMenu.setSubmenu(appMenu, for: appItem)
        builtMenus.append(appMenu)

        let file = NSMenu(title: "File")
        addFile(file)
        attach(mainMenu, title: "File", menu: file)

        let edit = NSMenu(title: "Edit")
        addEdit(edit)
        attach(mainMenu, title: "Edit", menu: edit)

        let search = NSMenu(title: "Search")
        addSearch(search)
        attach(mainMenu, title: "Search", menu: search)

        let view = NSMenu(title: "View")
        addView(view)
        attach(mainMenu, title: "View", menu: view)

        let language = NSMenu(title: "Language")
        addLanguage(language)
        attach(mainMenu, title: "Language", menu: language)

        let encoding = NSMenu(title: "Encoding")
        addEncoding(encoding)
        attach(mainMenu, title: "Encoding", menu: encoding)

        let help = NSMenu(title: "Help")
        item(help, "About NppMac", #selector(MainWindowController.helpAbout(_:)), "")
        attach(mainMenu, title: "Help", menu: help)

        NSApp.mainMenu = mainMenu
    }

    private static func attach(_ main: NSMenu, title: String, menu: NSMenu) {
        let i = main.addItem(withTitle: title, action: nil, keyEquivalent: "")
        main.setSubmenu(menu, for: i)
        builtMenus.append(menu)
    }

    private static func item(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String) {
        let i = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        i.target = nil
    }

    /// Point every built item whose action the window controller implements at it.
    /// Items already targeting NSApp (Quit/Hide) and standard responder-chain actions
    /// (cut:/copy:/paste:/selectAll:, handled by whichever text field has focus) are left alone.
    static func retarget(to controller: MainWindowController) {
        for menu in builtMenus {
            for item in menu.items {
                retargetItem(item, to: controller)
            }
        }
        reloadRecentFiles(target: controller)
    }

    fileprivate static func retargetItem(_ item: NSMenuItem, to controller: MainWindowController) {
        if let action = item.action, item.target == nil, controller.responds(to: action) {
            item.target = controller
        }
        if let sub = item.submenu {
            for child in sub.items {
                retargetItem(child, to: controller)
            }
        }
    }

    private static func addFile(_ m: NSMenu) {
        item(m, "New", #selector(MainWindowController.fileNew(_:)), "n")
        item(m, "Open…", #selector(MainWindowController.fileOpen(_:)), "o")
        item(m, "Reload from Disk", #selector(MainWindowController.fileReload(_:)), "r")
        m.addItem(.separator())
        let recent = NSMenu(title: "Open Recent")
        recentMenu = recent
        populateRecent(recent)
        let recentParent = m.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "")
        m.setSubmenu(recent, for: recentParent)
        m.addItem(.separator())
        item(m, "Save", #selector(MainWindowController.fileSave(_:)), "s")
        item(m, "Save As…", #selector(MainWindowController.fileSaveAs(_:)), "S")
        let saveAll = m.addItem(withTitle: "Save All", action: #selector(MainWindowController.fileSaveAll(_:)), keyEquivalent: "s")
        saveAll.keyEquivalentModifierMask = [.command, .option]
        saveAll.target = nil
        m.addItem(.separator())
        item(m, "Close Tab", #selector(MainWindowController.fileClose(_:)), "w")
        item(m, "Close All Tabs", #selector(MainWindowController.fileCloseAll(_:)), "W")
        let closeOthers = m.addItem(
            withTitle: "Close All but Current",
            action: #selector(MainWindowController.fileCloseOthers(_:)),
            keyEquivalent: ""
        )
        closeOthers.target = nil
        m.addItem(.separator())
        item(m, "Open Containing Folder", #selector(MainWindowController.fileOpenContainingFolder(_:)), "")
        item(m, "Copy File Path", #selector(MainWindowController.fileCopyPath(_:)), "")
        item(m, "Rename…", #selector(MainWindowController.fileRename(_:)), "")
        item(m, "Delete from Disk", #selector(MainWindowController.fileDelete(_:)), "")
    }

    private static weak var recentMenu: NSMenu?

    private static func populateRecent(_ menu: NSMenu) {
        menu.removeAllItems()
        let paths = SessionStore.loadRecent()
        if paths.isEmpty {
            let empty = menu.addItem(withTitle: "(Empty)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
        } else {
            for path in paths {
                let title = (path as NSString).lastPathComponent
                let i = menu.addItem(withTitle: title, action: #selector(MainWindowController.openRecentFile(_:)), keyEquivalent: "")
                i.representedObject = path
                i.toolTip = path
                i.target = nil
            }
            menu.addItem(.separator())
            item(menu, "Clear Menu", #selector(MainWindowController.clearRecentFiles(_:)), "")
        }
    }

    /// Refresh Open Recent after opens/saves.
    static func reloadRecentFiles(target: MainWindowController) {
        guard let menu = recentMenu else { return }
        populateRecent(menu)
        for child in menu.items {
            retargetItem(child, to: target)
        }
    }

    private static func addEdit(_ m: NSMenu) {
        item(m, "Undo", #selector(MainWindowController.editUndo(_:)), "z")
        item(m, "Redo", #selector(MainWindowController.editRedo(_:)), "Z")
        m.addItem(.separator())
        item(m, "Cut", #selector(NSText.cut(_:)), "x")
        item(m, "Copy", #selector(NSText.copy(_:)), "c")
        item(m, "Paste", #selector(NSText.paste(_:)), "v")
        item(m, "Select All", #selector(NSText.selectAll(_:)), "a")
        m.addItem(.separator())
        item(m, "Duplicate Line", #selector(MainWindowController.editDuplicateLine(_:)), "d")
        item(m, "Join Lines", #selector(MainWindowController.editJoinLines(_:)), "j")
        item(m, "Move Line Up", #selector(MainWindowController.editMoveUp(_:)), "")
        item(m, "Move Line Down", #selector(MainWindowController.editMoveDown(_:)), "")
        m.addItem(.separator())
        item(m, "Toggle Line Comment", #selector(MainWindowController.editToggleComment(_:)), "/")
        item(m, "Sort Lines Ascending", #selector(MainWindowController.editSortLines(_:)), "")
        item(m, "Indent", #selector(MainWindowController.editIndent(_:)), "")
        item(m, "Unindent", #selector(MainWindowController.editUnindent(_:)), "")
        m.addItem(.separator())
        item(m, "UPPERCASE", #selector(MainWindowController.editUpperCase(_:)), "U")
        item(m, "lowercase", #selector(MainWindowController.editLowerCase(_:)), "u")
        item(m, "Trim Trailing Space", #selector(MainWindowController.editTrimTrailing(_:)), "")
    }

    private static func addSearch(_ m: NSMenu) {
        item(m, "Find…", #selector(MainWindowController.searchFind(_:)), "f")
        item(m, "Find Next", #selector(MainWindowController.searchFindNext(_:)), "g")
        item(m, "Find Previous", #selector(MainWindowController.searchFindPrev(_:)), "G")
        // ⌘H is Hide NppMac; use the macOS-standard ⌥⌘F for Replace.
        let replace = m.addItem(withTitle: "Replace…", action: #selector(MainWindowController.searchReplace(_:)), keyEquivalent: "f")
        replace.keyEquivalentModifierMask = [.command, .option]
        replace.target = nil
        item(m, "Find in Files…", #selector(MainWindowController.searchFindInFiles(_:)), "")
        m.addItem(.separator())
        item(m, "Go to Line…", #selector(MainWindowController.searchGotoLine(_:)), "")
        m.addItem(.separator())
        let bookmark = NSMenu(title: "Bookmark")
        item(bookmark, "Toggle Bookmark", #selector(MainWindowController.bookmarkToggle(_:)), "")
        item(bookmark, "Next Bookmark", #selector(MainWindowController.bookmarkNext(_:)), "")
        item(bookmark, "Previous Bookmark", #selector(MainWindowController.bookmarkPrev(_:)), "")
        item(bookmark, "Clear All Bookmarks", #selector(MainWindowController.bookmarkClearAll(_:)), "")
        let bmParent = m.addItem(withTitle: "Bookmark", action: nil, keyEquivalent: "")
        m.setSubmenu(bookmark, for: bmParent)
    }

    private static func addView(_ m: NSMenu) {
        item(m, "Word Wrap", #selector(MainWindowController.viewToggleWrap(_:)), "")
        item(m, "Show Line Numbers", #selector(MainWindowController.viewToggleLineNumbers(_:)), "")
        m.addItem(.separator())
        item(m, "Zoom In", #selector(MainWindowController.viewZoomIn(_:)), "+")
        item(m, "Zoom Out", #selector(MainWindowController.viewZoomOut(_:)), "-")
        item(m, "Restore Default Zoom", #selector(MainWindowController.viewZoomReset(_:)), "0")
        m.addItem(.separator())
        item(m, "Document Switcher", #selector(MainWindowController.viewDocSwitcher(_:)), "")
        item(m, "Toggle Status Bar", #selector(MainWindowController.viewToggleStatusBar(_:)), "")
    }

    private static func addEncoding(_ m: NSMenu) {
        item(m, "UTF-8", #selector(MainWindowController.encUtf8(_:)), "")
        item(m, "UTF-8 with BOM", #selector(MainWindowController.encUtf8Bom(_:)), "")
        item(m, "UTF-16 LE", #selector(MainWindowController.encUtf16Le(_:)), "")
        item(m, "UTF-16 BE", #selector(MainWindowController.encUtf16Be(_:)), "")
        item(m, "ANSI (Windows-1252)", #selector(MainWindowController.encAnsi(_:)), "")
        m.addItem(.separator())
        let eol = NSMenu(title: "EOL Conversion")
        item(eol, "Windows (CRLF)", #selector(MainWindowController.eolCrlf(_:)), "")
        item(eol, "Unix (LF)", #selector(MainWindowController.eolLf(_:)), "")
        item(eol, "Macintosh (CR)", #selector(MainWindowController.eolCr(_:)), "")
        let eolParent = m.addItem(withTitle: "EOL Conversion", action: nil, keyEquivalent: "")
        m.setSubmenu(eol, for: eolParent)
    }

    /// Compact Language menu: Normal text, letter submenus A–Z, Auto-detect.
    /// Populated once at build time from a temporary engine (XML catalog).
    private static func addLanguage(_ m: NSMenu) {
        item(m, "None (Normal text)", #selector(MainWindowController.langSelect(_:)), "")
        if let none = m.items.last {
            none.representedObject = "normal"
        }
        m.addItem(.separator())

        let langs = NppEngine(langsModel: Bundle.main.url(forResource: "langs.model", withExtension: "xml")?.path)
            .languages()
            .filter { $0.key != "normal" }

        // Top-level specials matching Notepad++ compact menu quirks.
        let topLevelKeys: Set<String> = ["kix", "xml", "yaml"]
        let topLevel = langs.filter { topLevelKeys.contains($0.key) }
        let submenuLangs = langs.filter { !topLevelKeys.contains($0.key) }

        var submenuByLetter: [Character: [(key: String, display: String)]] = [:]
        for lang in submenuLangs {
            let letter = lang.display.first.map { ch -> Character in
                String(ch).uppercased().first ?? "#"
            } ?? "#"
            let key: Character = letter.isLetter ? letter : "#"
            submenuByLetter[key, default: []].append(lang)
        }

        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            guard let items = submenuByLetter[letter], !items.isEmpty else { continue }
            let sub = NSMenu(title: String(letter))
            for lang in items.sorted(by: { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }) {
                let i = sub.addItem(
                    withTitle: lang.display,
                    action: #selector(MainWindowController.langSelect(_:)),
                    keyEquivalent: ""
                )
                i.target = nil
                i.representedObject = lang.key
            }
            let parent = m.addItem(withTitle: String(letter), action: nil, keyEquivalent: "")
            m.setSubmenu(sub, for: parent)
        }

        if !topLevel.isEmpty {
            m.addItem(.separator())
            for lang in topLevel.sorted(by: { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }) {
                let i = m.addItem(
                    withTitle: lang.display,
                    action: #selector(MainWindowController.langSelect(_:)),
                    keyEquivalent: ""
                )
                i.target = nil
                i.representedObject = lang.key
            }
        }

        m.addItem(.separator())
        item(m, "Auto-detect by Extension", #selector(MainWindowController.langAuto(_:)), "")
    }
}
