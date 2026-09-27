import AppKit

/// Recent clipboard snippets (Notepad++ Clipboard History approximation).
final class ClipboardHistoryPanel: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private var items: [String] = []
    private var lastSeen = ""
    private var timer: Timer?
    private var headerLabel: NSTextField!
    private var clearButton: NSButton!
    var onPaste: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        headerLabel = NSTextField(labelWithString: "Clipboard History")
        headerLabel.font = NSFont.boldSystemFont(ofSize: 11)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerLabel)

        clearButton = NSButton(title: "Clear", target: self, action: #selector(clearAll))
        clearButton.bezelStyle = .rounded
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clearButton)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        col.title = "Clip"
        col.width = 200
        table.addTableColumn(col)
        table.headerView = nil
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 22
        table.style = .plain
        table.doubleAction = #selector(rowActivated)
        table.target = self

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            clearButton.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])

        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }

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
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func nativeLangDidChange(_ note: Notification) {
        applyLocalizedStrings()
    }

    private func applyLocalizedStrings() {
        headerLabel.stringValue = NativeLang.sectionString(
            section: "ClipboardHistory", tag: "PanelTitle", fallback: "Clipboard History"
        )
        clearButton.title = NativeLang.dialogString(
            dialogId: "ShortcutMapper", itemId: "2606", fallback: "Clear"
        )
    }

    func start() { pollPasteboard() }

    private func pollPasteboard() {
        guard let s = NSPasteboard.general.string(forType: .string), !s.isEmpty, s != lastSeen else { return }
        lastSeen = s
        items.removeAll { $0 == s }
        items.insert(s, at: 0)
        if items.count > 30 { items = Array(items.prefix(30)) }
        table.reloadData()
    }

    @objc private func clearAll() {
        items.removeAll()
        table.reloadData()
    }

    @objc private func rowActivated() {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard items.indices.contains(row) else { return }
        onPaste?(items[row])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("clipCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? {
            let c = NSTableCellView()
            c.identifier = id
            let t = NSTextField(labelWithString: "")
            t.translatesAutoresizingMaskIntoConstraints = false
            t.lineBreakMode = .byTruncatingTail
            c.addSubview(t)
            c.textField = t
            NSLayoutConstraint.activate([
                t.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 4),
                t.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
                t.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()
        let raw = items[row].replacingOccurrences(of: "\n", with: "⏎ ")
        cell.textField?.stringValue = String(raw.prefix(80))
        return cell
    }
}
