import AppKit

/// Left-side folder browser ("Folder as Workspace").
final class FolderBrowserPanel: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let outline = NSOutlineView()
    private let scroll = NSScrollView()
    private var rootURL: URL?
    private var childrenCache: [URL: [URL]] = [:]
    var onOpenFile: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let header = NSTextField(labelWithString: "Folder as Workspace")
        header.font = NSFont.boldSystemFont(ofSize: 11)
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        let openBtn = NSButton(title: "Open Folder…", target: self, action: #selector(pickFolder))
        openBtn.bezelStyle = .rounded
        openBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(openBtn)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.title = "Name"
        col.width = 200
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.headerView = nil
        outline.delegate = self
        outline.dataSource = self
        outline.rowHeight = 20
        outline.style = .plain
        outline.doubleAction = #selector(rowActivated)
        outline.target = self

        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            openBtn.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            openBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scroll.topAnchor.constraint(equalTo: openBtn.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setRoot(_ url: URL?) {
        rootURL = url
        childrenCache.removeAll()
        outline.reloadData()
        if let url {
            outline.expandItem(url)
        }
    }

    @objc private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            self?.setRoot(url)
        }
    }

    @objc private func rowActivated() {
        let row = outline.clickedRow
        guard row >= 0, let url = outline.item(atRow: row) as? URL else { return }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
            onOpenFile?(url)
        }
    }

    private func children(of url: URL) -> [URL] {
        if let cached = childrenCache[url] { return cached }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let sorted = urls.sorted {
            let aDir = (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            let bDir = (try? $1.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if aDir != bDir { return aDir && !bDir }
            return $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
        childrenCache[url] = sorted
        return sorted
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return rootURL == nil ? 0 : 1
        }
        guard let url = item as? URL else { return 0 }
        return children(of: url).count
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let url = item as? URL else { return false }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return rootURL!
        }
        let url = item as! URL
        return children(of: url)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("folderCell")
        let cell = (outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? {
            let c = NSTableCellView()
            c.identifier = id
            let t = NSTextField(labelWithString: "")
            t.translatesAutoresizingMaskIntoConstraints = false
            t.lineBreakMode = .byTruncatingTail
            c.addSubview(t)
            c.textField = t
            NSLayoutConstraint.activate([
                t.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                t.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -2),
                t.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()
        if let url = item as? URL {
            cell.textField?.stringValue = url.lastPathComponent
        }
        return cell
    }
}
