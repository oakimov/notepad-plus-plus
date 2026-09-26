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
}
