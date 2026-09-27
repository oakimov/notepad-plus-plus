import Foundation

/// Loads Notepad++ `nativeLang/*.xml` for menus, dialogs, panels, and MiscStrings.
enum NativeLang {
    /// Posted after `load(file:)` finishes (menus/dialogs should re-apply titles).
    static let didChangeNotification = Notification.Name("nppNativeLangDidChange")

    /// menuId / subMenuId / command id → localized name (ampersands stripped).
    private static var byKey: [String: String] = [:]
    /// Normalized English title → localized title (menus + dialogs).
    private static var byEnglishTitle: [String: String] = [:]
    /// `DialogTag/itemId` → name (e.g. `Find/1604`).
    private static var byDialogItem: [String: String] = [:]
    /// `DialogTag@attr` → value (e.g. `Find@titleFind`, `Preference@title`).
    private static var byDialogAttr: [String: String] = [:]
    /// `Section/Tag` → name or value (e.g. `ClipboardHistory/PanelTitle`, `MiscStrings/common-ok`).
    private static var bySection: [String: String] = [:]

    static var languageFile: String {
        get { UserDefaults.standard.string(forKey: "nativeLangFile") ?? "english.xml" }
        set { UserDefaults.standard.set(newValue, forKey: "nativeLangFile") }
    }

