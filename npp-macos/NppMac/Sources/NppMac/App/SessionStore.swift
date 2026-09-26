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
