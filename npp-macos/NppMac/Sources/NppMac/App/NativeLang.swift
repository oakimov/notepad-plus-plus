import Foundation

/// Loads Notepad++ `nativeLang/*.xml` Menu → Main → Entries for top-level menu titles.
enum NativeLang {
    private static var strings: [String: String] = [:]

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
        let dev = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // App
            .deletingLastPathComponent() // NppMac
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // NppMac
            .deletingLastPathComponent() // npp-macos
            .appendingPathComponent("PowerEditor/installer/nativeLang")
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
        strings = [:]
        guard let url = resolve(file) else { return }
        strings = parseEntries(url)
    }

    static func loadCurrent() {
        load(file: languageFile)
    }

    /// Localized top-level menu title for `menuId` (file/edit/…); falls back to `fallback`.
    static func menuTitle(id: String, fallback: String) -> String {
        if let s = strings[id], !s.isEmpty {
            return s.replacingOccurrences(of: "&", with: "")
        }
        return fallback
    }

    private static func resolve(_ file: String) -> URL? {
        let base = (file as NSString).deletingPathExtension
        if let u = Bundle.main.url(forResource: base, withExtension: "xml", subdirectory: "nativeLang") {
            return u
        }
        let dev = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PowerEditor/installer/nativeLang")
            .appendingPathComponent(file.hasSuffix(".xml") ? file : file + ".xml")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    private static func displayName(in url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // <Native-Langue name="French" ...>
        let pattern = #"Native-Langue[^>]*name="([^"]+)""#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        else { return nil }
        return (text as NSString).substring(with: m.range(at: 1))
    }

    private static func parseEntries(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        // Only Main Entries: menuId="file" name="..."
        let pattern = #"menuId="([^"]+)"\s+name="([^"]*)""#
        if let re = try? NSRegularExpression(pattern: pattern) {
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let id = ns.substring(with: m.range(at: 1))
                let name = ns.substring(with: m.range(at: 2))
                out[id] = name
            }
        }
        return out
    }
}