    /// Available language files (bundled or from PowerEditor/installer/nativeLang).
    static func available() -> [(file: String, name: String)] {
        var files: [URL] = []
        if let urls = Bundle.main.urls(forResourcesWithExtension: "xml", subdirectory: "nativeLang") {
            files.append(contentsOf: urls)
        }
        let dev = installerNativeLangDir()
        if let urls = try? FileManager.default.contentsOfDirectory(at: dev, includingPropertiesForKeys: nil) {
            files.append(contentsOf: urls.filter { $0.pathExtension == "xml" })
        }
        var seen = Set<String>()
        var out: [(String, String)] = []
        for u in files {
            let file = u.lastPathComponent
            guard seen.insert(file).inserted else { continue }
            let display = displayName(in: u) ?? u.deletingPathExtension().lastPathComponent
            out.append((file, display))
        }
        return out.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    static func load(file: String) {
        languageFile = file
        byKey = [:]
        byEnglishTitle = [:]
        byDialogItem = [:]
        byDialogAttr = [:]
        bySection = [:]
        guard let url = resolve(file) else {
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
            return
        }
        let parsed = parseAll(url)
        byKey = parsed.keys
        byDialogItem = parsed.dialogItems
        byDialogAttr = parsed.dialogAttrs
        bySection = parsed.sections

        // Build English → localized title map via command/entry ids and dialog items.
        if let engURL = resolve("english.xml") {
            let eng = parseAll(engURL)
            for (id, enName) in eng.keys {
                guard let loc = parsed.keys[id], !loc.isEmpty else { continue }
                mapEnglish(enName, to: loc)
            }
            for (key, enName) in eng.dialogItems {
                guard let loc = parsed.dialogItems[key], !loc.isEmpty else { continue }
                mapEnglish(enName, to: loc)
            }
            for (key, enName) in eng.dialogAttrs {
                guard let loc = parsed.dialogAttrs[key], !loc.isEmpty else { continue }
                mapEnglish(enName, to: loc)
            }
            for (key, enName) in eng.sections {
                guard let loc = parsed.sections[key], !loc.isEmpty else { continue }
                mapEnglish(enName, to: loc)
            }
        }

        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func loadCurrent() {
        load(file: languageFile)
    }

    /// Localized top-level / submenu title for `menuId` or `subMenuId`.
    static func menuTitle(id: String, fallback: String) -> String {
        if let s = byKey[id], !s.isEmpty {
            return stripAccel(s)
        }
        return fallback
    }

    /// Localized command title for a Notepad++ `id` attribute (e.g. `"41001"`).
    static func commandTitle(id: String, fallback: String) -> String {
        if let s = byKey[id], !s.isEmpty {
            return stripAccel(s)
        }
        return fallback
    }

    /// Look up localization by the English menu/dialog title used at build time.
    static func title(forEnglish english: String) -> String? {
        byEnglishTitle[normalizeTitle(english)]
    }

    /// Localized dialog control string for `<Dialog><Tag><Item id=… name=…/>`.
    static func dialogString(dialogId: String, itemId: String, fallback: String) -> String {
        let key = "\(dialogId)/\(itemId)"
        if let s = byDialogItem[key], !s.isEmpty {
            return stripAccel(s)
        }
        if let s = title(forEnglish: fallback) { return s }
        return fallback
    }

    /// Localized dialog attribute (`title`, `titleFind`, …) on a Dialog child element.
    static func dialogTitle(dialogId: String, attribute: String = "title", fallback: String) -> String {
        let key = "\(dialogId)@\(attribute)"
        if let s = byDialogAttr[key], !s.isEmpty {
            return stripAccel(s)
        }
        if let s = title(forEnglish: fallback) { return s }
        return fallback
    }

    /// Localized panel/section tag (`ClipboardHistory/PanelTitle`, …).
    static func sectionString(section: String, tag: String, fallback: String) -> String {
        let key = "\(section)/\(tag)"
        if let s = bySection[key], !s.isEmpty {
            return stripAccel(s)
        }
        if let s = title(forEnglish: fallback) { return s }
        return fallback
    }

    /// Localized MiscStrings value (`common-ok`, …).
    static func miscString(id: String, fallback: String) -> String {
        sectionString(section: "MiscStrings", tag: id, fallback: fallback)
    }

    // MARK: - Paths

    private static func installerNativeLangDir() -> URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // App
            .deletingLastPathComponent() // NppMac
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // NppMac (package)
            .deletingLastPathComponent() // npp-macos
            .deletingLastPathComponent() // notepad-plus-plus
            .appendingPathComponent("PowerEditor/installer/nativeLang")
    }

    private static func resolve(_ file: String) -> URL? {
        let base = (file as NSString).deletingPathExtension
        if let u = Bundle.main.url(forResource: base, withExtension: "xml", subdirectory: "nativeLang") {
            return u
        }
        let name = file.hasSuffix(".xml") ? file : file + ".xml"
        let dev = installerNativeLangDir().appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    private static func displayName(in url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let pattern = #"Native-Langue[^>]*name="([^"]+)""#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        else { return nil }
        return (text as NSString).substring(with: m.range(at: 1))
    }

    // MARK: - Parse

    private struct Parsed {
        var keys: [String: String]
        var dialogItems: [String: String]
        var dialogAttrs: [String: String]
        var sections: [String: String]
    }

    private static func parseAll(_ url: URL) -> Parsed {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return Parsed(keys: [:], dialogItems: [:], dialogAttrs: [:], sections: [:])
        }
        var out: [String: String] = [:]
        let ns = text as NSString
        let len = NSRange(location: 0, length: ns.length)

        func scan(_ pattern: String, idGroup: Int = 1, nameGroup: Int = 2) {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return }
            for m in re.matches(in: text, range: len) {
                let id = ns.substring(with: m.range(at: idGroup))
                let name = decodeXML(ns.substring(with: m.range(at: nameGroup)))
                if !id.isEmpty { out[id] = name }
            }
        }

        // Entries: menuId="file" name="..."
        scan(#"menuId="([^"]+)"\s+name="([^"]*)""#)
        // SubEntries: subMenuId="file-openFolder" name="..."
        scan(#"subMenuId="([^"]+)"\s+name="([^"]*)""#)
        // Commands: id="41001" name="..."
        scan(#"<Item\s+id="([^"]+)"\s+name="([^"]*)""#)
        // Alternate attribute order: name then id
        scan(#"<Item\s+name="([^"]*)"\s+id="([^"]+)""#, idGroup: 2, nameGroup: 1)

        let dialogs = parseDialogSection(text)
        let sections = parseNamedSections(text)

        return Parsed(
            keys: out,
            dialogItems: dialogs.items,
            dialogAttrs: dialogs.attrs,
            sections: sections
        )
    }

    /// Parse `<Dialog>…</Dialog>`: nested tags, Item ids, and title* attributes.
    private static func parseDialogSection(_ text: String) -> (items: [String: String], attrs: [String: String]) {
        guard let body = extractElementBody(text, tag: "Dialog") else {
            return ([:], [:])
        }
        var items: [String: String] = [:]
        var attrs: [String: String] = [:]
        var stack: [String] = []

        // Match start tags, end tags, and Items. Skip comments.
        let pattern = #"(?:<!--[\s\S]*?-->)|(?:</([A-Za-z_][\w.]*)\s*>)|(?:<([A-Za-z_][\w.]*)((?:\s+[^>]*?)?)\s*(/?)>)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return ([:], [:]) }
        let ns = body as NSString
        let len = NSRange(location: 0, length: ns.length)

        for m in re.matches(in: body, range: len) {
            // Comment match: only group 0
            if m.range(at: 1).location == NSNotFound, m.range(at: 2).location == NSNotFound {
                continue
            }
            // End tag
            if m.range(at: 1).location != NSNotFound {
                let name = ns.substring(with: m.range(at: 1))
                if stack.last == name { stack.removeLast() }
                continue
            }
            // Start / empty tag
            let tag = ns.substring(with: m.range(at: 2))
            let attrStr = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)) : ""
            let selfClosing = m.range(at: 4).location != NSNotFound && ns.substring(with: m.range(at: 4)) == "/"

            if tag == "Item" {
                if let id = attrValue(attrStr, "id"),
                   let name = attrValue(attrStr, "name"),
                   let owner = stack.last
                {
                    items["\(owner)/\(id)"] = decodeXML(name)
                }
                continue
            }

            // Record title* attributes on dialog/subdialog elements.
            if !stack.isEmpty || tag != "Menu" {
                for attr in ["title", "titleFind", "titleReplace", "titleFindInFiles", "titleFindInProjects", "titleMark", "title2", "title3", "title4"] {
                    if let v = attrValue(attrStr, attr), !v.isEmpty {
                        attrs["\(tag)@\(attr)"] = decodeXML(v)
                    }
                }
                // Named child tags under a dialog (e.g. ShortcutMapper ColumnName name="…").
                if let name = attrValue(attrStr, "name"), !name.isEmpty, let owner = stack.last {
                    attrs["\(owner)/\(tag)"] = decodeXML(name)
                }
            }

            if !selfClosing, tag != "Item", tag != "Element" {
                stack.append(tag)
            }
        }
        return (items, attrs)
    }

    /// Panel sections + MiscStrings: `<ClipboardHistory><PanelTitle name="…"/>`, `<common-ok value="…"/>`.
    private static func parseNamedSections(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        let sectionTags = [
            "ClipboardHistory", "DocList", "WindowsDlg", "AsciiInsertion",
            "DocumentMap", "FunctionList", "FolderAsWorkspace", "ProjectManager",
            "MiscStrings",
        ]
        for section in sectionTags {
            guard let body = extractElementBody(text, tag: section) else { continue }
            let ns = body as NSString
            let len = NSRange(location: 0, length: ns.length)

            // <TagName name="…"/> or <TagName value="…"/>
            let pattern = #"<([A-Za-z_][\w.-]*)((?:\s+[^>]*?)?)\s*/?>"#
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            for m in re.matches(in: body, range: len) {
                let tag = ns.substring(with: m.range(at: 1))
                let attrStr = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : ""
                if let name = attrValue(attrStr, "name") {
                    out["\(section)/\(tag)"] = decodeXML(name)
                } else if let value = attrValue(attrStr, "value") {
                    out["\(section)/\(tag)"] = decodeXML(value)
                }
            }

            // Nested Menu Items under FolderAsWorkspace etc.
            let itemPat = #"<Item\s+id="([^"]+)"\s+name="([^"]*)""#
            if let itemRe = try? NSRegularExpression(pattern: itemPat) {
                for m in itemRe.matches(in: body, range: len) {
                    let id = ns.substring(with: m.range(at: 1))
                    let name = decodeXML(ns.substring(with: m.range(at: 2)))
                    out["\(section)/\(id)"] = name
                }
            }
        }
        return out
    }

    private static func extractElementBody(_ text: String, tag: String) -> String? {
        let open = "<\(tag)"
        guard let openRange = text.range(of: open) else { return nil }
        // Find end of opening tag
        guard let gt = text[openRange.upperBound...].firstIndex(of: ">") else { return nil }
        let afterOpen = text.index(after: gt)
        let close = "</\(tag)>"
        guard let closeRange = text.range(of: close, range: afterOpen..<text.endIndex) else { return nil }
        return String(text[afterOpen..<closeRange.lowerBound])
    }

    private static func attrValue(_ attrs: String, _ name: String) -> String? {
        let pattern = #"\#(name)="([^"]*)""#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: attrs, range: NSRange(location: 0, length: (attrs as NSString).length))
        else { return nil }
        return (attrs as NSString).substring(with: m.range(at: 1))
    }

    private static func mapEnglish(_ enName: String, to loc: String) {
        let enNorm = normalizeTitle(enName)
        let locNorm = stripAccel(loc)
        if !enNorm.isEmpty, enNorm != locNorm {
            byEnglishTitle[enNorm] = locNorm
        }
    }

    private static func decodeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }

    private static func stripAccel(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "")
    }

    /// Normalize for English→localized matching (strip accel, unify ellipsis).
    static func normalizeTitle(_ s: String) -> String {
        stripAccel(s)
            .replacingOccurrences(of: "...", with: "…")
            .trimmingCharacters(in: .whitespaces)
    }
}
