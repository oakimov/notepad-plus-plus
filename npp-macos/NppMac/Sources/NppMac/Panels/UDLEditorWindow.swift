import AppKit

/// AppKit User Defined Language editor (shell + 4 tabs + styler sheet).
/// Mirrors upstream UserDefineDialog; binds to [`UDLStore`] / Swift XML until FFI CRUD lands.
final class UDLEditorWindow: NSWindowController, NSTextFieldDelegate, NSTextViewDelegate {
    private static var shared: UDLEditorWindow?

    private var store: UDLStore { UDLStore.shared }
    private var current: UDLLanguage = .blank()
    private var loadingUI = false

    // Shell
    private var langPopup: NSPopUpButton!
    private var ignoreCaseBox: NSButton!
    private var extField: NSTextField!
    private var tabView: NSTabView!

    // Folder & Default
    private var foldCompactBox: NSButton!
    private var folderFields: [NSTextField] = []

    // Keywords
    private var keywordViews: [NSTextView] = []
    private var prefixBoxes: [NSButton] = []

    // Comment & Number
    private var commentFields: [NSTextField] = []
    private var numberFields: [NSTextField] = []
    private var foldCommentsBox: NSButton!
    private var decimalPopup: NSPopUpButton!

    // Operators & Delimiters
    private var operators1View: NSTextView!
    private var operators2View: NSTextView!
    private var delimiterFields: [[NSTextField]] = []

    // Styler sheet
    private var stylerPanel: NSPanel?
    private var stylerTargetName: String = "DEFAULT"
    private var stylerFgWell: NSColorWell!
    private var stylerBgWell: NSColorWell!
    private var stylerBold: NSButton!
    private var stylerItalic: NSButton!
    private var stylerUnderline: NSButton!
    private var stylerFontName: NSTextField!
    private var stylerFontSize: NSTextField!
    private var stylerNestingBoxes: [NSButton] = []

    static func show() {
        if shared == nil { shared = UDLEditorWindow() }
        shared?.reloadAndShow()
    }

