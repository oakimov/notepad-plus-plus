import AppKit
import CryptoKit
import UniformTypeIdentifiers

/// Main window: internal tab bar + editor view + status bar + find panel.
final class MainWindowController: NSWindowController {
    private let store: DocumentStore
    private let textView: NSTextView
    private let statusLabel: NSTextField
    private var tabBar: TabBarView?
    private var findPanel: FindPanel?
    private var folderPanel: FolderBrowserPanel?
    private var functionListPanel: FunctionListPanel?
    private var folderWidth: NSLayoutConstraint?
    private var functionWidth: NSLayoutConstraint?
    private var folderVisible = false
    private var functionListVisible = false
    private var diskWatchTimer: Timer?
    private var knownMtimes: [String: Date] = [:]
    private var macroRecording = false
    private var macroSteps: [String] = []
    private weak var editorScroll: NSScrollView?
    private var lineNumberRuler: LineNumberRulerView?
    private var wordWrapEnabled = false
    private var lineNumbersVisible = true
    private var editorFontSize: CGFloat = 13
    /// Bookmarked line indices (0-based) per document index.
    private var bookmarksByDoc: [Int: Set<Int>] = [:]
    /// Editor bottom → find panel top (find visible) or → status bar top (hidden).
    private var editorAboveFind: NSLayoutConstraint?
    private var editorAboveStatus: NSLayoutConstraint?
    private var statusHeight: NSLayoutConstraint?
    private var syncingText = false
    /// Editor holds edits not yet pushed into the Rust buffer (sync is debounced).
    private var editorNeedsSync = false
    private var syncWorkItem: DispatchWorkItem?
    private var highlightWorkItem: DispatchWorkItem?
    /// Set once the user resolved every unsaved document for window close / quit.
    private var closeConfirmed = false

    private static let defaultFontSize: CGFloat = 13

