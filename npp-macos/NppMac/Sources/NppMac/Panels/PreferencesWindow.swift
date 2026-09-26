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

    static func show() {
        if shared == nil { shared = PreferencesWindow() }
        shared?.loadFromPrefs()
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
        let tabLabel = NSTextField(labelWithString: "Tab width:")
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
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(close(_:)))
        cancel.bezelStyle = .rounded
        let ok = NSButton(title: "OK", target: self, action: #selector(saveAndClose(_:)))
        ok.bezelStyle = .rounded
        ok.keyEquivalent = "\r"
        buttons.addArrangedSubview(cancel)
        buttons.addArrangedSubview(ok)
        stack.addArrangedSubview(buttons)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: window.contentView!.trailingAnchor, constant: -20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
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
        window?.close()
    }

    @objc private func close(_ sender: Any?) {
        window?.close()
    }
}

extension Notification.Name {
    static let nppPrefsDidChange = Notification.Name("nppPrefsDidChange")
}
