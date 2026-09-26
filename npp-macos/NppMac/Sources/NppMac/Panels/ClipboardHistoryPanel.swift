import AppKit

/// Recent clipboard snippets (Notepad++ Clipboard History approximation).
final class ClipboardHistoryPanel: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private var items: [String] = []
    private var lastSeen = ""
    private var timer: Timer?
    var onPaste: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let header = NSTextField(labelWithString: "Clipboard History")
        header.font = NSFont.boldSystemFont(ofSize: 11)
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        let clear = NSButton(title: "Clear", target: self, action: #selector(clearAll))
        clear.bezelStyle = .rounded
        clear.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clear)

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
            header.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            clear.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            clear.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])

        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        timer?.invalidate()
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