    private var editorFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: editorFontSize, weight: .regular)
    }

    init(documents store: DocumentStore) {
        self.store = store
        textView = Self.makeTextView()
        statusLabel = NSTextField(labelWithString: "")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NppMac"
        window.isReleasedWhenClosed = false
        window.center()
        // NSWindowController only calls loadWindow() for nib-backed controllers, so the
        // programmatic window must be handed over here or `window` stays nil forever.
        super.init(window: window)
        window.delegate = self
        textView.delegate = self
        buildContent(in: window)
        applyPrefsFromStore()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(prefsDidChange(_:)),
            name: .nppPrefsDidChange,
            object: nil
        )
        startDiskWatchIfNeeded()
        refresh()
    }

    deinit {
        diskWatchTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static func makeTextView() -> NSTextView {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        // No word wrap (Notepad++ default): container never tracks the view width.
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = false
        tv.font = NSFont.monospacedSystemFont(ofSize: defaultFontSize, weight: .regular)
        tv.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: defaultFontSize, weight: .regular),
            .foregroundColor: NSColor.textColor,
        ]
        tv.allowsUndo = true
        tv.isRichText = false
        tv.importsGraphics = false
        tv.usesFontPanel = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        return tv
    }

    private func buildContent(in window: NSWindow) {
        let root = NSView(frame: .zero)
        window.contentView = root

        let tabs = TabBarView(
            store: store,
            onSelect: { [weak self] in self?.refresh() },
            onClose: { [weak self] idx in self?.closeTab(at: idx) },
            syncBeforeSelect: { [weak self] in self?.syncEditorToStore() }
        )
        tabBar = tabs

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = textView
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        let ruler = LineNumberRulerView(scrollView: scroll, textView: textView)
        scroll.verticalRulerView = ruler
        lineNumberRuler = ruler
        editorScroll = scroll

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(editorBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scroll.contentView
        )
        scroll.contentView.postsBoundsChangedNotifications = true

        let find = FindPanel(
            onFind: { [weak self] in self?.performFind($0) },
            onHide: { [weak self] in self?.setFindVisible(false) }
        )
        find.isHidden = true
        findPanel = find

        let folder = FolderBrowserPanel()
        folder.onOpenFile = { [weak self] url in self?.openPaths([url.path]) }
        folder.isHidden = true
        folderPanel = folder

        let functions = FunctionListPanel()
        functions.onJump = { [weak self] line in self?.goToLineNumber(line) }
        functions.isHidden = true
        functionListPanel = functions

        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for view in [tabs, folder, scroll, functions, find, statusLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        let aboveFind = scroll.bottomAnchor.constraint(equalTo: find.topAnchor)
        let aboveStatus = scroll.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -2)
        let statusH = statusLabel.heightAnchor.constraint(equalToConstant: 0)
        let folderW = folder.widthAnchor.constraint(equalToConstant: 0)
        let functionW = functions.widthAnchor.constraint(equalToConstant: 0)
        editorAboveFind = aboveFind
        editorAboveStatus = aboveStatus
        statusHeight = statusH
        folderWidth = folderW
        functionWidth = functionW
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: root.topAnchor),
            tabs.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            folder.topAnchor.constraint(equalTo: tabs.bottomAnchor),
            folder.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            folder.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -2),
            folderW,

            functions.topAnchor.constraint(equalTo: tabs.bottomAnchor),
            functions.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            functions.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -2),
            functionW,

            scroll.topAnchor.constraint(equalTo: tabs.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: folder.trailingAnchor),
            scroll.trailingAnchor.constraint(equalTo: functions.leadingAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            aboveStatus,

            find.leadingAnchor.constraint(equalTo: folder.trailingAnchor),
            find.trailingAnchor.constraint(equalTo: functions.leadingAnchor),
            find.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -2),

            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            statusLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -3),
        ])
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(textView)
    }

    // MARK: - Editor ⇄ store

    /// Push pending editor edits into the selected Rust buffer.
    private func syncEditorToStore() {
        syncWorkItem?.cancel()
        syncWorkItem = nil
        guard editorNeedsSync, store.selected != nil else { return }
        editorNeedsSync = false
        store.updateSelected(text: textView.string)
    }

    /// Load the selected document into the editor and redraw tabs/title/status.
    private func refresh() {
        tabBar?.reload()
        guard let meta = store.selectedMeta() else { return }
        let body = store.text(at: store.selectedIndex)
        if textView.string != body {
            syncingText = true
            textView.breakUndoCoalescing()
            textView.string = body
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
            syncingText = false
        }
        editorNeedsSync = false
        updateChrome(
            title: meta.title,
            isDirty: meta.isDirty,
            encoding: meta.encodingLabel,
            language: meta.languageDisplay,
            eol: meta.eolLabel
        )
        scheduleHighlight()
        refreshLineNumbers()
        refreshFunctionList()
        recordKnownMtimes()
    }

    private func updateChrome(title: String, isDirty: Bool, encoding: String, language: String, eol: String) {
        window?.title = isDirty ? "\(title) •" : title
        window?.representedURL = store.selectedMeta()?.fileURL
        let text = textView.string
        let lines = text.utf8.lazy.filter { $0 == UInt8(ascii: "\n") }.count + 1
        let caret = textView.selectedRange().location
        let (ln, col) = lineColumn(at: caret, in: text)
        statusLabel.stringValue =
            "Ln \(ln), Col \(col) — \(lines) lines — \(encoding) — \(eol) — \(language)"
    }

    private func lineColumn(at utf16: Int, in text: String) -> (Int, Int) {
        let ns = text as NSString
        let clamped = max(0, min(utf16, ns.length))
        var line = 1
        var col = 1
        var i = 0
        while i < clamped {
            let ch = ns.character(at: i)
            if ch == 10 { // \n
                line += 1
                col = 1
            } else {
                col += 1
            }
            i += 1
        }
        return (line, col)
    }

    private func scheduleSync() {
        syncWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.syncEditorToStore()
            self.tabBar?.reload()
            if let meta = self.store.selectedMeta() {
                self.updateChrome(
                    title: meta.title,
                    isDirty: meta.isDirty,
                    encoding: meta.encodingLabel,
                    language: meta.languageDisplay,
                    eol: meta.eolLabel
                )
            }
            self.refreshLineNumbers()
            self.refreshFunctionList()
        }
        syncWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func scheduleHighlight() {
        highlightWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyHighlight() }
        highlightWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func applyHighlight() {
        guard let meta = store.selectedMeta(), let storage = textView.textStorage else { return }
        let text = textView.string
        if text.isEmpty || text.utf8.count > 512 * 1024 { return }
        let tokens = store.highlight(language: meta.language, text: text)
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: editorFont, .foregroundColor: NSColor.textColor], range: full)
        for t in tokens {
            let end = NSMaxRange(t.range)
            guard t.range.location >= 0, end <= storage.length else { continue }
            let color = store.color(forScope: t.scope, language: meta.language)
            storage.addAttribute(.foregroundColor, value: color, range: t.range)
        }
        storage.endEditing()
        refreshLineNumbers()
    }

    /// Replace `range` through NSTextView so the edit is undoable and flows back via `textDidChange`.
    private func replaceEditorText(in range: NSRange, with replacement: String) {
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
    }

    /// Replace the whole editor text, touching only the span that actually changed.
    private func applyEditorText(_ newText: String, caret: Int? = nil) {
        let old = textView.string as NSString
        let new = newText as NSString
        let minLen = min(old.length, new.length)
        var start = 0
        while start < minLen, old.character(at: start) == new.character(at: start) { start += 1 }
        if start > 0, UTF16.isLeadSurrogate(old.character(at: start - 1)) { start -= 1 }
        var suffix = 0
        while suffix < minLen - start,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        if suffix > 0, UTF16.isTrailSurrogate(old.character(at: old.length - suffix)) { suffix -= 1 }
        let range = NSRange(location: start, length: old.length - start - suffix)
        let replacement = new.substring(with: NSRange(location: start, length: new.length - start - suffix))
        if range.length > 0 || !replacement.isEmpty {
            replaceEditorText(in: range, with: replacement)
        }
        if let caret {
            let at = NSRange(location: min(caret, new.length), length: 0)
            textView.setSelectedRange(at)
            textView.scrollRangeToVisible(at)
        }
    }

    // MARK: - Tabs / closing

    private enum SaveOutcome { case saved, discarded, cancelled }

    /// Ask Save / Don't Save / Cancel for the document at `index`.
    private func promptToSave(at index: Int, done: @escaping (SaveOutcome) -> Void) {
        guard let window else { done(.cancelled); return }
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(store.title(at: index))”?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.saveDocument(at: index) { done($0 ? .saved : .cancelled) }
            case .alertSecondButtonReturn:
                done(.discarded)
            default:
                done(.cancelled)
            }
        }
    }

    /// Close one tab, prompting when dirty. `done(true)` once it is closed.
    private func closeTab(at index: Int, done: ((Bool) -> Void)? = nil) {
        syncEditorToStore()
        guard (0..<store.count).contains(index), window?.attachedSheet == nil else { done?(false); return }
        guard store.isDirty(at: index) else {
            store.close(at: index)
            refresh()
            done?(true)
            return
        }
        store.select(at: index)
        refresh()
        promptToSave(at: index) { [weak self] outcome in
            guard let self else { return }
            guard outcome != .cancelled else { done?(false); return }
            self.store.close(at: index)
            self.refresh()
            done?(true)
        }
    }

    /// Close the first `remaining` tabs one by one (stops if the user cancels).
    private func closeTabs(remaining: Int) {
        guard remaining > 0 else { return }
        closeTab(at: 0) { [weak self] closed in
            if closed { self?.closeTabs(remaining: remaining - 1) }
        }
    }

    var hasUnsavedDocuments: Bool {
        guard !closeConfirmed else { return false }
        syncEditorToStore()
        return store.tabs.contains { $0.isDirty }
    }

    /// Resolve every unsaved document (save or discard) before window close / quit.
    /// `done(false)` if the user cancelled.
    func confirmCloseAll(_ done: @escaping (Bool) -> Void) {
        syncEditorToStore()
        resolveUnsaved(from: 0) { [weak self] proceed in
            if proceed { self?.closeConfirmed = true }
            done(proceed)
        }
    }

    private func resolveUnsaved(from start: Int, done: @escaping (Bool) -> Void) {
        guard let index = (start..<max(start, store.count)).first(where: { store.isDirty(at: $0) }) else {
            done(true)
            return
        }
        store.select(at: index)
        refresh()
        promptToSave(at: index) { [weak self] outcome in
            guard let self, outcome != .cancelled else { done(false); return }
            self.resolveUnsaved(from: index + 1, done: done)
        }
    }

    // MARK: - File

    @objc func fileNew(_ sender: Any?) {
        syncEditorToStore()
        store.newDocument()
        refresh()
    }

    @objc func fileOpen(_ sender: Any?) {
        syncEditorToStore()
        guard let window, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if let dir = store.selectedMeta()?.fileURL?.deletingLastPathComponent() {
            panel.directoryURL = dir
        }
        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK else { return }
            let urls = panel.urls
            // Let the open panel's sheet finish closing before a failure alert may attach.
            DispatchQueue.main.async { self.open(urls: urls) }
        }
    }

    /// Open paths from argv / Finder / `NPP_OPEN` (QA and double-click).
    func openPaths(_ paths: [String]) {
        open(urls: paths.map { URL(fileURLWithPath: $0) })
        showWindow(nil)
    }

    private func open(urls: [URL]) {
        syncEditorToStore()
        var failed: [String] = []
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if let existing = store.index(of: url) {
                store.select(at: existing)
                continue
            }
            // Notepad++ replaces the untouched startup "new 1" tab with the first opened file.
            let replaceFresh = store.count == 1
                && store.tabs.first.map { $0.fileURL == nil && !$0.isDirty } == true
                && store.text(at: 0).isEmpty
            if store.openDocument(url: url) {
                if replaceFresh { store.close(at: 0) }
                SessionStore.pushRecent(url.path)
            } else {
                failed.append(url.lastPathComponent)
            }
        }
        refresh()
        persistSession()
        MenuBuilder.reloadRecentFiles(target: self)
        guard !failed.isEmpty, let window else { return }
        let alert = NSAlert()
        alert.messageText = failed.count == 1
            ? "Could not open “\(failed[0])”"
            : "Could not open \(failed.count) files"
        alert.informativeText = "Missing, unreadable, or larger than the 32 MB open limit."
        alert.alertStyle = .warning
        if window.attachedSheet == nil {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    @objc func fileReload(_ sender: Any?) {
        syncEditorToStore()
        let index = store.selectedIndex
        guard let url = store.selectedMeta()?.fileURL, let window, window.attachedSheet == nil else { return }
        let reload = { [weak self] in
            guard let self else { return }
            guard self.store.openDocument(url: url) else {
                self.presentError(CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path]))
                return
            }
            // Reopened copy lands at the end; put it where the old tab was.
            self.store.moveTab(from: self.store.count - 1, to: index)
            self.store.close(at: index + 1)
            self.store.select(at: index)
            self.refresh()
        }
        guard store.isDirty(at: index) else { reload(); return }
        let alert = NSAlert()
        alert.messageText = "Reload “\(store.title(at: index))” from disk?"
        alert.informativeText = "Unsaved changes will be lost."
        alert.addButton(withTitle: "Reload")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { reload() }
        }
    }

    @objc func fileSave(_ sender: Any?) {
        syncEditorToStore()
        saveDocument(at: store.selectedIndex) { [weak self] _ in self?.refresh() }
    }

    @objc func fileSaveAs(_ sender: Any?) {
        syncEditorToStore()
        let index = store.selectedIndex
        guard (0..<store.count).contains(index) else { return }
        runSavePanel(for: index) { [weak self] _ in self?.refresh() }
    }

    @objc func fileSaveAll(_ sender: Any?) {
        syncEditorToStore()
        for (i, doc) in store.tabs.enumerated() where doc.isDirty {
            guard doc.fileURL != nil else { continue }
            do {
                try store.save(at: i)
            } catch {
                presentError(error)
                break
            }
        }
        refresh()
    }

    @objc func fileClose(_ sender: Any?) { closeTab(at: store.selectedIndex) }

    @objc func fileCloseAll(_ sender: Any?) {
        syncEditorToStore()
        closeTabs(remaining: store.count)
    }

    @objc func fileCloseOthers(_ sender: Any?) {
        syncEditorToStore()
        let keep = store.selectedIndex
        // Close from the end so indices stay valid.
        for i in stride(from: store.count - 1, through: 0, by: -1) where i != keep {
            closeTab(at: i)
        }
    }

    @objc func fileOpenContainingFolder(_ sender: Any?) {
        guard let url = store.selectedMeta()?.fileURL else { NSSound.beep(); return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func fileCopyPath(_ sender: Any?) {
        guard let path = store.selectedMeta()?.fileURL?.path else { NSSound.beep(); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    @objc func fileRename(_ sender: Any?) {
        syncEditorToStore()
        let index = store.selectedIndex
        guard (0..<store.count).contains(index),
              let url = store.tabs[index].fileURL
        else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = "New file name:"
        let field = NSTextField(string: url.lastPathComponent)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != url.lastPathComponent else { return }
        let dest = url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            try store.save(at: index, to: dest)
            SessionStore.pushRecent(dest.path)
            persistSession()
            MenuBuilder.reloadRecentFiles(target: self)
            refresh()
        } catch {
            presentError(error)
        }
    }

    @objc func fileDelete(_ sender: Any?) {
        syncEditorToStore()
        let index = store.selectedIndex
        guard (0..<store.count).contains(index),
              let url = store.tabs[index].fileURL
        else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(url.lastPathComponent)”?"
        alert.informativeText = "The file will be moved to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            store.close(at: index)
            persistSession()
            refresh()
        } catch {
            presentError(error)
        }
    }

    @objc func filePrint(_ sender: Any?) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        let op = NSPrintOperation(view: textView, printInfo: info)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.run()
    }

    private func saveDocument(at index: Int, done: @escaping (Bool) -> Void) {
        guard (0..<store.count).contains(index) else { done(false); return }
        guard store.tabs[index].fileURL != nil else {
            runSavePanel(for: index, done: done)
            return
        }
        do {
            if let url = store.tabs[index].fileURL {
                maybeBackup(url)
            }
            try store.save(at: index)
            if let url = store.tabs[index].fileURL {
                SessionStore.pushRecent(url.path)
                knownMtimes[url.path] = Self.mtime(of: url)
            }
            persistSession()
            MenuBuilder.reloadRecentFiles(target: self)
            done(true)
        } catch {
            presentError(error)
            done(false)
        }
    }

    /// Paths of open documents with a file URL (for session.xml).
    func sessionPaths() -> [String] {
        store.tabs.compactMap { $0.fileURL?.path }
    }

    func persistSession() {
        SessionStore.saveSession(paths: sessionPaths())
    }

    /// Restore last session if no argv/Finder files were opened.
    func restoreSessionIfNeeded() {
        guard AppPrefs.restoreSession else { return }
        let paths = SessionStore.loadSession()
        guard !paths.isEmpty else { return }
        openPaths(paths)
    }

    @objc func openRecentFile(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let path = item.representedObject as? String else { return }
        openPaths([path])
    }

    @objc func clearRecentFiles(_ sender: Any?) {
        try? "".write(to: SessionStore.recentURL, atomically: true, encoding: .utf8)
        MenuBuilder.reloadRecentFiles(target: self)
    }

    private func runSavePanel(for index: Int, done: @escaping (Bool) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = store.title(at: index)
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            guard let self, result == .OK, let url = panel.url else { done(false); return }
            do {
                // Save As: no prior file to back up at dest.
                try self.store.save(at: index, to: url)
                SessionStore.pushRecent(url.path)
                self.knownMtimes[url.path] = Self.mtime(of: url)
                self.persistSession()
                MenuBuilder.reloadRecentFiles(target: self)
                done(true)
            } catch {
                self.presentError(error)
                done(false)
            }
        }
        if let window, window.attachedSheet == nil {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    // MARK: - Edit

    @objc func editUndo(_ sender: Any?) { currentUndoManager?.undo() }
    @objc func editRedo(_ sender: Any?) { currentUndoManager?.redo() }

    /// Undo stack of whatever has focus (editor ⇒ per-document manager, find field ⇒ its own).
    private var currentUndoManager: UndoManager? {
        window?.firstResponder?.undoManager
    }

    @objc func editDuplicateLine(_ sender: Any?) { transformCurrentLine { lines, i in lines.insert(lines[i], at: i) } }
    @objc func editJoinLines(_ sender: Any?) {
        transformCurrentLine { lines, i in
            guard i + 1 < lines.count else { return }
            lines[i] += " " + lines.remove(at: i + 1)
        }
    }
    @objc func editMoveUp(_ sender: Any?) { moveCurrentLine(by: -1) }
    @objc func editMoveDown(_ sender: Any?) { moveCurrentLine(by: 1) }
    @objc func editUpperCase(_ sender: Any?) { transformSelection { $0.uppercased() } }
    @objc func editLowerCase(_ sender: Any?) { transformSelection { $0.lowercased() } }
    @objc func editTrimTrailing(_ sender: Any?) {
        let caret = textView.selectedRange().location
        let text = textView.string.components(separatedBy: "\n").map {
            $0.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
        }.joined(separator: "\n")
        applyEditorText(text, caret: caret)
    }

    @objc func editToggleComment(_ sender: Any?) {
        let token = commentToken(for: store.selectedMeta()?.language ?? "normal")
        guard !token.isEmpty else { return }
        let text = textView.string
        let caret = textView.selectedRange().location
        var lines = text.components(separatedBy: "\n")
        let i = lineIndex(at: caret, in: text)
        guard lines.indices.contains(i) else { return }
        let needComment = !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(token)
        if needComment {
            let indent = lines[i].prefix(while: { $0 == " " || $0 == "\t" }).count
            let idx = lines[i].index(lines[i].startIndex, offsetBy: indent)
            lines[i].insert(contentsOf: token + " ", at: idx)
        } else if let range = lines[i].range(of: token) {
            var end = range.upperBound
            if lines[i][end...].hasPrefix(" ") {
                end = lines[i].index(after: end)
            }
            lines[i].removeSubrange(range.lowerBound..<end)
        }
        applyEditorText(lines.joined(separator: "\n"), caret: caret)
    }

    @objc func editSortLines(_ sender: Any?) {
        let caret = textView.selectedRange().location
        var lines = textView.string.components(separatedBy: "\n")
        let trailing = textView.string.hasSuffix("\n")
        if trailing, lines.last == "" { lines.removeLast() }
        lines.sort()
        var out = lines.joined(separator: "\n")
        if trailing { out += "\n" }
        applyEditorText(out, caret: caret)
    }

    @objc func editIndent(_ sender: Any?) {
        transformCurrentLine { lines, i in lines[i] = "\t" + lines[i] }
    }

    @objc func editUnindent(_ sender: Any?) {
        transformCurrentLine { lines, i in
            if lines[i].hasPrefix("\t") {
                lines[i].removeFirst()
            } else if lines[i].hasPrefix("    ") {
                lines[i].removeFirst(4)
            } else if lines[i].hasPrefix(" ") {
                lines[i].removeFirst()
            }
        }
    }

    private func commentToken(for language: String) -> String {
        switch language {
        case "python", "ruby", "bash", "yaml", "toml", "perl", "r", "cmake":
            return "#"
        case "lua", "sql", "haskell":
            return "--"
        case "vb", "vbnet":
            return "'"
        case "matlab":
            return "%"
        case "html", "xml", "markdown":
            return "" // block comments only; skip for now
        default:
            return "//"
        }
    }

    private func transformSelection(_ f: (String) -> String) {
        let range = textView.selectedRange()
        guard range.length > 0 else { return }
        let selected = (textView.string as NSString).substring(with: range)
        let replaced = f(selected)
        replaceEditorText(in: range, with: replaced)
        textView.setSelectedRange(NSRange(location: range.location, length: (replaced as NSString).length))
    }

    private func transformCurrentLine(_ f: (inout [String], Int) -> Void) {
        let text = textView.string
        let caret = textView.selectedRange().location
        var lines = text.components(separatedBy: "\n")
        let i = lineIndex(at: caret, in: text)
        guard lines.indices.contains(i) else { return }
        f(&lines, i)
        applyEditorText(lines.joined(separator: "\n"), caret: caret)
    }

    private func moveCurrentLine(by delta: Int) {
        let text = textView.string
        let caret = textView.selectedRange().location
        var lines = text.components(separatedBy: "\n")
        let i = lineIndex(at: caret, in: text)
        let j = i + delta
        guard lines.indices.contains(i), lines.indices.contains(j) else { return }
        let column = caret - lines[..<i].reduce(0) { $0 + $1.utf16.count + 1 }
        lines.swapAt(i, j)
        let lineStart = lines[..<j].reduce(0) { $0 + $1.utf16.count + 1 }
        applyEditorText(lines.joined(separator: "\n"), caret: lineStart + column)
    }

    private func lineIndex(at utf16offset: Int, in text: String) -> Int {
        let idx = String.Index(utf16Offset: min(utf16offset, text.utf16.count), in: text)
        return text[..<idx].utf8.lazy.filter { $0 == UInt8(ascii: "\n") }.count
    }

    // MARK: - Search

    private func setFindVisible(_ visible: Bool) {
        guard let findPanel else { return }
        findPanel.isHidden = !visible
        editorAboveStatus?.isActive = !visible
        editorAboveFind?.isActive = visible
        if !visible { window?.makeFirstResponder(textView) }
    }

    @objc func searchFind(_ sender: Any?) { setFindVisible(true); findPanel?.focusFind() }
    @objc func searchReplace(_ sender: Any?) { setFindVisible(true); findPanel?.focusReplace() }
    @objc func searchFindNext(_ sender: Any?) { setFindVisible(true); stepFind(forward: true) }
    @objc func searchFindPrev(_ sender: Any?) { setFindVisible(true); stepFind(forward: false) }

    @objc func searchFindInFiles(_ sender: Any?) {
        guard let window, window.attachedSheet == nil else { return }
        setFindVisible(true)
        guard let findPanel, !findPanel.findText.isEmpty else {
            findPanel?.focusFind()
            NSSound.beep()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Find in Files"
        alert.informativeText = "Filters (e.g. *.swift;*.rs) and folders to exclude:"
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 56)
        let filtersField = NSTextField(string: AppPrefs.fifFilters)
        filtersField.placeholderString = "Filters"
        let excludesField = NSTextField(string: AppPrefs.fifExcludes)
        excludesField.placeholderString = "Excludes"
        stack.addArrangedSubview(filtersField)
        stack.addArrangedSubview(excludesField)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Choose Folder…")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        AppPrefs.fifFilters = filtersField.stringValue
        AppPrefs.fifExcludes = excludesField.stringValue

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Find"
        if let dir = store.selectedMeta()?.fileURL?.deletingLastPathComponent() {
            panel.directoryURL = dir
        }
        let opts = findPanel.options
        let filters = AppPrefs.fifFilters
        let excludes = AppPrefs.fifExcludes
        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK, let dir = panel.url else { return }
            self.statusLabel.stringValue = "Searching…"
            self.findPanel?.findInFiles(
                directory: dir,
                filters: filters,
                excludes: excludes,
                options: opts
            ) { [weak self] hits in
                self?.presentFindResults(hits)
            }
        }
    }

    @objc func searchGotoLine(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn,
              let n = Int(field.stringValue.trimmingCharacters(in: .whitespaces)), n >= 1
        else { return }
        let lines = textView.string.components(separatedBy: "\n")
        let target = min(n, lines.count) - 1
        let offset = lines[..<target].reduce(0) { $0 + $1.utf16.count + 1 }
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: offset, length: 0))
        textView.scrollRangeToVisible(NSRange(location: offset, length: 0))
    }

    private func performFind(_ req: FindPanel.Request) {
        let text = textView.string
        let opts = req.options
        do {
            if req.countOnly {
                let n = try store.findCount(
                    in: text,
                    pattern: req.find,
                    caseSensitive: opts.caseSensitive,
                    wholeWord: opts.wholeWord,
                    regex: opts.regex
                )
                statusLabel.stringValue = "Count: \(n) matches"
                return
            }
            if req.replaceAll {
                let (out, n) = try store.replaceAll(
                    in: text,
                    pattern: req.find,
                    replacement: req.replace,
                    caseSensitive: opts.caseSensitive,
                    wholeWord: opts.wholeWord,
                    regex: opts.regex
                )
                guard n > 0 else { NSSound.beep(); return }
                applyEditorText(out, caret: textView.selectedRange().location)
                statusLabel.stringValue = "Replaced \(n) occurrence(s)"
                return
            }
            let results = try store.findAll(
                in: text,
                pattern: req.find,
                caseSensitive: opts.caseSensitive,
                wholeWord: opts.wholeWord,
                regex: opts.regex
            ).map(\.range)
            guard let first = results.first else { NSSound.beep(); return }
            if req.replaceOne {
                let at = textView.selectedRange()
                let target = results.first(where: { NSEqualRanges($0, at) })
                    ?? results.first(where: { $0.location >= at.location })
                    ?? first
                textView.setSelectedRange(target)
                replaceEditorText(in: target, with: req.replace)
                // Advance to next after replace.
                let nextRanges = (try? store.findAll(
                    in: textView.string,
                    pattern: req.find,
                    caseSensitive: opts.caseSensitive,
                    wholeWord: opts.wholeWord,
                    regex: opts.regex
                ).map(\.range)) ?? []
                if let next = nextRanges.first(where: { $0.location >= textView.selectedRange().location }) ?? nextRanges.first {
                    textView.setSelectedRange(next)
                    textView.scrollRangeToVisible(next)
                }
                return
            }
            let at = textView.selectedRange().location
            let next = results.first(where: { $0.location >= at + (req.findNext ? 1 : 0) }) ?? first
            textView.setSelectedRange(next)
            textView.scrollRangeToVisible(next)
        } catch {
            NSSound.beep()
            statusLabel.stringValue = error.localizedDescription
        }
    }

    private func stepFind(forward: Bool) {
        guard let findPanel, !findPanel.findText.isEmpty else {
            findPanel?.focusFind()
            NSSound.beep()
            return
        }
        let opts = findPanel.options
        do {
            let ranges = try store.findAll(
                in: textView.string,
                pattern: findPanel.findText,
                caseSensitive: opts.caseSensitive,
                wholeWord: opts.wholeWord,
                regex: opts.regex
            ).map(\.range)
            guard let first = ranges.first, let last = ranges.last else { NSSound.beep(); return }
            let at = textView.selectedRange().location
            let pick = forward
                ? (ranges.first(where: { $0.location > at }) ?? first)
                : (ranges.last(where: { $0.location < at }) ?? last)
            textView.setSelectedRange(pick)
            textView.scrollRangeToVisible(pick)
        } catch {
            NSSound.beep()
            statusLabel.stringValue = error.localizedDescription
        }
    }

    private func presentFindResults(_ hits: [FindPanel.Hit]) {
        syncEditorToStore()
        var text = "Find in Files — \(hits.count) hits\n"
        for h in hits.prefix(500) {
            text += "\(h.file.path)(\(h.line)): \(h.preview)\n"
        }
        if hits.count > 500 {
            text += "… truncated (showing 500 of \(hits.count))\n"
        }
        store.openDocument(title: "Find result", url: nil, text: text, language: "normal")
        refresh()
        statusLabel.stringValue = "Find in Files: \(hits.count) hit(s)"
    }

    // MARK: - View / Encoding / Language / Help

    @objc func viewDocSwitcher(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Documents"
        let names = store.tabs.enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: "\n")
        alert.informativeText = names.isEmpty ? "(none)" : names
        alert.addButton(withTitle: "OK")
        // Quick-select via numbered buttons for small sets.
        let count = min(store.count, 9)
        for i in 0..<count {
            alert.addButton(withTitle: "\(i + 1)")
        }
        let response = alert.runModal()
        if response.rawValue >= NSApplication.ModalResponse.alertSecondButtonReturn.rawValue {
            let idx = response.rawValue - NSApplication.ModalResponse.alertSecondButtonReturn.rawValue
            if idx < store.count {
                syncEditorToStore()
                store.select(at: idx)
                refresh()
            }
        }
    }

    @objc func viewToggleStatusBar(_ sender: Any?) {
        statusLabel.isHidden.toggle()
        statusHeight?.isActive = statusLabel.isHidden
    }

    @objc func viewToggleWrap(_ sender: Any?) {
        wordWrapEnabled.toggle()
        applyWrapMode()
    }

    @objc func viewToggleLineNumbers(_ sender: Any?) {
        lineNumbersVisible.toggle()
        editorScroll?.rulersVisible = lineNumbersVisible
    }

    @objc func viewZoomIn(_ sender: Any?) {
        editorFontSize = min(editorFontSize + 1, 48)
        applyEditorFont()
    }

    @objc func viewZoomOut(_ sender: Any?) {
        editorFontSize = max(editorFontSize - 1, 8)
        applyEditorFont()
    }

    @objc func viewZoomReset(_ sender: Any?) {
        editorFontSize = Self.defaultFontSize
        applyEditorFont()
    }

    @objc func viewToggleFolder(_ sender: Any?) {
        folderVisible.toggle()
        folderPanel?.isHidden = !folderVisible
        folderWidth?.constant = folderVisible ? 220 : 0
    }

    @objc func viewToggleFunctionList(_ sender: Any?) {
        functionListVisible.toggle()
        functionListPanel?.isHidden = !functionListVisible
        functionWidth?.constant = functionListVisible ? 200 : 0
        if functionListVisible {
            refreshFunctionList()
        }
    }

    private func refreshFunctionList() {
        guard functionListVisible else { return }
        let lang = store.selectedMeta()?.language ?? "normal"
        functionListPanel?.reload(text: textView.string, language: lang)
    }

    @objc func toolsMD5(_ sender: Any?) { showHash(of: textView.string, algorithm: .md5) }
    @objc func toolsSHA256(_ sender: Any?) { showHash(of: textView.string, algorithm: .sha256) }
    @objc func toolsMD5Selection(_ sender: Any?) { showHash(of: selectedText(), algorithm: .md5) }
    @objc func toolsSHA256Selection(_ sender: Any?) { showHash(of: selectedText(), algorithm: .sha256) }

    private enum HashKind { case md5, sha256 }

    private func selectedText() -> String {
        let range = textView.selectedRange()
        guard range.length > 0 else { return "" }
        return (textView.string as NSString).substring(with: range)
    }

    private func showHash(of text: String, algorithm: HashKind) {
        guard !text.isEmpty else { NSSound.beep(); return }
        let data = Data(text.utf8)
        let digest: String
        switch algorithm {
        case .md5:
            digest = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .sha256:
            digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        let alert = NSAlert()
        alert.messageText = algorithm == .md5 ? "MD5" : "SHA-256"
        alert.informativeText = digest
        alert.addButton(withTitle: "Copy")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(digest, forType: .string)
        }
    }

    @objc func runCommand(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Run"
        alert.informativeText = "Shell command (path of current file available as $FILE):"
        let field = NSTextField(string: "")
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var cmd = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        if let path = store.selectedMeta()?.fileURL?.path {
            cmd = cmd.replacingOccurrences(of: "$FILE", with: "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'")
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-lc", cmd]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let result = NSAlert()
            result.messageText = task.terminationStatus == 0 ? "Command finished" : "Exit \(task.terminationStatus)"
            result.informativeText = out.isEmpty ? "(no output)" : String(out.prefix(4000))
            result.runModal()
        } catch {
            presentError(error)
        }
    }

    private func maybeBackup(_ url: URL) {
        guard AppPrefs.backupOnSave else { return }
        let bak = url.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: bak)
        try? FileManager.default.copyItem(at: url, to: bak)
    }

    private static func mtime(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func recordKnownMtimes() {
        for tab in store.tabs {
            guard let url = tab.fileURL else { continue }
            knownMtimes[url.path] = Self.mtime(of: url)
        }
    }

    private func startDiskWatchIfNeeded() {
        diskWatchTimer?.invalidate()
        guard AppPrefs.watchDiskChanges else { return }
        diskWatchTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkDiskChanges()
        }
    }

    private func checkDiskChanges() {
        guard AppPrefs.watchDiskChanges else { return }
        for (i, tab) in store.tabs.enumerated() {
            guard let url = tab.fileURL else { continue }
            let path = url.path
            guard let now = Self.mtime(of: url) else { continue }
            if let prev = knownMtimes[path], now > prev.addingTimeInterval(0.5) {
                knownMtimes[path] = now
                if i == store.selectedIndex, !tab.isDirty {
                    // Auto-reload clean tab.
                    store.reloadFromDisk(at: i)
                    if i == store.selectedIndex { refresh() }
                    statusLabel.stringValue = "Reloaded from disk: \(url.lastPathComponent)"
                } else if tab.isDirty {
                    statusLabel.stringValue = "File changed on disk: \(url.lastPathComponent)"
                }
            } else if knownMtimes[path] == nil {
                knownMtimes[path] = now
            }
        }
    }

    @objc private func prefsDidChange(_ note: Notification) {
        applyPrefsFromStore()
    }

    private func applyPrefsFromStore() {
        wordWrapEnabled = AppPrefs.wordWrapDefault
        applyWrapMode()
        lineNumbersVisible = AppPrefs.showLineNumbers
        editorScroll?.rulersVisible = lineNumbersVisible
        applyTabWidth(AppPrefs.tabWidth)
        startDiskWatchIfNeeded()
    }

    private func applyTabWidth(_ n: Int) {
        let font = editorFont
        let space = NSAttributedString(string: String(repeating: " ", count: max(n, 1)), attributes: [.font: font])
        let width = space.size().width
        textView.defaultParagraphStyle = {
            let p = NSMutableParagraphStyle()
            p.defaultTabInterval = width
            p.tabStops = []
            return p
        }()
        textView.typingAttributes[.paragraphStyle] = textView.defaultParagraphStyle
    }

    private func applyWrapMode() {
        guard let container = textView.textContainer else { return }
        if wordWrapEnabled {
            textView.isHorizontallyResizable = false
            container.widthTracksTextView = true
            if let scroll = editorScroll {
                container.containerSize = NSSize(
                    width: max(scroll.contentSize.width, 1),
                    height: CGFloat.greatestFiniteMagnitude
                )
            }
            editorScroll?.hasHorizontalScroller = false
        } else {
            textView.isHorizontallyResizable = true
            container.widthTracksTextView = false
            container.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            editorScroll?.hasHorizontalScroller = true
        }
        textView.needsDisplay = true
        refreshLineNumbers()
    }

    private func applyEditorFont() {
        let font = editorFont
        textView.font = font
        textView.typingAttributes = [.font: font, .foregroundColor: NSColor.textColor]
        scheduleHighlight()
        refreshLineNumbers()
    }

    @objc func editorBoundsDidChange(_ note: Notification) {
        refreshLineNumbers()
    }

    private func refreshLineNumbers() {
        let marks = bookmarksByDoc[store.selectedIndex] ?? []
        lineNumberRuler?.setBookmarks(marks)
        lineNumberRuler?.needsDisplay = true
    }

    private func currentLineIndex() -> Int {
        let ns = textView.string as NSString
        let loc = min(textView.selectedRange().location, ns.length)
        var line = 0
        var i = 0
        while i < loc {
            let range = ns.lineRange(for: NSRange(location: i, length: 0))
            if range.location >= loc { break }
            i = NSMaxRange(range)
            line += 1
            if range.length == 0 { break }
        }
        return line
    }

    @objc func bookmarkToggle(_ sender: Any?) {
        let idx = store.selectedIndex
        var set = bookmarksByDoc[idx] ?? []
        let line = currentLineIndex()
        if set.contains(line) {
            set.remove(line)
        } else {
            set.insert(line)
        }
        bookmarksByDoc[idx] = set
        refreshLineNumbers()
    }

    @objc func bookmarkNext(_ sender: Any?) {
        jumpBookmark(forward: true)
    }

    @objc func bookmarkPrev(_ sender: Any?) {
        jumpBookmark(forward: false)
    }

    @objc func bookmarkClearAll(_ sender: Any?) {
        bookmarksByDoc[store.selectedIndex] = []
        refreshLineNumbers()
    }

    private func jumpBookmark(forward: Bool) {
        let marks = (bookmarksByDoc[store.selectedIndex] ?? []).sorted()
        guard !marks.isEmpty else { return }
        let cur = currentLineIndex()
        let target: Int
        if forward {
            target = marks.first(where: { $0 > cur }) ?? marks[0]
        } else {
            target = marks.last(where: { $0 < cur }) ?? marks[marks.count - 1]
        }
        goToLineNumber(target + 1)
    }

    private func goToLineNumber(_ oneBased: Int) {
        let ns = textView.string as NSString
        var line = 1
        var i = 0
        while i < ns.length {
            if line == oneBased {
                textView.setSelectedRange(NSRange(location: i, length: 0))
                textView.scrollRangeToVisible(NSRange(location: i, length: 0))
                return
            }
            let range = ns.lineRange(for: NSRange(location: i, length: 0))
            i = NSMaxRange(range)
            line += 1
            if range.length == 0 { break }
        }
    }

    @objc func encUtf8(_ sender: Any?) { setEncoding(.utf8) }
    @objc func encUtf8Bom(_ sender: Any?) { setEncoding(.utf8Bom) }
    @objc func encUtf16Le(_ sender: Any?) { setEncoding(.utf16Le) }
    @objc func encUtf16Be(_ sender: Any?) { setEncoding(.utf16Be) }
    @objc func encAnsi(_ sender: Any?) { setEncoding(.ansi) }

    private func setEncoding(_ enc: DocEncoding) {
        syncEditorToStore()
        store.setEncoding(enc)
        refresh()
    }

    @objc func eolCrlf(_ sender: Any?) { setEol(.crlf) }
    @objc func eolLf(_ sender: Any?) { setEol(.lf) }
    @objc func eolCr(_ sender: Any?) { setEol(.cr) }

    private func setEol(_ eol: DocEol) {
        syncEditorToStore()
        store.setEol(eol)
        refresh()
    }

    @objc func langSelect(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let key = item.representedObject as? String
        else { return }
        syncEditorToStore()
        store.setLanguage(key)
        refresh()
    }

    @objc func langAuto(_ sender: Any?) {
        syncEditorToStore()
        guard let doc = store.selected else { return }
        let lang: String
        if let url = doc.fileURL {
            lang = store.language(forPath: url.path)
        } else if let name = doc.title.split(separator: "/").last {
            lang = store.language(forPath: String(name))
        } else {
            lang = "normal"
        }
        store.setLanguage(lang)
        refresh()
    }

    @objc func langLoadUDL(_ sender: Any?) {
        guard let window, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.xml]
        panel.message = "Choose Notepad++ User Defined Language (.udl.xml) files"
        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK else { return }
            var loaded = 0
            var lastKey: String?
            for url in panel.urls {
                do {
                    let n = try self.store.loadUDL(path: url.path)
                    loaded += n
                    if let key = self.store.languages().last(where: { $0.key.hasPrefix("udl_") })?.key {
                        lastKey = key
                    }
                } catch {
                    self.presentError(error)
                }
            }
            if let lastKey {
                self.syncEditorToStore()
                self.store.setLanguage(lastKey)
            }
            self.refresh()
            self.statusLabel.stringValue = "Loaded \(loaded) UDL language(s)"
        }
    }

    @objc func helpAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "NppMac 0.1.0"
        alert.informativeText = "Notepad++ macOS port — Rust core + native Swift GUI."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func openPreferences(_ sender: Any?) {
        PreferencesWindow.show()
    }

    // MARK: - Macro (shell)

    @objc func macroStartRecording(_ sender: Any?) {
        macroRecording = true
        macroSteps = []
        statusLabel.stringValue = "Macro recording…"
    }

    @objc func macroStopRecording(_ sender: Any?) {
        guard macroRecording else { NSSound.beep(); return }
        macroRecording = false
        statusLabel.stringValue = "Macro stopped (\(macroSteps.count) steps)"
    }

    @objc func macroPlayback(_ sender: Any?) {
        guard !macroSteps.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No macro recorded"
            alert.informativeText = "Use Macro → Start Recording, perform edits, then Stop Recording."
            alert.runModal()
            return
        }
        // Playback is limited to recorded text-insert steps for now.
        for step in macroSteps {
            if step.hasPrefix("insert:") {
                let text = String(step.dropFirst("insert:".count))
                let range = textView.selectedRange()
                replaceEditorText(in: range, with: text)
            }
        }
        statusLabel.stringValue = "Macro playback finished"
    }

    @objc func macroSave(_ sender: Any?) {
        guard !macroSteps.isEmpty else { NSSound.beep(); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "macro.txt"
        panel.begin { [weak self] result in
            guard let self, result == .OK, let url = panel.url else { return }
            let body = self.macroSteps.joined(separator: "\n") + "\n"
            try? body.write(to: url, atomically: true, encoding: .utf8)
            self.statusLabel.stringValue = "Macro saved"
        }
    }

    /// Record a typing step while macro recording is active.
    func recordMacroInsert(_ text: String) {
        guard macroRecording, !text.isEmpty else { return }
        macroSteps.append("insert:\(text)")
    }

    // MARK: - Plugins (shell)

    @objc func pluginsOpenFolder(_ sender: Any?) {
        NSWorkspace.shared.open(PluginHost.pluginsDirectory)
    }

    @objc func pluginsRefresh(_ sender: Any?) {
        MenuBuilder.reloadPlugins(target: self)
        statusLabel.stringValue = "Plugins: \(PluginHost.discover().count) found"
    }

    @objc func pluginsInvoke(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let url = item.representedObject as? URL else { return }
        let alert = NSAlert()
        alert.messageText = "Plugin host (stub)"
        alert.informativeText = "Discovered \(url.lastPathComponent).\nFull Notepad++ plugin ABI loading is not yet implemented on macOS."
        alert.runModal()
    }
}

