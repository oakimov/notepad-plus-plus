import AppKit

/// Stable shortcut override: AppKit `keyEquivalent` + modifier mask bits.
struct ShortcutBinding: Codable, Equatable {
    var key: String
    /// Raw `NSEvent.ModifierFlags` intersection with command/option/control/shift.
    var mods: UInt

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: mods)
    }

    static func from(keyEquivalent: String, mask: NSEvent.ModifierFlags) -> ShortcutBinding {
        ShortcutBinding(
            key: keyEquivalent,
            mods: mask.intersection([.command, .option, .control, .shift]).rawValue
        )
    }

    static let empty = ShortcutBinding(key: "", mods: 0)

    var displayString: String {
        Self.format(key: key, mods: modifierFlags)
    }

    static func format(key: String, mods: NSEvent.ModifierFlags) -> String {
        guard !key.isEmpty else { return "—" }
        var parts = ""
        if mods.contains(.control) { parts += "⌃" }
        if mods.contains(.option) { parts += "⌥" }
        if mods.contains(.shift) { parts += "⇧" }
        if mods.contains(.command) { parts += "⌘" }
        let shown: String
        switch key {
        case "\r", "\n": shown = "↩"
        case "\t": shown = "⇥"
        case "\u{1b}": shown = "⎋"
        case " ": shown = "Space"
        case "\u{7f}": shown = "⌫"
        case "\u{F700}": shown = "↑"
        case "\u{F701}": shown = "↓"
        case "\u{F702}": shown = "←"
        case "\u{F703}": shown = "→"
        default:
            // Uppercase keyEquivalent already implies Shift in AppKit; still show glyph.
            shown = key.uppercased()
        }
        return parts + shown
    }
}

/// Captures defaults, applies overrides, and hosts Settings → Shortcut Mapper.
enum ShortcutMapper {
    private static var factoryDefaults: [String: ShortcutBinding] = [:]

    /// English-title command id → binding (empty key clears the shortcut).
    static var overrides: [String: ShortcutBinding] {
        get { AppPrefs.shortcutOverrides }
        set { AppPrefs.shortcutOverrides = newValue }
    }

    /// Snapshot current menu key equivalents as factory defaults (call once after `MenuBuilder.build`, before overrides).
    static func captureDefaultsFromMenus() {
        guard factoryDefaults.isEmpty, let main = NSApp.mainMenu else { return }
        var map: [String: ShortcutBinding] = [:]
        walk(main, path: []) { item, _ in
            guard let id = commandID(for: item) else { return }
            map[id] = ShortcutBinding.from(
                keyEquivalent: item.keyEquivalent,
                mask: item.keyEquivalentModifierMask
            )
        }
        factoryDefaults = map
    }

    static func applyOverrides() {
        guard let main = NSApp.mainMenu else { return }
        let ovr = overrides
        walk(main, path: []) { item, _ in
            guard let id = commandID(for: item) else { return }
            let binding: ShortcutBinding
            if let custom = ovr[id] {
                binding = custom
            } else if let factory = factoryDefaults[id] {
                binding = factory
            } else {
                return
            }
            item.keyEquivalent = binding.key
            item.keyEquivalentModifierMask = binding.modifierFlags
        }
    }

    static func resetAll() {
        overrides = [:]
        applyOverrides()
    }

    static func reset(ids: [String]) {
        var ovr = overrides
        for id in ids { ovr.removeValue(forKey: id) }
        overrides = ovr
        applyOverrides()
    }

    static func setOverride(id: String, binding: ShortcutBinding) {
        var ovr = overrides
        if let factory = factoryDefaults[id], factory == binding {
            ovr.removeValue(forKey: id)
        } else {
            ovr[id] = binding
        }
        overrides = ovr
        applyOverrides()
    }

    static func effectiveBinding(id: String, item: NSMenuItem) -> ShortcutBinding {
        if let custom = overrides[id] { return custom }
        if let factory = factoryDefaults[id] { return factory }
        return ShortcutBinding.from(keyEquivalent: item.keyEquivalent, mask: item.keyEquivalentModifierMask)
    }

