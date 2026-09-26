import AppKit

/// Internal document tab bar (Notepad++ parity: NOT native window tabbing).
/// Click selects; drag reorders; × closes (dirty ⇒ prompt).
final class TabBarView: NSView {
    private let store: DocumentStore
    private let onSelect: () -> Void
    private let onClose: (Int) -> Void
    private let syncBeforeSelect: () -> Void
    private var stack = NSStackView()
    private var dragFrom: Int?

    init(
        store: DocumentStore,
        onSelect: @escaping () -> Void,
        onClose: @escaping (Int) -> Void,
        syncBeforeSelect: @escaping () -> Void
    ) {
        self.store = store
        self.onSelect = onSelect
        self.onClose = onClose
        self.syncBeforeSelect = syncBeforeSelect
        super.init(frame: .zero)
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
        ])
        registerForDraggedTypes([.string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func reload() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let selected = store.selectedIndex
        for (index, tab) in store.tabs.enumerated() {
            let cell = NSStackView()
            cell.orientation = .horizontal
            cell.spacing = 2
            cell.identifier = NSUserInterfaceItemIdentifier("tab-\(index)")

            let button = NSButton(
                title: tab.isDirty ? "\(tab.title) •" : tab.title,
                target: self,
                action: #selector(tabClicked(_:))
            )
            button.tag = index
            button.bezelStyle = .rounded
            // On/off type so `state` actually renders the selected tab.
            button.setButtonType(.pushOnPushOff)
            button.state = index == selected ? .on : .off
            button.toolTip = tab.fileURL?.path ?? tab.title
            cell.addArrangedSubview(button)

            let close = NSButton(title: "×", target: self, action: #selector(tabClose(_:)))
            close.tag = index
            close.bezelStyle = .inline
            close.setButtonType(.momentaryPushIn)
            close.toolTip = "Close tab"
            cell.addArrangedSubview(close)

            stack.addArrangedSubview(cell)
        }
    }

    @objc private func tabClicked(_ sender: NSButton) {
        syncBeforeSelect()
        store.select(at: sender.tag)
        onSelect()
    }

    @objc private func tabClose(_ sender: NSButton) {
        syncBeforeSelect()
        onClose(sender.tag)
    }

    // MARK: - Drag reorder

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let idx = tabIndex(at: point) {
            dragFrom = idx
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let from = dragFrom else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let to = tabIndex(at: point), to != from {
            syncBeforeSelect()
            store.moveTab(from: from, to: to)
            dragFrom = to
            reload()
            onSelect()
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragFrom = nil
    }

    private func tabIndex(at point: NSPoint) -> Int? {
        for cell in stack.arrangedSubviews {
            let frameInSelf = stack.convert(cell.frame, to: self)
            if frameInSelf.contains(point),
               let id = cell.identifier?.rawValue,
               id.hasPrefix("tab-"),
               let idx = Int(id.dropFirst(4))
            {
                return idx
            }
        }
        return nil
    }
}
