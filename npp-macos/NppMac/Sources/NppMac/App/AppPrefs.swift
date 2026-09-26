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
}