    static func allRows() -> [ShortcutRow] {
        guard let main = NSApp.mainMenu else { return [] }
        var rows: [ShortcutRow] = []
        for top in main.items {
            guard let sub = top.submenu else { continue }
            let topTitle = englishTitle(of: top) ?? top.title
            collect(sub, path: [topTitle], into: &rows)
        }
        return rows.sorted {
            $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
        }
    }

    private static func collect(_ menu: NSMenu, path: [String], into rows: inout [ShortcutRow]) {
        for item in menu.items {
            if item.isSeparatorItem { continue }
            let title = englishTitle(of: item) ?? item.title
            if let sub = item.submenu {
                collect(sub, path: path + [title], into: &rows)
                continue
            }
            guard item.action != nil else { continue }
            guard let id = commandID(for: item) else { continue }
            // Skip system Hide / Quit equivalents that always stay on the app menu.
            if id == "Hide NppMac" || id == "Quit NppMac" || id == "Hide Others" { continue }
            rows.append(
                ShortcutRow(
                    id: id,
                    title: title,
                    menuPath: path.joined(separator: " › "),
                    binding: effectiveBinding(id: id, item: item)
                )
            )
        }
    }

    private static func walk(_ menu: NSMenu, path: [String], visit: (NSMenuItem, [String]) -> Void) {
        for item in menu.items {
            if item.isSeparatorItem { continue }
            let title = englishTitle(of: item) ?? item.title
            visit(item, path)
            if let sub = item.submenu {
                walk(sub, path: path + [title], visit: visit)
            }
        }
    }

    /// Prefer `en:` identifier; ensure one exists from the current (English) title when capturing.
    static func commandID(for item: NSMenuItem) -> String? {
        if let raw = item.identifier?.rawValue, raw.hasPrefix("en:") {
            let id = String(raw.dropFirst(3))
            return id.isEmpty ? nil : id
        }
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, item.action != nil else { return nil }
        item.identifier = NSUserInterfaceItemIdentifier("en:\(title)")
        return title
    }

    private static func englishTitle(of item: NSMenuItem) -> String? {
        if let raw = item.identifier?.rawValue, raw.hasPrefix("en:") {
            return String(raw.dropFirst(3))
        }
        return nil
    }
}

struct ShortcutRow {
    var id: String
    var title: String
    var menuPath: String
    var binding: ShortcutBinding

    var path: String { "\(menuPath) › \(title)" }
}

// MARK: - Window

