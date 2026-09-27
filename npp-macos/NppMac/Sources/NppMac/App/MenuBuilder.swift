import AppKit

/// Builds the native menubar: App/File/Edit/Search/View/Encoding/Language/Help.
enum MenuBuilder {
    private static var builtMenus: [NSMenu] = []
    /// Language → User-defined submenu (rebuilt after UDL load/save).
    private static var userDefinedMenu: NSMenu?

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

        let settings = NSMenu(title: "Settings")
        item(settings, "Preferences…", #selector(MainWindowController.openPreferences(_:)), ",")
        item(settings, "Style Configurator…", #selector(MainWindowController.openStyleConfigurator(_:)), "")
        item(settings, "Shortcut Mapper…", #selector(MainWindowController.openShortcutMapper(_:)), "")
        settings.addItem(.separator())
        let theme = NSMenu(title: "Theme")
        item(theme, "Default (stylers.model)", #selector(MainWindowController.themeSelect(_:)), "")
        if let none = theme.items.last { none.representedObject = "" }
        for name in Self.bundledThemeNames() {
            let i = theme.addItem(withTitle: name, action: #selector(MainWindowController.themeSelect(_:)), keyEquivalent: "")
            i.representedObject = name + ".xml"
            i.target = nil
        }
        let themeParent = settings.addItem(withTitle: "Theme", action: nil, keyEquivalent: "")
        settings.setSubmenu(theme, for: themeParent)
        settings.addItem(.separator())
        let appear = NSMenu(title: "Appearance")
        item(appear, "System", #selector(MainWindowController.appearanceSelect(_:)), "")
        if let i = appear.items.last { i.representedObject = "system" }
        item(appear, "Light", #selector(MainWindowController.appearanceSelect(_:)), "")
        if let i = appear.items.last { i.representedObject = "light" }
        item(appear, "Dark", #selector(MainWindowController.appearanceSelect(_:)), "")
        if let i = appear.items.last { i.representedObject = "dark" }
        let appearParent = settings.addItem(withTitle: "Appearance", action: nil, keyEquivalent: "")
        settings.setSubmenu(appear, for: appearParent)
        settings.addItem(.separator())
        let uiLang = NSMenu(title: "UI Language")
        for lang in NativeLang.available() {
            let i = uiLang.addItem(
                withTitle: lang.name,
                action: #selector(MainWindowController.uiLanguageSelect(_:)),
                keyEquivalent: ""
            )
            i.representedObject = lang.file
            i.target = nil
        }
        let uiParent = settings.addItem(withTitle: "UI Language", action: nil, keyEquivalent: "")
        settings.setSubmenu(uiLang, for: uiParent)
        attach(mainMenu, title: "Settings", menu: settings)

        let tools = NSMenu(title: "Tools")
        item(tools, "MD5 of Current File…", #selector(MainWindowController.toolsMD5(_:)), "")
        item(tools, "SHA-256 of Current File…", #selector(MainWindowController.toolsSHA256(_:)), "")
        item(tools, "MD5 of Selection…", #selector(MainWindowController.toolsMD5Selection(_:)), "")
        item(tools, "SHA-256 of Selection…", #selector(MainWindowController.toolsSHA256Selection(_:)), "")
        attach(mainMenu, title: "Tools", menu: tools)

        let macro = NSMenu(title: "Macro")
        item(macro, "Start Recording", #selector(MainWindowController.macroStartRecording(_:)), "")
        item(macro, "Stop Recording", #selector(MainWindowController.macroStopRecording(_:)), "")
        item(macro, "Playback", #selector(MainWindowController.macroPlayback(_:)), "")
        macro.addItem(.separator())
        item(macro, "Save Current Macro…", #selector(MainWindowController.macroSave(_:)), "")
        attach(mainMenu, title: "Macro", menu: macro)

        let plugins = NSMenu(title: "Plugins")
        pluginsMenu = plugins
        populatePlugins(plugins)
        attach(mainMenu, title: "Plugins", menu: plugins)

        let run = NSMenu(title: "Run")
        item(run, "Run…", #selector(MainWindowController.runCommand(_:)), "")
        attach(mainMenu, title: "Run", menu: run)

        let windowMenu = NSMenu(title: "Window")
        item(windowMenu, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        item(windowMenu, "Zoom", #selector(NSWindow.performZoom(_:)), "")
        windowMenu.addItem(.separator())
        item(windowMenu, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), "")
        attach(mainMenu, title: "Window", menu: windowMenu)

        let help = NSMenu(title: "Help")
        item(help, "About NppMac", #selector(MainWindowController.helpAbout(_:)), "")
        attach(mainMenu, title: "Help", menu: help)

        NSApp.mainMenu = mainMenu
    }

    private static func attach(_ main: NSMenu, title: String, menu: NSMenu) {
        let i = main.addItem(withTitle: title, action: nil, keyEquivalent: "")
        i.identifier = NSUserInterfaceItemIdentifier("en:\(title)")
        main.setSubmenu(menu, for: i)
        builtMenus.append(menu)
    }

    private static func item(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String) {
        let i = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        i.target = nil
        // Preserve English title for nativeLang re-application.
        i.identifier = NSUserInterfaceItemIdentifier("en:\(title)")
    }

    /// Theme basenames bundled under Resources/themes (without `.xml`).
    static func bundledThemeNames() -> [String] {
        var names: [String] = []
        if let urls = Bundle.main.urls(forResourcesWithExtension: "xml", subdirectory: "themes") {
            names = urls.map { $0.deletingPathExtension().lastPathComponent }
        }
        // Dev fallback: PowerEditor installer themes next to the repo.
        if names.isEmpty {
            let dev = URL(fileURLWithPath: #file)
                .deletingLastPathComponent() // App
                .deletingLastPathComponent() // NppMac
                .deletingLastPathComponent() // Sources
                .deletingLastPathComponent() // NppMac
                .deletingLastPathComponent() // npp-macos
                .appendingPathComponent("PowerEditor/installer/themes")
            if let urls = try? FileManager.default.contentsOfDirectory(at: dev, includingPropertiesForKeys: nil) {
                names = urls.filter { $0.pathExtension == "xml" }.map { $0.deletingPathExtension().lastPathComponent }
            }
        }
        return names.sorted()
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
        reloadPlugins(target: controller)
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
        saveAll.identifier = NSUserInterfaceItemIdentifier("en:Save All")
        m.addItem(.separator())
        item(m, "Close Tab", #selector(MainWindowController.fileClose(_:)), "w")
        item(m, "Close All Tabs", #selector(MainWindowController.fileCloseAll(_:)), "W")
        let closeOthers = m.addItem(
            withTitle: "Close All but Current",
            action: #selector(MainWindowController.fileCloseOthers(_:)),
            keyEquivalent: ""
        )
        closeOthers.target = nil
        closeOthers.identifier = NSUserInterfaceItemIdentifier("en:Close All but Current")
        m.addItem(.separator())
        item(m, "Open Containing Folder", #selector(MainWindowController.fileOpenContainingFolder(_:)), "")
        item(m, "Copy File Path", #selector(MainWindowController.fileCopyPath(_:)), "")
        item(m, "Rename…", #selector(MainWindowController.fileRename(_:)), "")
        item(m, "Delete from Disk", #selector(MainWindowController.fileDelete(_:)), "")
        m.addItem(.separator())
        item(m, "Print…", #selector(MainWindowController.filePrint(_:)), "p")
    }

    private static weak var recentMenu: NSMenu?
    private static weak var pluginsMenu: NSMenu?

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

    private static func populatePlugins(_ menu: NSMenu) {
        menu.removeAllItems()
        item(menu, "Open Plugins Folder…", #selector(MainWindowController.pluginsOpenFolder(_:)), "")
        item(menu, "Refresh Plugin List", #selector(MainWindowController.pluginsRefresh(_:)), "")
        menu.addItem(.separator())

        PluginRuntime.shared.reload()
        let plugins = PluginRuntime.shared.loaded
        if plugins.isEmpty {
            let empty = menu.addItem(withTitle: "(No plugins found)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            return
        }
        for plugin in plugins {
            let parent = menu.addItem(withTitle: plugin.displayName, action: nil, keyEquivalent: "")
            parent.toolTip = plugin.path.path
            if plugin.commands.isEmpty {
                // Loaded but no FuncItemUTF8 exports — show path info.
                parent.action = #selector(MainWindowController.pluginsInvoke(_:))
                parent.representedObject = plugin.path
                parent.target = nil
                continue
            }
            let sub = NSMenu(title: plugin.displayName)
            for cmd in plugin.commands {
                let i = sub.addItem(
                    withTitle: cmd.title,
                    action: #selector(PluginCommandTarget.run(_:)),
                    keyEquivalent: ""
                )
                i.target = cmd
            }
            menu.setSubmenu(sub, for: parent)
        }
    }

    /// Apply nativeLang titles (top-level Entries + Commands matched by English title).
    static func applyNativeLangTitles() {
        guard let main = NSApp.mainMenu else { return }
        let topMap: [String: String] = [
            "File": "file",
            "Edit": "edit",
            "Search": "search",
            "View": "view",
            "Encoding": "encoding",
            "Language": "language",
            "Settings": "settings",
            "Tools": "tools",
            "Macro": "macro",
            "Run": "run",
            "Plugins": "Plugins",
            "Window": "Window",
            "Help": "help",
        ]
        for item in main.items {
            let english: String
            if let id = item.identifier?.rawValue, id.hasPrefix("en:") {
                english = String(id.dropFirst(3))
            } else {
                english = item.title
            }
            if let mid = topMap[english] {
                item.title = NativeLang.menuTitle(id: mid, fallback: english)
                item.identifier = NSUserInterfaceItemIdentifier("en:\(english)")
            }
            if let sub = item.submenu {
                applyNativeLangRecursive(sub)
            }
        }
    }

    private static func applyNativeLangRecursive(_ menu: NSMenu) {
        for item in menu.items {
            if item.isSeparatorItem { continue }
            let english: String
            if let id = item.identifier?.rawValue, id.hasPrefix("en:") {
                english = String(id.dropFirst(3))
            } else {
                english = item.title
                item.identifier = NSUserInterfaceItemIdentifier("en:\(english)")
            }
            if let loc = NativeLang.title(forEnglish: english) {
                item.title = loc
            }
            if let sub = item.submenu {
                applyNativeLangRecursive(sub)
            }
        }
    }

    static func reloadPlugins(target: MainWindowController) {
        guard let menu = pluginsMenu else { return }
        populatePlugins(menu)
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
        item(m, "Insert Date/Time", #selector(MainWindowController.editInsertDateTime(_:)), "")
        item(m, "Character Panel…", #selector(MainWindowController.editCharacterPanel(_:)), "")
        m.addItem(.separator())
        item(m, "Column Mode", #selector(MainWindowController.editToggleColumnMode(_:)), "")
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
        replace.identifier = NSUserInterfaceItemIdentifier("en:Replace…")
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
        item(m, "Show Whitespace", #selector(MainWindowController.viewToggleWhitespace(_:)), "")
        m.addItem(.separator())
        item(m, "Folder as Workspace", #selector(MainWindowController.viewToggleFolder(_:)), "")
        item(m, "Function List", #selector(MainWindowController.viewToggleFunctionList(_:)), "")
        item(m, "Document Map", #selector(MainWindowController.viewToggleDocumentMap(_:)), "")
        item(m, "Clipboard History", #selector(MainWindowController.viewToggleClipboardHistory(_:)), "")
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

        let userDef = NSMenu(title: "User-defined")
        userDefinedMenu = userDef
        rebuildUserDefinedSubmenu(names: UDLStore.shared.names)
        let udParent = m.addItem(withTitle: "User-defined", action: nil, keyEquivalent: "")
        udParent.identifier = NSUserInterfaceItemIdentifier("en:User-defined")
        m.setSubmenu(userDef, for: udParent)

        item(m, "User-Defined Language…", #selector(MainWindowController.openUDLEditor(_:)), "")
        item(m, "Load UDL…", #selector(MainWindowController.langLoadUDL(_:)), "")
        item(m, "Open userDefineLangs Folder…", #selector(MainWindowController.openUserDefineLangsFolder(_:)), "")
        item(m, "Auto-detect by Extension", #selector(MainWindowController.langAuto(_:)), "")
    }

    /// Rebuild Language → User-defined from loaded UDL display names.
    /// Items use `udl_*` engine keys as `representedObject` when available from the store model.
    static func rebuildUserDefinedSubmenu(names: [String]) {
        let menu = userDefinedMenu ?? {
            let m = NSMenu(title: "User-defined")
            userDefinedMenu = m
            return m
        }()
        menu.removeAllItems()
        if names.isEmpty {
            let empty = menu.addItem(withTitle: "(none)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            return
        }
        for name in names.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            let key = UDLStore.shared.language(named: name)?.engineKey ?? name
            let i = menu.addItem(
                withTitle: name,
                action: #selector(MainWindowController.langSelect(_:)),
                keyEquivalent: ""
            )
            i.target = nil
            i.representedObject = key
        }
    }
}
