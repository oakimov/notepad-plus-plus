import AppKit
import Foundation

/// User preferences persisted via UserDefaults (NppMac domain).
enum AppPrefs {
    private static let defaults = UserDefaults.standard

    static var wordWrapDefault: Bool {
        get { defaults.bool(forKey: "wordWrapDefault") }
        set { defaults.set(newValue, forKey: "wordWrapDefault") }
    }

    static var showLineNumbers: Bool {
        get { defaults.object(forKey: "showLineNumbers") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showLineNumbers") }
    }

    static var backupOnSave: Bool {
        get { defaults.bool(forKey: "backupOnSave") }
        set { defaults.set(newValue, forKey: "backupOnSave") }
    }

    static var restoreSession: Bool {
        get { defaults.object(forKey: "restoreSession") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "restoreSession") }
    }

    static var watchDiskChanges: Bool {
        get { defaults.object(forKey: "watchDiskChanges") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "watchDiskChanges") }
    }

    static var tabWidth: Int {
        get {
            let v = defaults.integer(forKey: "tabWidth")
            return v > 0 ? v : 4
        }
        set { defaults.set(newValue, forKey: "tabWidth") }
    }

    /// Find-in-Files include globs, e.g. `*.swift;*.rs;*.md` (empty = all text files).
    static var fifFilters: String {
        get {
            defaults.string(forKey: "fifFilters")
                ?? "*.swift;*.rs;*.py;*.js;*.ts;*.go;*.c;*.h;*.cpp;*.hpp;*.java;*.cs;*.rb;*.php;*.md;*.txt;*.xml;*.json;*.yml;*.yaml;*.toml;*.sh"
        }
        set { defaults.set(newValue, forKey: "fifFilters") }
    }

    /// Directory name fragments to skip, e.g. `node_modules;.git;target;build`.
    static var fifExcludes: String {
        get {
            defaults.string(forKey: "fifExcludes")
                ?? "node_modules;.git;target;build;Dist;dist;.build;DerivedData"
        }
        set { defaults.set(newValue, forKey: "fifExcludes") }
    }

    /// `system` | `light` | `dark`
    static var appearance: String {
        get { defaults.string(forKey: "appearance") ?? "system" }
        set { defaults.set(newValue, forKey: "appearance") }
    }

    static var showWhitespace: Bool {
        get { defaults.bool(forKey: "showWhitespace") }
        set { defaults.set(newValue, forKey: "showWhitespace") }
    }

    /// Active theme file name (e.g. `Monokai.xml`), empty = stock stylers.
    static var themeName: String {
        get { defaults.string(forKey: "themeName") ?? "" }
        set { defaults.set(newValue, forKey: "themeName") }
    }

    static func styleOverride(scope: Int32) -> String? {
        defaults.string(forKey: "style.\(scope)")
    }

    static func setStyleOverride(scope: Int32, hex: String) {
        defaults.set(hex, forKey: "style.\(scope)")
    }

    static func clearStyleOverrides() {
        for s in 0...8 {
            defaults.removeObject(forKey: "style.\(s)")
        }
    }

    static func applyAppearance() {
        switch appearance {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }

    /// Shortcut Mapper overrides keyed by English command title (`en:` menu id).
    static var shortcutOverrides: [String: ShortcutBinding] {
        get {
            guard let data = defaults.data(forKey: "shortcutOverrides"),
                  let decoded = try? JSONDecoder().decode([String: ShortcutBinding].self, from: data)
            else { return [:] }
            return decoded
        }
        set {
            if newValue.isEmpty {
                defaults.removeObject(forKey: "shortcutOverrides")
            } else if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "shortcutOverrides")
            }
        }
    }
}