    private func reloadAndShow() {
        store.reloadFromDisk()
        if store.languages.isEmpty {
            current = .blank(name: "new user define")
            store.upsert(current)
        } else {
            current = store.languages[0]
        }
        rebuildPopup()
        loadCurrentIntoUI()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "User Defined Language"
        window.minSize = NSSize(width: 700, height: 520)
        window.center()
        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - UI construction

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        root.addArrangedSubview(makeShellRow())
        root.addArrangedSubview(makeMetaRow())

        tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.addTabViewItem(makeFolderTab())
        tabView.addTabViewItem(makeKeywordsTab())
        tabView.addTabViewItem(makeCommentNumberTab())
        tabView.addTabViewItem(makeOperatorsTab())
        root.addArrangedSubview(tabView)
        tabView.heightAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true

        let saveRow = NSStackView()
        saveRow.orientation = .horizontal
        saveRow.spacing = 8
        saveRow.alignment = .centerY
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        saveRow.addArrangedSubview(spacer)
        saveRow.addArrangedSubview(roundedButton("Save", #selector(saveAction(_:))))
        root.addArrangedSubview(saveRow)
    }

    private func makeShellRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY

        langPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        langPopup.target = self
        langPopup.action = #selector(langPopupChanged(_:))
        langPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        row.addArrangedSubview(langPopup)

        for (title, sel) in [
            ("Create new", #selector(createNew(_:))),
            ("Save as…", #selector(saveAsAction(_:))),
            ("Rename…", #selector(renameAction(_:))),
            ("Remove", #selector(removeAction(_:))),
            ("Import…", #selector(importAction(_:))),
            ("Export…", #selector(exportAction(_:))),
        ] as [(String, Selector)] {
            row.addArrangedSubview(roundedButton(title, sel))
        }
        return row
    }

    private func makeMetaRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        ignoreCaseBox = NSButton(checkboxWithTitle: "Ignore case", target: self, action: #selector(metaChanged(_:)))
        row.addArrangedSubview(ignoreCaseBox)
        row.addArrangedSubview(NSTextField(labelWithString: "Ext:"))
        extField = NSTextField(string: "")
        extField.delegate = self
        extField.widthAnchor.constraint(equalToConstant: 160).isActive = true
        row.addArrangedSubview(extField)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)
        return row
    }

    // MARK: Tab 1 — Folder & Default

    private func makeFolderTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "folder")
        item.label = "Folder & Default"
        let scroll = makeScrollableStack()
        let stack = scroll.documentStack

        let top = NSStackView()
        top.orientation = .horizontal
        top.spacing = 12
        top.addArrangedSubview(stylerButton("DEFAULT", styleName: "DEFAULT"))
        foldCompactBox = NSButton(checkboxWithTitle: "Fold compact", target: self, action: #selector(metaChanged(_:)))
        top.addArrangedSubview(foldCompactBox)
        stack.addArrangedSubview(top)

        folderFields.removeAll()
        let groups: [(String, String, String)] = [
            ("Folders in code1", "FOLDER IN CODE1", "Folders in code1"),
            ("Folders in code2", "FOLDER IN CODE2", "Folders in code2"),
            ("Folders in comment", "FOLDER IN COMMENT", "Folders in comment"),
        ]
        for (label, styleName, kwPrefix) in groups {
            let header = NSStackView()
            header.orientation = .horizontal
            header.spacing = 8
            header.addArrangedSubview(NSTextField(labelWithString: label))
            header.addArrangedSubview(stylerButton("Styler", styleName: styleName))
            stack.addArrangedSubview(header)
            for part in ["open", "middle", "close"] {
                let (row, field) = labeledField("\(part):", width: 280)
                field.identifier = NSUserInterfaceItemIdentifier("kw:\(kwPrefix), \(part)")
                field.delegate = self
                folderFields.append(field)
                stack.addArrangedSubview(row)
            }
        }
        item.view = scroll.scrollView
        return item
    }

    // MARK: Tab 2 — Keywords Lists

    private func makeKeywordsTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "keywords")
        item.label = "Keywords Lists"
        let scroll = makeScrollableStack()
        let stack = scroll.documentStack
        keywordViews.removeAll()
        prefixBoxes.removeAll()

        for i in 1...8 {
            let header = NSStackView()
            header.orientation = .horizontal
            header.spacing = 8
            header.addArrangedSubview(NSTextField(labelWithString: "Keywords\(i)"))
            let prefix = NSButton(checkboxWithTitle: "Prefix mode", target: self, action: #selector(metaChanged(_:)))
            prefixBoxes.append(prefix)
            header.addArrangedSubview(prefix)
            header.addArrangedSubview(stylerButton("Styler", styleName: "KEYWORDS\(i)"))
            stack.addArrangedSubview(header)

            let (scrollTV, tv) = makeTextView(height: 56)
            tv.delegate = self
            tv.identifier = NSUserInterfaceItemIdentifier("Keywords\(i)")
            keywordViews.append(tv)
            stack.addArrangedSubview(scrollTV)
        }
        item.view = scroll.scrollView
        return item
    }

    // MARK: Tab 3 — Comment & Number

    private func makeCommentNumberTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "comment")
        item.label = "Comment & Number"
        let scroll = makeScrollableStack()
        let stack = scroll.documentStack
        commentFields.removeAll()
        numberFields.removeAll()

        let cHeader = NSStackView()
        cHeader.orientation = .horizontal
        cHeader.spacing = 8
        cHeader.addArrangedSubview(NSTextField(labelWithString: "Comments"))
        cHeader.addArrangedSubview(stylerButton("Line", styleName: "LINE COMMENTS"))
        cHeader.addArrangedSubview(stylerButton("Block", styleName: "COMMENTS"))
        foldCommentsBox = NSButton(checkboxWithTitle: "Allow fold of comments", target: self, action: #selector(metaChanged(_:)))
        cHeader.addArrangedSubview(foldCommentsBox)
        stack.addArrangedSubview(cHeader)

        for label in ["Line open", "Line continue", "Line close", "Block open", "Block close"] {
            let (row, field) = labeledField("\(label):", width: 220)
            field.delegate = self
            commentFields.append(field)
            stack.addArrangedSubview(row)
        }

        let nHeader = NSStackView()
        nHeader.orientation = .horizontal
        nHeader.spacing = 8
        nHeader.addArrangedSubview(NSTextField(labelWithString: "Numbers"))
        nHeader.addArrangedSubview(stylerButton("Styler", styleName: "NUMBERS"))
        nHeader.addArrangedSubview(NSTextField(labelWithString: "Decimal:"))
        decimalPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        decimalPopup.addItems(withTitles: ["Dot", "Comma", "Both"])
        decimalPopup.target = self
        decimalPopup.action = #selector(metaChanged(_:))
        nHeader.addArrangedSubview(decimalPopup)
        stack.addArrangedSubview(nHeader)

        let numberLabels = [
            ("Numbers, prefix1", "Prefix 1"),
            ("Numbers, prefix2", "Prefix 2"),
            ("Numbers, extras1", "Extras 1"),
            ("Numbers, extras2", "Extras 2"),
            ("Numbers, suffix1", "Suffix 1"),
            ("Numbers, suffix2", "Suffix 2"),
            ("Numbers, range", "Range"),
        ]
        for (key, label) in numberLabels {
            let (row, field) = labeledField("\(label):", width: 280)
            field.identifier = NSUserInterfaceItemIdentifier("kw:\(key)")
            field.delegate = self
            numberFields.append(field)
            stack.addArrangedSubview(row)
        }
        item.view = scroll.scrollView
        return item
    }

    // MARK: Tab 4 — Operators & Delimiters

    private func makeOperatorsTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "ops")
        item.label = "Operators & Delimiters"
        let scroll = makeScrollableStack()
        let stack = scroll.documentStack
        delimiterFields.removeAll()

        let opHeader = NSStackView()
        opHeader.orientation = .horizontal
        opHeader.spacing = 8
        opHeader.addArrangedSubview(NSTextField(labelWithString: "Operators"))
        opHeader.addArrangedSubview(stylerButton("Styler", styleName: "OPERATORS"))
        stack.addArrangedSubview(opHeader)

        stack.addArrangedSubview(NSTextField(labelWithString: "Operators1"))
        let (s1, tv1) = makeTextView(height: 48)
        tv1.delegate = self
        operators1View = tv1
        stack.addArrangedSubview(s1)

        stack.addArrangedSubview(NSTextField(labelWithString: "Operators2"))
        let (s2, tv2) = makeTextView(height: 48)
        tv2.delegate = self
        operators2View = tv2
        stack.addArrangedSubview(s2)

        for d in 1...8 {
            let header = NSStackView()
            header.orientation = .horizontal
            header.spacing = 8
            header.addArrangedSubview(NSTextField(labelWithString: "Delimiter \(d)"))
            header.addArrangedSubview(stylerButton("Styler", styleName: "DELIMITERS\(d)"))
            stack.addArrangedSubview(header)
            var rowFields: [NSTextField] = []
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            for part in ["Open", "Escape", "Close"] {
                row.addArrangedSubview(NSTextField(labelWithString: "\(part):"))
                let f = NSTextField(string: "")
                f.delegate = self
                f.widthAnchor.constraint(equalToConstant: 100).isActive = true
                row.addArrangedSubview(f)
                rowFields.append(f)
            }
            delimiterFields.append(rowFields)
            stack.addArrangedSubview(row)
        }
        item.view = scroll.scrollView
        return item
    }

    // MARK: Controls helpers

    private func roundedButton(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }

    private func stylerButton(_ title: String, styleName: String) -> NSButton {
        let b = NSButton(title: title, target: self, action: #selector(openStyler(_:)))
        b.bezelStyle = .rounded
        b.identifier = NSUserInterfaceItemIdentifier(styleName)
        return b
    }

    private func labeledField(_ label: String, width: CGFloat) -> (NSStackView, NSTextField) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        let lab = NSTextField(labelWithString: label)
        lab.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let field = NSTextField(string: "")
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        row.addArrangedSubview(lab)
        row.addArrangedSubview(field)
        return (row, field)
    }

    private func makeTextView(height: CGFloat) -> (NSScrollView, NSTextView) {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        let tv = NSTextView()
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        tv.autoresizingMask = [.width]
        scroll.documentView = tv
        return (scroll, tv)
    }

    private struct ScrollableStack {
        let scrollView: NSScrollView
        let documentStack: NSStackView
    }

    private func makeScrollableStack() -> ScrollableStack {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: doc.widthAnchor),
        ])
        scroll.documentView = doc
        // Keep document width synced with clip view.
        if let clip = scroll.contentView as NSClipView? {
            doc.widthAnchor.constraint(equalTo: clip.widthAnchor).isActive = true
        }
        return ScrollableStack(scrollView: scroll, documentStack: stack)
    }

    // MARK: - Load / harvest

    private func rebuildPopup() {
        langPopup.removeAllItems()
        let names = store.names
        if names.isEmpty {
            langPopup.addItem(withTitle: current.name)
        } else {
            langPopup.addItems(withTitles: names)
            if let idx = store.index(named: current.name) {
                langPopup.selectItem(at: idx)
            }
        }
    }

    private func loadCurrentIntoUI() {
        loadingUI = true
        defer { loadingUI = false }
        current.ensureDefaults()

        ignoreCaseBox.state = current.caseIgnored ? .on : .off
        extField.stringValue = current.ext
        foldCompactBox.state = current.foldCompact ? .on : .off
        foldCommentsBox.state = current.allowFoldOfComments ? .on : .off
        decimalPopup.selectItem(at: min(max(current.decimalSeparator, 0), 2))

        let folderKeys = [
            "Folders in code1, open", "Folders in code1, middle", "Folders in code1, close",
            "Folders in code2, open", "Folders in code2, middle", "Folders in code2, close",
            "Folders in comment, open", "Folders in comment, middle", "Folders in comment, close",
        ]
        for (i, key) in folderKeys.enumerated() where i < folderFields.count {
            folderFields[i].stringValue = current.keyword(key)
        }

        for i in 0..<8 {
            keywordViews[i].string = current.keyword("Keywords\(i + 1)")
            prefixBoxes[i].state = current.prefix[i] ? .on : .off
        }

        let cf = current.commentFields
        for i in 0..<min(5, commentFields.count) {
            commentFields[i].stringValue = i < cf.count ? cf[i] : ""
        }

        let numKeys = [
            "Numbers, prefix1", "Numbers, prefix2",
            "Numbers, extras1", "Numbers, extras2",
            "Numbers, suffix1", "Numbers, suffix2",
            "Numbers, range",
        ]
        for (i, key) in numKeys.enumerated() where i < numberFields.count {
            numberFields[i].stringValue = current.keyword(key)
        }

        operators1View.string = current.keyword("Operators1")
        operators2View.string = current.keyword("Operators2")

        let dels = current.delimiterFields
        for d in 0..<8 {
            for p in 0..<3 {
                delimiterFields[d][p].stringValue = (d < dels.count && p < dels[d].count) ? dels[d][p] : ""
            }
        }
    }

    private func harvestUIIntoCurrent() {
        current.caseIgnored = ignoreCaseBox.state == .on
        current.ext = extField.stringValue
        current.foldCompact = foldCompactBox.state == .on
        current.allowFoldOfComments = foldCommentsBox.state == .on
        current.decimalSeparator = decimalPopup.indexOfSelectedItem

        let folderKeys = [
            "Folders in code1, open", "Folders in code1, middle", "Folders in code1, close",
            "Folders in code2, open", "Folders in code2, middle", "Folders in code2, close",
            "Folders in comment, open", "Folders in comment, middle", "Folders in comment, close",
        ]
        for (i, key) in folderKeys.enumerated() where i < folderFields.count {
            current.setKeyword(key, folderFields[i].stringValue)
        }

        for i in 0..<8 {
            current.setKeyword("Keywords\(i + 1)", keywordViews[i].string)
            current.prefix[i] = prefixBoxes[i].state == .on
        }

        current.commentFields = commentFields.map(\.stringValue)

        let numKeys = [
            "Numbers, prefix1", "Numbers, prefix2",
            "Numbers, extras1", "Numbers, extras2",
            "Numbers, suffix1", "Numbers, suffix2",
            "Numbers, range",
        ]
        for (i, key) in numKeys.enumerated() where i < numberFields.count {
            current.setKeyword(key, numberFields[i].stringValue)
        }

        current.setKeyword("Operators1", operators1View.string)
        current.setKeyword("Operators2", operators2View.string)
        current.delimiterFields = delimiterFields.map { $0.map(\.stringValue) }
        current.udlVersion = "2.1"
        current.ensureDefaults()
    }

    private func commitCurrent() {
        harvestUIIntoCurrent()
        store.upsert(current)
    }

    // MARK: - Actions

    @objc private func langPopupChanged(_ sender: Any?) {
        guard !loadingUI, let name = langPopup.titleOfSelectedItem else { return }
        commitCurrent()
        if let lang = store.language(named: name) {
            current = lang
            loadCurrentIntoUI()
        }
    }

    @objc private func metaChanged(_ sender: Any?) {
        guard !loadingUI else { return }
        // Live-bind; persisted on Save.
        harvestUIIntoCurrent()
    }

    @objc private func createNew(_ sender: Any?) {
        commitCurrent()
        var name = "new user define"
        var n = 1
        while store.index(named: name) != nil {
            n += 1
            name = "new user define \(n)"
        }
        current = .blank(name: name)
        store.upsert(current)
        rebuildPopup()
        langPopup.selectItem(withTitle: name)
        loadCurrentIntoUI()
    }

    @objc private func saveAction(_ sender: Any?) {
        commitCurrent()
        do {
            try store.save()
            // Also write individual file under userDefineLangs for Import/Export parity.
            let dest = UDLStore.langsFolderURL
                .appendingPathComponent("\(current.name.replacingOccurrences(of: "/", with: "_")).udl.xml")
            try UDLXML.serializeSingle(current).write(to: dest, atomically: true, encoding: .utf8)
            MenuBuilder.rebuildUserDefinedSubmenu(names: store.names)
            notifyApplyToEngine(path: UDLStore.multiLangURL.path, name: current.name)
            presentAlert(title: "Saved", info: "Wrote \(UDLStore.multiLangURL.path)")
        } catch {
            presentAlert(title: "Save failed", info: error.localizedDescription)
        }
    }

    @objc private func saveAsAction(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Save User Language As…"
        alert.informativeText = "Enter a new language name."
        let input = NSTextField(string: current.name + " copy")
        input.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        commitCurrent()
        var copy = current
        copy.name = name
        if store.index(named: name) != nil {
            presentAlert(title: "Name in use", info: "A language named “\(name)” already exists.")
            return
        }
        current = copy
        store.upsert(current)
        rebuildPopup()
        langPopup.selectItem(withTitle: name)
        saveAction(nil)
    }

    @objc private func renameAction(_ sender: Any?) {
        let old = current.name
        let alert = NSAlert()
        alert.messageText = "Rename User Language"
        let input = NSTextField(string: old)
        input.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            commitCurrent()
            try store.rename(from: old, to: name)
            current.name = name
            rebuildPopup()
            langPopup.selectItem(withTitle: name)
            try store.save()
            MenuBuilder.rebuildUserDefinedSubmenu(names: store.names)
        } catch {
            presentAlert(title: "Rename failed", info: error.localizedDescription)
        }
    }

    @objc private func removeAction(_ sender: Any?) {
        let name = current.name
        let alert = NSAlert()
        alert.messageText = "Remove “\(name)”?"
        alert.informativeText = "This removes the language from the store and saves."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.remove(named: name)
        if store.languages.isEmpty {
            current = .blank()
            store.upsert(current)
        } else {
            current = store.languages[0]
        }
        do { try store.save() } catch {
            presentAlert(title: "Save failed", info: error.localizedDescription)
        }
        rebuildPopup()
        loadCurrentIntoUI()
        MenuBuilder.rebuildUserDefinedSubmenu(names: store.names)
    }

    @objc private func importAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.xml]
        panel.message = "Import Notepad++ User Defined Language (.udl.xml)"
        panel.beginSheetModal(for: window!) { [weak self] result in
            guard let self, result == .OK else { return }
            var last: String?
            for url in panel.urls {
                do {
                    let names = try self.store.importFile(at: url)
                    last = names.last
                    self.notifyApplyToEngine(path: UDLStore.multiLangURL.path, name: last)
                } catch {
                    self.presentAlert(title: "Import failed", info: error.localizedDescription)
                }
            }
            self.rebuildPopup()
            if let last, let lang = self.store.language(named: last) {
                self.current = lang
                self.langPopup.selectItem(withTitle: last)
                self.loadCurrentIntoUI()
            }
            MenuBuilder.rebuildUserDefinedSubmenu(names: self.store.names)
        }
    }

    @objc private func exportAction(_ sender: Any?) {
        commitCurrent()
        store.upsert(current)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = "\(current.name).udl.xml"
        panel.beginSheetModal(for: window!) { [weak self] result in
            guard let self, result == .OK, let url = panel.url else { return }
            do {
                try self.store.export(named: self.current.name, to: url)
            } catch {
                self.presentAlert(title: "Export failed", info: error.localizedDescription)
            }
        }
    }

    /// Ask the main window to reload UDL into the LexUser highlight engine.
    private func notifyApplyToEngine(path: String, name: String? = nil) {
        var info: [String: Any] = ["path": path]
        if let name { info["name"] = name }
        NotificationCenter.default.post(
            name: UDLEditorWindow.didRequestApplyNotification,
            object: nil,
            userInfo: info
        )
    }

    static let didRequestApplyNotification = Notification.Name("NppMac.UDLEditor.didRequestApply")

    private func presentAlert(title: String, info: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: "OK")
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    // MARK: - Styler sheet

    @objc private func openStyler(_ sender: Any?) {
        commitCurrent()
        guard let btn = sender as? NSButton else { return }
        stylerTargetName = btn.identifier?.rawValue ?? "DEFAULT"
        showStylerSheet()
    }

    private func showStylerSheet() {
        if stylerPanel == nil { buildStylerPanel() }
        guard let panel = stylerPanel, let window else { return }

        let style = current.styles.first(where: { $0.name == stylerTargetName })
            ?? UDLStyle.blank(name: stylerTargetName)

        stylerFgWell.color = color(fromHex: style.fgColor) ?? .black
        stylerBgWell.color = color(fromHex: style.bgColor) ?? .white
        stylerBold.state = (style.fontStyle & 1) != 0 ? .on : .off
        stylerItalic.state = (style.fontStyle & 2) != 0 ? .on : .off
        stylerUnderline.state = (style.fontStyle & 4) != 0 ? .on : .off
        stylerFontName.stringValue = style.fontName
        stylerFontSize.stringValue = style.fontSize
        for (i, flag) in UDLLanguage.nestingFlags.enumerated() where i < stylerNestingBoxes.count {
            stylerNestingBoxes[i].state = (style.nesting & flag.mask) != 0 ? .on : .off
        }
        panel.title = "Styler — \(stylerTargetName)"
        window.beginSheet(panel)
    }

    private func buildStylerPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            root.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            root.bottomAnchor.constraint(lessThanOrEqualTo: panel.contentView!.bottomAnchor),
        ])

        let fontRow = NSStackView()
        fontRow.orientation = .horizontal
        fontRow.spacing = 8
        fontRow.addArrangedSubview(NSTextField(labelWithString: "Font:"))
        stylerFontName = NSTextField(string: "")
        stylerFontName.widthAnchor.constraint(equalToConstant: 140).isActive = true
        fontRow.addArrangedSubview(stylerFontName)
        fontRow.addArrangedSubview(NSTextField(labelWithString: "Size:"))
        stylerFontSize = NSTextField(string: "")
        stylerFontSize.widthAnchor.constraint(equalToConstant: 48).isActive = true
        fontRow.addArrangedSubview(stylerFontSize)
        root.addArrangedSubview(fontRow)

        let styleRow = NSStackView()
        styleRow.orientation = .horizontal
        styleRow.spacing = 12
        stylerBold = NSButton(checkboxWithTitle: "Bold", target: nil, action: nil)
        stylerItalic = NSButton(checkboxWithTitle: "Italic", target: nil, action: nil)
        stylerUnderline = NSButton(checkboxWithTitle: "Underline", target: nil, action: nil)
        styleRow.addArrangedSubview(stylerBold)
        styleRow.addArrangedSubview(stylerItalic)
        styleRow.addArrangedSubview(stylerUnderline)
        root.addArrangedSubview(styleRow)

        let colorRow = NSStackView()
        colorRow.orientation = .horizontal
        colorRow.spacing = 12
        colorRow.addArrangedSubview(NSTextField(labelWithString: "Foreground:"))
        stylerFgWell = NSColorWell()
        stylerFgWell.widthAnchor.constraint(equalToConstant: 48).isActive = true
        colorRow.addArrangedSubview(stylerFgWell)
        colorRow.addArrangedSubview(NSTextField(labelWithString: "Background:"))
        stylerBgWell = NSColorWell()
        stylerBgWell.widthAnchor.constraint(equalToConstant: 48).isActive = true
        colorRow.addArrangedSubview(stylerBgWell)
        root.addArrangedSubview(colorRow)

        root.addArrangedSubview(NSTextField(labelWithString: "Nesting"))
        stylerNestingBoxes.removeAll()
        let nestGrid = NSStackView()
        nestGrid.orientation = .vertical
        nestGrid.spacing = 4
        nestGrid.alignment = .leading
        var row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        for (i, flag) in UDLLanguage.nestingFlags.enumerated() {
            if i > 0 && i % 3 == 0 {
                nestGrid.addArrangedSubview(row)
                row = NSStackView()
                row.orientation = .horizontal
                row.spacing = 8
            }
            let box = NSButton(checkboxWithTitle: flag.label, target: nil, action: nil)
            stylerNestingBoxes.append(box)
            row.addArrangedSubview(box)
        }
        nestGrid.addArrangedSubview(row)
        root.addArrangedSubview(nestGrid)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttons.addArrangedSubview(spacer)
        buttons.addArrangedSubview(roundedButton("Cancel", #selector(stylerCancel(_:))))
        let ok = roundedButton("OK", #selector(stylerOK(_:)))
        ok.keyEquivalent = "\r"
        buttons.addArrangedSubview(ok)
        root.addArrangedSubview(buttons)

        stylerPanel = panel
    }

    @objc private func stylerCancel(_ sender: Any?) {
        guard let panel = stylerPanel else { return }
        window?.endSheet(panel)
    }

    @objc private func stylerOK(_ sender: Any?) {
        var nesting: UInt32 = 0
        for (i, box) in stylerNestingBoxes.enumerated() where box.state == .on {
            if i < UDLLanguage.nestingFlags.count {
                nesting |= UDLLanguage.nestingFlags[i].mask
            }
        }
        var fontStyle = 0
        if stylerBold.state == .on { fontStyle |= 1 }
        if stylerItalic.state == .on { fontStyle |= 2 }
        if stylerUnderline.state == .on { fontStyle |= 4 }

        current.updateStyle(named: stylerTargetName) { st in
            st.fgColor = hex(from: stylerFgWell.color)
            st.bgColor = hex(from: stylerBgWell.color)
            st.fontStyle = fontStyle
            st.fontName = stylerFontName.stringValue
            st.fontSize = stylerFontSize.stringValue
            st.nesting = nesting
            st.colorStyle = 1
        }
        store.upsert(current)
        if let panel = stylerPanel {
            window?.endSheet(panel)
        }
    }

    // MARK: - Color helpers

    private func hex(from color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        return String(format: "%02X%02X%02X", r, g, b)
    }

    private func color(fromHex hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    // MARK: - Delegates

    func controlTextDidChange(_ obj: Notification) {
        guard !loadingUI else { return }
        harvestUIIntoCurrent()
    }

    func textDidChange(_ notification: Notification) {
        guard !loadingUI else { return }
        harvestUIIntoCurrent()
    }
}
