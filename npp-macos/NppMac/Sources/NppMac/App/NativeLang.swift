import Foundation

/// Loads Notepad++ `nativeLang/*.xml` for menu titles (Entries, SubEntries, Commands).
enum NativeLang {
    /// menuId / subMenuId / command id → localized name (ampersands stripped).
    private static var byKey: [String: String] = [:]
    /// Normalized English title → localized title (for items without explicit keys).
    private static var byEnglishTitle: [String: String] = [:]

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
        guard let url = resolve(file) else { return }
        let parsed = parseAll(url)
        byKey = parsed.keys

        // Build English → localized title map via command/entry ids.
        if let engURL = resolve("english.xml") {
            let eng = parseAll(engURL)
            for (id, enName) in eng.keys {
                guard let loc = parsed.keys[id], !loc.isEmpty else { continue }
                let enNorm = normalizeTitle(enName)
                let locNorm = stripAccel(loc)
                if !enNorm.isEmpty, enNorm != locNorm {
                    byEnglishTitle[enNorm] = locNorm
                }
            }
        }
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

    /// Look up localization by the English menu title used at build time.
    static func title(forEnglish english: String) -> String? {
        byEnglishTitle[normalizeTitle(english)]
    }

    // MARK: - Paths

    private static func installerNativeLangDir() -> URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // App
            .deletingLastPathComponent() // NppMac
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // NppMac
            .deletingLastPathComponent() // npp-macos
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
    }

    private static func parseAll(_ url: URL) -> Parsed {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return Parsed(keys: [:])
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

        return Parsed(keys: out)
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
