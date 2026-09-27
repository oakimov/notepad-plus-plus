import AppKit

/// Notepad++-style Document Map: scaled-down text overview; click to jump.
final class DocumentMapPanel: NSView, NSTextViewDelegate {
    private let scroll = NSScrollView()
    private let mapView = NSTextView()
    private var syncing = false
    private var headerLabel: NSTextField!
    var onJumpFraction: ((CGFloat) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        headerLabel = NSTextField(labelWithString: "Document Map")
        headerLabel.font = NSFont.boldSystemFont(ofSize: 11)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerLabel)

        mapView.isEditable = false
        mapView.isSelectable = false
        mapView.isRichText = false
        mapView.drawsBackground = true
        mapView.backgroundColor = NSColor.textBackgroundColor
        mapView.font = NSFont.monospacedSystemFont(ofSize: 4, weight: .regular)
        mapView.textColor = NSColor.secondaryLabelColor
        mapView.isVerticallyResizable = true
        mapView.isHorizontallyResizable = false
        mapView.textContainer?.widthTracksTextView = true
        mapView.textContainer?.containerSize = NSSize(width: 120, height: CGFloat.greatestFiniteMagnitude)
        mapView.minSize = .zero
        mapView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        mapView.delegate = self

        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked(_:)))
        mapView.addGestureRecognizer(click)

        scroll.documentView = mapView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scroll.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
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
            section: "DocumentMap", tag: "PanelTitle", fallback: "Document Map"
        )
    }

    func setText(_ text: String) {
        guard mapView.string != text else { return }
        syncing = true
        mapView.string = text
        syncing = false
    }

    /// Sync scroll position so the visible editor fraction is near the top of the map viewport.
    func mirrorVisibleFraction(_ fraction: CGFloat) {
        let docH = mapView.bounds.height
        let visH = scroll.contentView.bounds.height
        guard docH > visH else { return }
        let y = max(0, min(docH - visH, fraction * docH - visH * 0.25))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    @objc private func clicked(_ gr: NSClickGestureRecognizer) {
        let p = gr.location(in: mapView)
        let h = max(mapView.bounds.height, 1)
        let frac: CGFloat
        if mapView.isFlipped {
            frac = max(0, min(1, p.y / h))
        } else {
            frac = max(0, min(1, 1 - p.y / h))
        }
        onJumpFraction?(frac)
    }
}
