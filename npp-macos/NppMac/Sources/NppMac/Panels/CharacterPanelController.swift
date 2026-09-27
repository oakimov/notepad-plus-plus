import AppKit

/// Insert Unicode characters from a searchable grid (Character Panel approximation).
final class CharacterPanelController: NSWindowController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private static var shared: CharacterPanelController?
    private var collection: NSCollectionView!
    private var filterField: NSTextField!
    private var glyphs: [Character] = []
    private var filtered: [Character] = []
    var onInsert: ((String) -> Void)?

    static func show(onInsert: @escaping (String) -> Void) {
        if shared == nil { shared = CharacterPanelController() }
        shared?.onInsert = onInsert
        shared?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = "Character Panel"
        window.center()
        super.init(window: window)

        // Common punctuation + symbols + arrows + box drawing subset.
        let ranges: [ClosedRange<UInt32>] = [
            0x00A0...0x00FF, // Latin-1 supplement
            0x2010...0x205E, // punctuation
            0x2190...0x21FF, // arrows
            0x2500...0x257F, // box drawing
            0x25A0...0x25FF, // geometric
            0x2600...0x26FF, // misc symbols
        ]
        for r in ranges {
            for scalar in r {
                if let s = UnicodeScalar(scalar) {
                    glyphs.append(Character(s))
                }
            }
        }
        filtered = glyphs

        let root = NSView(frame: .zero)
        window.contentView = root

        filterField = NSTextField(string: "")
        filterField.placeholderString = "Filter (hex or name fragment)"
        filterField.target = self
        filterField.action = #selector(filterChanged)
        filterField.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(filterField)

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 36, height: 36)
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        collection = NSCollectionView(frame: .zero)
        collection.collectionViewLayout = layout
        collection.dataSource = self
        collection.delegate = self
        collection.isSelectable = true
        collection.register(CharItem.self, forItemWithIdentifier: CharItem.id)

        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

        NSLayoutConstraint.activate([
            filterField.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            filterField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            filterField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
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
        window?.title = NativeLang.sectionString(
            section: "AsciiInsertion", tag: "PanelTitle", fallback: "Character Panel"
        )
    }

    @objc private func filterChanged() {
        let q = filterField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            filtered = glyphs
        } else if q.hasPrefix("u+") || q.hasPrefix("0x"),
                  let v = UInt32(q.replacingOccurrences(of: "u+", with: "").replacingOccurrences(of: "0x", with: ""), radix: 16),
                  let s = UnicodeScalar(v)
        {
            filtered = [Character(s)]
        } else {
            filtered = glyphs.filter { String($0).lowercased().contains(q) }
        }
        collection.reloadData()
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        filtered.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: CharItem.id, for: indexPath) as! CharItem
        item.label.stringValue = String(filtered[indexPath.item])
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let ip = indexPaths.first else { return }
        onInsert?(String(filtered[ip.item]))
        collectionView.deselectAll(nil)
    }
}

private final class CharItem: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("CharItem")
    let label = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 4
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        label.font = NSFont.systemFont(ofSize: 18)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
