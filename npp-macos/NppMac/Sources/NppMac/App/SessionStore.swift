import Foundation

/// Persist open tabs (`session.xml`) and recent files under Application Support/NppMac.
enum SessionStore {
    private static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("NppMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var sessionURL: URL { supportDir.appendingPathComponent("session.xml") }
    static var recentURL: URL { supportDir.appendingPathComponent("recent.txt") }
    static var configURL: URL { supportDir.appendingPathComponent("config.xml") }

    /// Persist AppPrefs into a minimal Notepad++-style `config.xml`.
    static func saveConfig() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" ?>
        <NotepadPlus>
            <GUIConfig>
                <WordWrap>\(AppPrefs.wordWrapDefault ? 1 : 0)</WordWrap>
                <LineNumbers>\(AppPrefs.showLineNumbers ? 1 : 0)</LineNumbers>
                <BackupOnSave>\(AppPrefs.backupOnSave ? 1 : 0)</BackupOnSave>
                <RestoreSession>\(AppPrefs.restoreSession ? 1 : 0)</RestoreSession>
                <WatchDisk>\(AppPrefs.watchDiskChanges ? 1 : 0)</WatchDisk>
                <TabWidth>\(AppPrefs.tabWidth)</TabWidth>
                <FifFilters>\(xmlEscape(AppPrefs.fifFilters))</FifFilters>
                <FifExcludes>\(xmlEscape(AppPrefs.fifExcludes))</FifExcludes>
                <Appearance>\(xmlEscape(AppPrefs.appearance))</Appearance>
                <ShowWhitespace>\(AppPrefs.showWhitespace ? 1 : 0)</ShowWhitespace>
                <Theme>\(xmlEscape(AppPrefs.themeName))</Theme>
            </GUIConfig>
        </NotepadPlus>
        """
        try? xml.write(to: configURL, atomically: true, encoding: .utf8)
    }

    /// Load AppPrefs from `config.xml` if present.
    static func loadConfig() {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return }
        if let v = intTag("WordWrap", in: text) { AppPrefs.wordWrapDefault = v != 0 }
        if let v = intTag("LineNumbers", in: text) { AppPrefs.showLineNumbers = v != 0 }
        if let v = intTag("BackupOnSave", in: text) { AppPrefs.backupOnSave = v != 0 }
        if let v = intTag("RestoreSession", in: text) { AppPrefs.restoreSession = v != 0 }
        if let v = intTag("WatchDisk", in: text) { AppPrefs.watchDiskChanges = v != 0 }
        if let v = intTag("TabWidth", in: text), v > 0, v < 32 { AppPrefs.tabWidth = v }
        if let s = stringTag("FifFilters", in: text) { AppPrefs.fifFilters = xmlUnescape(s) }
        if let s = stringTag("FifExcludes", in: text) { AppPrefs.fifExcludes = xmlUnescape(s) }
        if let s = stringTag("Appearance", in: text) { AppPrefs.appearance = s }
        if let v = intTag("ShowWhitespace", in: text) { AppPrefs.showWhitespace = v != 0 }
        if let s = stringTag("Theme", in: text) { AppPrefs.themeName = xmlUnescape(s) }
    }

    private static func intTag(_ name: String, in text: String) -> Int? {
        stringTag(name, in: text).flatMap(Int.init)
    }

    private static func stringTag(_ name: String, in text: String) -> String? {
        let pattern = "<\(name)>([\\s\\S]*?)</\(name)>"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        else { return nil }
        return (text as NSString).substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func xmlUnescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    static func saveSession(paths: [String]) {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<NotepadPlus>\n<Session>\n"
        for path in paths {
            let escaped = path
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
            xml += "<File filename=\"\(escaped)\" view=\"0\" />\n"
        }
        xml += "</Session>\n</NotepadPlus>\n"
        try? xml.write(to: sessionURL, atomically: true, encoding: .utf8)
    }

    static func loadSession() -> [String] {
        guard let text = try? String(contentsOf: sessionURL, encoding: .utf8) else { return [] }
        var paths: [String] = []
        // Minimal parse: filename="..."
        let pattern = #"filename="([^"]+)""#
        if let re = try? NSRegularExpression(pattern: pattern) {
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let raw = ns.substring(with: m.range(at: 1))
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&amp;", with: "&")
                if FileManager.default.fileExists(atPath: raw) {
                    paths.append(raw)
                }
            }
        }
        return paths
    }

    static func pushRecent(_ path: String) {
        var items = loadRecent()
        items.removeAll { $0 == path }
        items.insert(path, at: 0)
        if items.count > 10 { items = Array(items.prefix(10)) }
        let body = items.joined(separator: "\n") + "\n"
        try? body.write(to: recentURL, atomically: true, encoding: .utf8)
    }

    static func loadRecent() -> [String] {
        guard let text = try? String(contentsOf: recentURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init).filter {
            !$0.isEmpty && FileManager.default.fileExists(atPath: $0)
        }
    }
}