final class ShortcutMapperWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private static var shared: ShortcutMapperWindow?

    private var allRows: [ShortcutRow] = []
    private var filtered: [ShortcutRow] = []
    private var table: NSTableView!
    private var searchField: NSSearchField!
    private var statusLabel: NSTextField!
    private var recorder: KeyRecorderView!
    private var selectedID: String?

    static func show() {
        if shared == nil { shared = ShortcutMapperWindow() }
        shared?.reload()
        shared?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Shortcut Mapper"
        window.minSize = NSSize(width: 520, height: 360)
        window.center()
        super.init(window: window)

        let content = NSView(frame: window.contentView!.bounds)
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = content

        searchField = NSSearchField()
        searchField.placeholderString = "Filter commands"
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(searchField)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        table = NSTableView()
        table.delegate = self
        table.dataSource = self
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.rowHeight = 22
        table.target = self
        table.doubleAction = #selector(editSelected(_:))

        let colCmd = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("cmd"))
        colCmd.title = "Command"
        colCmd.width = 280
        colCmd.minWidth = 160
        table.addTableColumn(colCmd)

        let colKey = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("key"))
        colKey.title = "Shortcut"
        colKey.width = 120
        colKey.minWidth = 80
        table.addTableColumn(colKey)

        let colPath = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        colPath.title = "Menu"
        colPath.width = 200
        colPath.minWidth = 100
        table.addTableColumn(colPath)

        scroll.documentView = table

        let editBtn = NSButton(title: "Edit…", target: self, action: #selector(editSelected(_:)))
        editBtn.bezelStyle = .rounded
        let clearBtn = NSButton(title: "Clear", target: self, action: #selector(clearSelected(_:)))
        clearBtn.bezelStyle = .rounded
        let resetBtn = NSButton(title: "Reset Selected", target: self, action: #selector(resetSelected(_:)))
        resetBtn.bezelStyle = .rounded
        let resetAllBtn = NSButton(title: "Reset All", target: self, action: #selector(resetAll(_:)))
        resetAllBtn.bezelStyle = .rounded
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(save(_:)))
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "s"
        saveBtn.keyEquivalentModifierMask = .command
        let closeBtn = NSButton(title: "Close", target: self, action: #selector(closeWindow(_:)))
        closeBtn.bezelStyle = .rounded

        let buttons = NSStackView(views: [editBtn, clearBtn, resetBtn, resetAllBtn, NSView(), saveBtn, closeBtn])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(buttons)

        recorder = KeyRecorderView()
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.onCaptured = { [weak self] binding in
            self?.applyRecording(binding)
        }
        content.addSubview(recorder)

        statusLabel = NSTextField(labelWithString: "Select a command, then click the recorder and press a key combination.")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: recorder.topAnchor, constant: -8),

            recorder.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            recorder.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            recorder.heightAnchor.constraint(equalToConstant: 36),
            recorder.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -6),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            statusLabel.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -8),

            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func reload() {
        allRows = ShortcutMapper.allRows()
        applyFilter()
    }

    private func applyFilter() {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            filtered = allRows
        } else {
            filtered = allRows.filter {
                $0.title.lowercased().contains(q)
                    || $0.menuPath.lowercased().contains(q)
                    || $0.binding.displayString.lowercased().contains(q)
            }
        }
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < filtered.count, let col = tableColumn else { return nil }
        let item = filtered[row]
        let text: String
        switch col.identifier.rawValue {
        case "cmd": text = item.title
        case "key": text = item.binding.displayString
        case "path": text = item.menuPath
        default: text = ""
        }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView
            ?? {
                let c = NSTableCellView()
                c.identifier = id
                let tf = NSTextField(labelWithString: "")
                tf.translatesAutoresizingMaskIntoConstraints = false
                tf.lineBreakMode = .byTruncatingTail
                c.addSubview(tf)
                c.textField = tf
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                    tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -2),
                    tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                ])
                return c
            }()
        cell.textField?.stringValue = text
        if col.identifier.rawValue == "key" {
            cell.textField?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        } else {
            cell.textField?.font = NSFont.systemFont(ofSize: 12)
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        guard row >= 0, row < filtered.count else {
            selectedID = nil
            recorder.prompt = "Select a command to rebind"
            return
        }
        selectedID = filtered[row].id
        let b = filtered[row].binding
        recorder.prompt = b.key.isEmpty
            ? "Press keys for “\(filtered[row].title)”…"
            : "Current \(b.displayString) — press new keys for “\(filtered[row].title)”…"
        recorder.arm()
    }

    @objc private func searchChanged(_ sender: Any?) {
        applyFilter()
    }

    @objc private func editSelected(_ sender: Any?) {
        let row = table.selectedRow
        guard row >= 0, row < filtered.count else { return }
        selectedID = filtered[row].id
        recorder.arm()
        window?.makeFirstResponder(recorder)
        statusLabel.stringValue = "Recording — press the new shortcut for “\(filtered[row].title)”."
    }

    private func applyRecording(_ binding: ShortcutBinding) {
        guard let id = selectedID else {
            statusLabel.stringValue = "Select a command first."
            return
        }
        // Soft conflict note (still apply).
        if !binding.key.isEmpty {
            let conflicts = allRows.filter {
                $0.id != id
                    && $0.binding.key == binding.key
                    && $0.binding.mods == binding.mods
            }
            if let first = conflicts.first {
                statusLabel.stringValue = "Note: also used by “\(first.title)”. Saved anyway."
            } else {
                statusLabel.stringValue = "Rebound to \(binding.displayString)."
            }
        } else {
            statusLabel.stringValue = "Shortcut cleared."
        }
        ShortcutMapper.setOverride(id: id, binding: binding)
        reload()
        if let idx = filtered.firstIndex(where: { $0.id == id }) {
            table.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            table.scrollRowToVisible(idx)
        }
    }

    @objc private func clearSelected(_ sender: Any?) {
        guard let id = selectedID else { return }
        ShortcutMapper.setOverride(id: id, binding: .empty)
        statusLabel.stringValue = "Shortcut cleared."
        reload()
    }

    @objc private func resetSelected(_ sender: Any?) {
        guard let id = selectedID else { return }
        ShortcutMapper.reset(ids: [id])
        statusLabel.stringValue = "Restored default shortcut."
        reload()
    }

    @objc private func resetAll(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Reset all shortcuts?"
        alert.informativeText = "Restore every command to its built-in key equivalent."
        alert.addButton(withTitle: "Reset All")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ShortcutMapper.resetAll()
        statusLabel.stringValue = "All shortcuts restored to defaults."
        reload()
    }

    @objc private func save(_ sender: Any?) {
        SessionStore.saveConfig()
        statusLabel.stringValue = "Saved to config.xml / preferences."
    }

    @objc private func closeWindow(_ sender: Any?) {
        SessionStore.saveConfig()
        window?.close()
    }
}