extension MainWindowController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard !syncingText else { return }
        editorNeedsSync = true
        if macroRecording {
            // Best-effort: record the last typed character(s) via change count is hard;
            // capture short inserts when selection was empty before sync.
            // Full keystroke capture lands with a dedicated textStorage observer later.
        }
        scheduleSync()
        scheduleHighlight()
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        if macroRecording, let replacementString, !replacementString.isEmpty {
            recordMacroInsert(replacementString)
        }
        return true
    }

    /// Each tab keeps its own undo history (the editor view is shared).
    func undoManager(for view: NSTextView) -> UndoManager? {
        store.undoManager(at: store.selectedIndex)
    }
}

extension MainWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(langSelect(_:)),
           let key = menuItem.representedObject as? String
        {
            menuItem.state = (store.selectedMeta()?.language == key) ? .on : .off
            return true
        }
        if menuItem.action == #selector(langAuto(_:)) {
            menuItem.state = .off
            return store.selected != nil
        }
        if menuItem.action == #selector(viewToggleWrap(_:)) {
            menuItem.state = wordWrapEnabled ? .on : .off
        } else if menuItem.action == #selector(viewToggleLineNumbers(_:)) {
            menuItem.state = lineNumbersVisible ? .on : .off
        } else if menuItem.action == #selector(viewToggleFolder(_:)) {
            menuItem.state = folderVisible ? .on : .off
        } else if menuItem.action == #selector(viewToggleFunctionList(_:)) {
            menuItem.state = functionListVisible ? .on : .off
        } else if menuItem.action == #selector(macroStartRecording(_:)) {
            return !macroRecording
        } else if menuItem.action == #selector(macroStopRecording(_:)) {
            return macroRecording
        } else if menuItem.action == #selector(macroPlayback(_:)) || menuItem.action == #selector(macroSave(_:)) {
            return !macroSteps.isEmpty && !macroRecording
        }
        let enc = store.selectedIndex >= 0 ? store.encoding(at: store.selectedIndex) : nil
        if menuItem.action == #selector(encUtf8(_:)) {
            menuItem.state = enc == .utf8 ? .on : .off
        } else if menuItem.action == #selector(encUtf8Bom(_:)) {
            menuItem.state = enc == .utf8Bom ? .on : .off
        } else if menuItem.action == #selector(encUtf16Le(_:)) {
            menuItem.state = enc == .utf16Le ? .on : .off
        } else if menuItem.action == #selector(encUtf16Be(_:)) {
            menuItem.state = enc == .utf16Be ? .on : .off
        } else if menuItem.action == #selector(encAnsi(_:)) {
            menuItem.state = enc == .ansi ? .on : .off
        }
        let eol = store.selectedIndex >= 0 ? store.eol(at: store.selectedIndex) : nil
        if menuItem.action == #selector(eolCrlf(_:)) {
            menuItem.state = eol == .crlf ? .on : .off
        } else if menuItem.action == #selector(eolLf(_:)) {
            menuItem.state = eol == .lf ? .on : .off
        } else if menuItem.action == #selector(eolCr(_:)) {
            menuItem.state = eol == .cr ? .on : .off
        }
        return true
    }
}

extension MainWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard hasUnsavedDocuments else { return true }
        confirmCloseAll { proceed in
            if proceed { sender.close() }
        }
        return false
    }
}
