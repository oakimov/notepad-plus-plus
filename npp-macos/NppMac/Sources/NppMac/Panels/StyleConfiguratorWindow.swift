import AppKit

/// Settings → Style Configurator: override syntax scope colors.
final class StyleConfiguratorWindow: NSWindowController {
    private static var shared: StyleConfiguratorWindow?

    private struct Row {
        var scope: Int32
        var title: String
        var well: NSColorWell
    }

    private var rows: [Row] = []

    static func show() {
        if shared == nil { shared = StyleConfiguratorWindow() }
        shared?.loadColors()
        shared?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Style Configurator"
        window.center()
        super.init(window: window)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)

        let scopes: [(Int32, String)] = [
            (0, "Default"),
            (1, "Keyword"),
            (2, "Type"),
            (3, "String"),
            (4, "Comment"),
            (5, "Number"),
            (6, "Operator"),
            (7, "Function"),
            (8, "Preprocessor"),
        ]
        for (scope, title) in scopes {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 12
            let label = NSTextField(labelWithString: title)
            label.widthAnchor.constraint(equalToConstant: 120).isActive = true
            let well = NSColorWell()
            well.isBordered = true
            well.widthAnchor.constraint(equalToConstant: 48).isActive = true
            well.heightAnchor.constraint(equalToConstant: 24).isActive = true
            row.addArrangedSubview(label)
            row.addArrangedSubview(well)
            stack.addArrangedSubview(row)
            rows.append(Row(scope: scope, title: title, well: well))
        }

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let reset = NSButton(title: "Reset Overrides", target: self, action: #selector(resetOverrides(_:)))
        reset.bezelStyle = .rounded
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(close(_:)))
        cancel.bezelStyle = .rounded
        let ok = NSButton(title: "OK", target: self, action: #selector(saveAndClose(_:)))
        ok.bezelStyle = .rounded
        ok.keyEquivalent = "\r"
        buttons.addArrangedSubview(reset)
        buttons.addArrangedSubview(cancel)
        buttons.addArrangedSubview(ok)
        stack.addArrangedSubview(buttons)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: window.contentView!.trailingAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func loadColors() {
        for row in rows {
            if let hex = AppPrefs.styleOverride(scope: row.scope),
               let c = StyleColors.color(fromRGBHex: hex)
            {
                row.well.color = c
            } else {
                row.well.color = StyleColors.fallback(forScope: row.scope)
            }
        }
    }

    @objc private func resetOverrides(_ sender: Any?) {
        AppPrefs.clearStyleOverrides()
        loadColors()
        NotificationCenter.default.post(name: .nppStylesDidChange, object: nil)
    }

    @objc private func saveAndClose(_ sender: Any?) {
        for row in rows {
            AppPrefs.setStyleOverride(scope: row.scope, hex: StyleColors.rgbHex(row.well.color))
        }
        SessionStore.saveConfig()
        NotificationCenter.default.post(name: .nppStylesDidChange, object: nil)
        window?.close()
    }

    @objc private func close(_ sender: Any?) {
        window?.close()
    }
}

enum StyleColors {
    static func rgbHex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }

    static func color(fromRGBHex hex: String) -> NSColor? {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    static func fallback(forScope scope: Int32) -> NSColor {
        switch scope {
        case 1: return .systemPurple
        case 2: return .systemTeal
        case 3: return .systemOrange
        case 4: return .systemGray
        case 5: return .systemBlue
        case 6: return .systemPink
        case 7: return .systemIndigo
        case 8: return .systemBrown
        default: return .textColor
        }
    }
}

extension Notification.Name {
    static let nppStylesDidChange = Notification.Name("nppStylesDidChange")
}
