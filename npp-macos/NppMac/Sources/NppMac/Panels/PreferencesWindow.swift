import AppKit

/// Preferences window bound to [`AppPrefs`].
final class PreferencesWindow: NSWindowController {
    private static var shared: PreferencesWindow?

    private var wrapBox: NSButton!
    private var linesBox: NSButton!
    private var backupBox: NSButton!
    private var sessionBox: NSButton!
    private var watchBox: NSButton!
    private var tabField: NSTextField!
    private var tabLabel: NSTextField!
    private var cancelButton: NSButton!
    private var okButton: NSButton!

    static func show() {
        if shared == nil { shared = PreferencesWindow() }
        shared?.loadFromPrefs()
        shared?.applyLocalizedStrings()
        shared?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()
        super.init(window: window)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)

        wrapBox = NSButton(checkboxWithTitle: "Word wrap by default", target: nil, action: nil)
        linesBox = NSButton(checkboxWithTitle: "Show line numbers", target: nil, action: nil)
        backupBox = NSButton(checkboxWithTitle: "Create .bak backup on save", target: nil, action: nil)
        sessionBox = NSButton(checkboxWithTitle: "Restore session on launch", target: nil, action: nil)
        watchBox = NSButton(checkboxWithTitle: "Watch for disk changes", target: nil, action: nil)

        let tabRow = NSStackView()
        tabRow.orientation = .horizontal
        tabRow.spacing = 8
        tabLabel = NSTextField(labelWithString: "Tab width:")
        tabField = NSTextField(string: "4")
        tabField.frame.size.width = 48
        tabField.widthAnchor.constraint(equalToConstant: 48).isActive = true
        tabRow.addArrangedSubview(tabLabel)
        tabRow.addArrangedSubview(tabField)

        for v in [wrapBox!, linesBox!, backupBox!, sessionBox!, watchBox!, tabRow] as [NSView] {
            stack.addArrangedSubview(v)
        }

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(close(_:)))
        cancelButton.bezelStyle = .rounded
        okButton = NSButton(title: "OK", target: self, action: #selector(saveAndClose(_:)))
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"
        buttons.addArrangedSubview(cancelButton)
        buttons.addArrangedSubview(okButton)
        stack.addArrangedSubview(buttons)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: window.contentView!.trailingAnchor, constant: -20),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(nativeLangDidChange(_:)),
            name: NativeLang.didChangeNotification,
            object: nil
        )
        applyLocalizedStrings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func nativeLangDidChange(_ note: Notification) {
        applyLocalizedStrings()
    }

    private func applyLocalizedStrings() {
        window?.title = NativeLang.dialogTitle(dialogId: "Preference", fallback: "Preferences")
        // Closest upstream Preference strings; mac-only wording stays as English fallback.
        wrapBox.title = NativeLang.commandTitle(id: "44022", fallback: "Word wrap by default")
        linesBox.title = NativeLang.dialogString(
            dialogId: "MarginsBorderEdge", itemId: "6291", fallback: "Show line numbers"
        )
        backupBox.title = NativeLang.dialogString(
            dialogId: "Backup", itemId: "6801", fallback: "Create .bak backup on save"
        )
        sessionBox.title = NativeLang.dialogString(
            dialogId: "Backup", itemId: "6309", fallback: "Restore session on launch"
        )
        watchBox.title = NativeLang.dialogString(
            dialogId: "MISC", itemId: "6312", fallback: "Watch for disk changes"
        )
        tabLabel.stringValue = NativeLang.dialogString(
            dialogId: "Indentation", itemId: "6303", fallback: "Tab width:"
        )
        cancelButton.title = NativeLang.miscString(id: "common-cancel", fallback: "Cancel")
        okButton.title = NativeLang.miscString(id: "common-ok", fallback: "OK")
    }

    private func loadFromPrefs() {
        wrapBox.state = AppPrefs.wordWrapDefault ? .on : .off
        linesBox.state = AppPrefs.showLineNumbers ? .on : .off
        backupBox.state = AppPrefs.backupOnSave ? .on : .off
        sessionBox.state = AppPrefs.restoreSession ? .on : .off
        watchBox.state = AppPrefs.watchDiskChanges ? .on : .off
        tabField.stringValue = "\(AppPrefs.tabWidth)"
    }

    @objc private func saveAndClose(_ sender: Any?) {
        AppPrefs.wordWrapDefault = wrapBox.state == .on
        AppPrefs.showLineNumbers = linesBox.state == .on
        AppPrefs.backupOnSave = backupBox.state == .on
        AppPrefs.restoreSession = sessionBox.state == .on
        AppPrefs.watchDiskChanges = watchBox.state == .on
        if let n = Int(tabField.stringValue), n > 0, n < 32 {
            AppPrefs.tabWidth = n
        }
        NotificationCenter.default.post(name: .nppPrefsDidChange, object: nil)
        SessionStore.saveConfig()
        window?.close()
    }

    @objc private func close(_ sender: Any?) {
        window?.close()
    }
}

extension Notification.Name {
    static let nppPrefsDidChange = Notification.Name("nppPrefsDidChange")
}
