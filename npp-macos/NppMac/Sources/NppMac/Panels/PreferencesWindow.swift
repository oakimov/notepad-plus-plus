import AppKit

/// Minimal Preferences window (Settings menu parity, M2 scope).
final class PreferencesWindow: NSWindowController {
    private static var shared: PreferencesWindow?

    static func show() {
        if shared == nil { shared = PreferencesWindow() }
        shared?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()
        super.init(window: window)

        let label = NSTextField(labelWithString: "Defaults: UTF-8, LF for new files, tab width 4.\nFull Settings dialog (shortcuts, stylers, backup) lands with config.xml read/write.")
        label.frame = NSRect(x: 20, y: 120, width: 380, height: 100)
        window.contentView?.addSubview(label)

        let ok = NSButton(title: "OK", target: self, action: #selector(close(_:)))
        ok.frame = NSRect(x: 320, y: 16, width: 80, height: 28)
        ok.bezelStyle = .rounded
        ok.keyEquivalent = "\r"
        window.contentView?.addSubview(ok)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func close(_ sender: Any?) {
        window?.close()
    }
}
