import AppKit

/// Left-side folder browser ("Folder as Workspace").
final class FolderBrowserPanel: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let outline = NSOutlineView()
    private let scroll = NSScrollView()
    private var rootURL: URL?
    private var childrenCache: [URL: [URL]] = [:]
    private var headerLabel: NSTextField!
    private var openButton: NSButton!
    var onOpenFile: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        headerLabel = NSTextField(labelWithString: "Folder as Workspace")
        headerLabel.font = NSFont.boldSystemFont(ofSize: 11)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerLabel)

        openButton = NSButton(title: "Open Folder…", target: self, action: #selector(pickFolder))
        openButton.bezelStyle = .rounded
        openButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(openButton)

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
            headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            openButton.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 4),
            openButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scroll.topAnchor.constraint(equalTo: openButton.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
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
        headerLabel.stringValue = NativeLang.sectionString(
            section: "FolderAsWorkspace", tag: "PanelTitle", fallback: "Folder as Workspace"
        )
        openButton.title = NativeLang.sectionString(
            section: "FolderAsWorkspace",
            tag: "SelectFolderFromBrowserString",
            fallback: "Open Folder…"
        )
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