// MARK: - Key recorder

final class KeyRecorderView: NSView {
    var prompt: String = "Click here, then press a key combination" {
        didSet { needsDisplay = true }
    }
    var onCaptured: ((ShortcutBinding) -> Void)?

    private var armed = false
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    func arm() {
        armed = true
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        arm()
    }

    override func becomeFirstResponder() -> Bool {
        armed = true
        installMonitor()
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        removeMonitor()
        armed = false
        needsDisplay = true
        return super.resignFirstResponder()
    }

    private func installMonitor() {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.armed else { return event }
            if event.keyCode == 53 { // Escape cancels recording focus
                self.window?.makeFirstResponder(nil)
                return nil
            }
            let binding = Self.binding(from: event)
            self.onCaptured?(binding)
            self.armed = false
            self.removeMonitor()
            self.needsDisplay = true
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit { removeMonitor() }

    static func binding(from event: NSEvent) -> ShortcutBinding {
        var mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // Prefer charactersIgnoringModifiers; fall back to characters.
        var key = event.charactersIgnoringModifiers ?? event.characters ?? ""
        // Function / special keys come through as private-use chars; keep first scalar.
        if key.count > 1 { key = String(key.prefix(1)) }
        // AppKit menu convention: uppercase letter implies Shift in the equivalent.
        if key.count == 1, let ch = key.unicodeScalars.first, CharacterSet.letters.contains(ch) {
            if mods.contains(.shift) {
                key = key.uppercased()
                mods.remove(.shift)
            } else {
                key = key.lowercased()
            }
        }
        // Default Command for letter shortcuts when no modifier was held (matches menubar habit).
        if mods.isEmpty, key.count == 1, let ch = key.unicodeScalars.first, CharacterSet.alphanumerics.contains(ch) {
            mods.insert(.command)
        }
        return ShortcutBinding.from(keyEquivalent: key, mask: mods)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let bg = armed ? NSColor.selectedControlColor.withAlphaComponent(0.25) : NSColor.controlBackgroundColor
        bg.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: armed ? NSColor.labelColor : NSColor.secondaryLabelColor,
        ]
        let str = NSAttributedString(string: prompt, attributes: attrs)
        let size = str.size()
        let origin = NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        )
        str.draw(at: origin)
    }
}
