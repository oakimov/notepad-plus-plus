import AppKit
import Cnpp_plugin
import Darwin
import Foundation

/// Retains a plugin command so the menu can invoke `PFUNCPLUGINCMD`.
final class PluginCommandTarget: NSObject {
    let title: String
    let pluginName: String
    private let invokeFn: () -> Void

    init(title: String, pluginName: String, invoke: @escaping () -> Void) {
        self.title = title
        self.pluginName = pluginName
        self.invokeFn = invoke
    }

    @objc func run(_ sender: Any?) {
        invokeFn()
    }
}

/// C trampoline target for `nppSendMessage` (defined in Cnpp_plugin).
private func nppSendMessageImpl(
    _ hwnd: UInt64,
    _ msg: UInt32,
    _ wParam: UInt,
    _ lParam: Int
) -> Int {
    PluginRuntime.shared.sendMessage(hwnd: hwnd, msg: msg, wParam: wParam, lParam: lParam)
}

/// Loads and retains Notepad++-compatible `.dylib` plugins; builds Plugins menu entries;
/// broadcasts `beNotified` and dispatches `NPPM_*` via `nppSendMessage`.
final class PluginRuntime: NSObject {
    static let shared: PluginRuntime = {
        let r = PluginRuntime()
        nppRegisterSendMessage(nppSendMessageImpl)
        return r
    }()

    typealias BeNotifiedFn = @convention(c) (UnsafeRawPointer) -> Void
    typealias MessageProcFn = @convention(c) (UInt32, UInt, Int) -> Int

    struct Loaded {
        var path: URL
        var handle: UnsafeMutableRawPointer
        var displayName: String
        var commands: [PluginCommandTarget]
        var beNotified: BeNotifiedFn?
        var messageProc: MessageProcFn?
    }

    private(set) var loaded: [Loaded] = []

    /// Opaque `NppData` tokens (never dereference).
    private let nppHandle: UInt64 = 1
    private let editorMain: UInt64 = 2
    private let editorSecond: UInt64 = 3

    /// Active buffer / editor state for `NPPM_*` replies.
    private(set) var currentBufferId: UInt64 = 0
    private(set) var currentEditor: UInt64 = 2
    private(set) var currentDocIndex: Int = 0
    private var lastActivatedBuffer: UInt64 = .max
    private var readySent = false

    /// Window controller that runs `IDM_*` menu actions for `NPPM_MENUCOMMAND`.
    weak var menuTarget: MainWindowController?

    var pluginsDirectory: URL { PluginHost.pluginsDirectory }

    func reload() {
        unloadAll()
        readySent = false
        for url in PluginHost.dylibURLs() {
            if let plugin = load(url: url) {
                loaded.append(plugin)
            }
        }
    }

    func unloadAll() {
        if !loaded.isEmpty {
            broadcastNppn(code: NppNotifyCode.shutdown, bufferId: currentBufferId)
        }
        for p in loaded {
            dlclose(p.handle)
        }
        loaded.removeAll()
    }

    // MARK: - State

    func setCurrent(bufferId: UInt64, editor: UInt64? = nil, docIndex: Int) {
        currentBufferId = bufferId
        currentDocIndex = docIndex
        if let editor {
            currentEditor = editor
        } else {
            currentEditor = editorMain
        }
    }

    /// Sync host state from the document store selection.
    func syncFromStore(selectedIndex: Int) {
        guard selectedIndex >= 0 else { return }
        setCurrent(bufferId: UInt64(selectedIndex), docIndex: selectedIndex)
    }

    // MARK: - NPPM_* dispatch (nppSendMessage)

    func sendMessage(hwnd: UInt64, msg: UInt32, wParam: UInt, lParam: Int) -> Int {
        _ = hwnd
        _ = wParam
        switch msg {
        case NppMsg.getCurrentBufferId:
            return Int(bitPattern: UInt(currentBufferId))
        case NppMsg.getCurrentScintilla:
            // Win32 writes view index (0/1) to *lParam; NppMac also returns editor token.
            if lParam != 0 {
                let view: Int32 = (currentEditor == editorSecond) ? 1 : 0
                UnsafeMutableRawPointer(bitPattern: lParam)?
                    .assumingMemoryBound(to: Int32.self)
                    .pointee = view
            }
            return Int(bitPattern: UInt(currentEditor))
        case NppMsg.getCurrentDocIndex:
            return currentDocIndex
        case NppMsg.menuCommand:
            return executeMenuCommand(idm: Int(lParam)) ? 1 : 0
        default:
            return 0
        }
    }

    private func executeMenuCommand(idm: Int) -> Bool {
        guard let t = menuTarget else { return false }
        switch idm {
        case NppIdm.fileNew: t.fileNew(nil)
        case NppIdm.fileOpen: t.fileOpen(nil)
        case NppIdm.fileClose: t.fileClose(nil)
        case NppIdm.fileSave: t.fileSave(nil)
        case NppIdm.fileSaveAs: t.fileSaveAs(nil)
        case NppIdm.fileSaveAll: t.fileSaveAll(nil)
        case NppIdm.fileReload: t.fileReload(nil)
        case NppIdm.editUndo: t.editUndo(nil)
        case NppIdm.editRedo: t.editRedo(nil)
        case NppIdm.editSelectAll:
            t.editorTextViewForPlugins.selectAll(nil)
        case NppIdm.editDupLine: t.editDuplicateLine(nil)
        case NppIdm.editJoinLines: t.editJoinLines(nil)
        case NppIdm.editUppercase: t.editUpperCase(nil)
        case NppIdm.editLowercase: t.editLowerCase(nil)
        case NppIdm.editTrimTrailing: t.editTrimTrailing(nil)
        default:
            return false
        }
        return true
    }

    // MARK: - beNotified broadcast

    func notifyReady() {
        guard !readySent, !loaded.isEmpty else { return }
        readySent = true
        broadcastNppn(code: NppNotifyCode.ready, bufferId: currentBufferId)
    }

    func notifyFileOpened(bufferId: UInt64) {
        broadcastNppn(code: NppNotifyCode.fileOpened, bufferId: bufferId)
        notifyBufferActivated(bufferId: bufferId)
    }

    func notifyFileBeforeSave(bufferId: UInt64) {
        broadcastNppn(code: NppNotifyCode.fileBeforeSave, bufferId: bufferId)
    }

    func notifyFileSaved(bufferId: UInt64) {
        broadcastNppn(code: NppNotifyCode.fileSaved, bufferId: bufferId)
    }

    func notifyFileBeforeClose(bufferId: UInt64) {
        broadcastNppn(code: NppNotifyCode.fileBeforeClose, bufferId: bufferId)
    }

    func notifyFileClosed(bufferId: UInt64) {
        broadcastNppn(code: NppNotifyCode.fileClosed, bufferId: bufferId)
    }

    func notifyBufferActivated(bufferId: UInt64) {
        syncFromStore(selectedIndex: Int(bufferId))
        guard bufferId != lastActivatedBuffer else { return }
        lastActivatedBuffer = bufferId
        broadcastNppn(code: NppNotifyCode.bufferActivated, bufferId: bufferId)
    }

    /// SCN_MODIFIED from NSTextView edits (UTF-8 byte offsets).
    func notifyModified(
        bufferId: UInt64,
        position: Int,
        length: Int,
        linesAdded: Int,
        modificationType: Int32
    ) {
        var note = SCNotificationC()
        note.nmhdr.hwndFrom = UnsafeMutableRawPointer(bitPattern: UInt(editorMain))
        note.nmhdr.idFrom = UInt(bufferId)
        note.nmhdr.code = NppNotifyCode.scnModified
        note.position = position
        note.modificationType = modificationType
        note.length = length
        note.linesAdded = linesAdded
        broadcast(&note)
    }

    private func broadcastNppn(code: UInt32, bufferId: UInt64) {
        var note = SCNotificationC()
        note.nmhdr.hwndFrom = UnsafeMutableRawPointer(bitPattern: UInt(nppHandle))
        note.nmhdr.idFrom = UInt(bufferId)
        note.nmhdr.code = code
        broadcast(&note)
    }

    private func broadcast(_ note: inout SCNotificationC) {
        for p in loaded {
            guard let fn = p.beNotified else { continue }
            withUnsafePointer(to: &note) { fn(UnsafeRawPointer($0)) }
        }
    }

    /// Forward a host→plugin message via each plugin's `messageProc` (rarely used).
    @discardableResult
    func callMessageProcs(message: UInt32, wParam: UInt, lParam: Int) -> Int {
        var last = 0
        for p in loaded {
            if let fn = p.messageProc {
                last = fn(message, wParam, lParam)
            }
        }
        return last
    }

    // MARK: - Load

    private func load(url: URL) -> Loaded? {
        guard let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else {
            return nil
        }

        // Layout must match C `FuncItemUTF8` (verified: sizeof=88, pFunc@64).
        assert(MemoryLayout<FuncItemUTF8Layout>.stride == 88)
        assert(MemoryLayout<SCNotificationC>.stride == 160)

        // ARM64 AAPCS: aggregates >16 bytes are passed by hidden pointer (x0 = &NppData),
        // not as three register args. Passing (1,2,3) made setInfo dereference 0x1 (crash).
        if let sym = dlsym(handle, "setInfo") {
            typealias SetInfoFn = @convention(c) (UnsafeRawPointer) -> Void
            let fn = unsafeBitCast(sym, to: SetInfoFn.self)
            var data = NppDataC(npp: nppHandle, main: editorMain, second: editorSecond)
            withUnsafeBytes(of: &data) { raw in
                fn(raw.baseAddress!)
            }
        }

        var beNotified: BeNotifiedFn?
        if let sym = dlsym(handle, "beNotified") {
            beNotified = unsafeBitCast(sym, to: BeNotifiedFn.self)
        }
        var messageProc: MessageProcFn?
        if let sym = dlsym(handle, "messageProc") {
            messageProc = unsafeBitCast(sym, to: MessageProcFn.self)
        }

        let display = readName(handle: handle) ?? url.deletingPathExtension().lastPathComponent
        var commands: [PluginCommandTarget] = []

        typealias GetFuncsUTF8 = @convention(c) (UnsafeMutablePointer<Int32>) -> UnsafeMutableRawPointer?
        if let sym = dlsym(handle, "getFuncsArrayUTF8") {
            let fn = unsafeBitCast(sym, to: GetFuncsUTF8.self)
            var count: Int32 = 0
            if let arr = fn(&count), count > 0 {
                let stride = MemoryLayout<FuncItemUTF8Layout>.stride
                for i in 0..<Int(count) {
                    let base = arr.advanced(by: i * stride)
                    let layout = base.assumingMemoryBound(to: FuncItemUTF8Layout.self).pointee
                    let title = withUnsafePointer(to: layout.itemName) {
                        $0.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) }
                    }
                    guard !title.isEmpty, let raw = layout.pFunc else { continue }
                    let callback = unsafeBitCast(raw, to: (@convention(c) () -> Void).self)
                    commands.append(PluginCommandTarget(
                        title: title,
                        pluginName: display,
                        invoke: { callback() }
                    ))
                }
            }
        }

        return Loaded(
            path: url,
            handle: handle,
            displayName: display,
            commands: commands,
            beNotified: beNotified,
            messageProc: messageProc
        )
    }

    private func readName(handle: UnsafeMutableRawPointer) -> String? {
        typealias GetNameUTF8 = @convention(c) () -> UnsafePointer<CChar>?
        if let sym = dlsym(handle, "getNameUTF8") {
            let fn = unsafeBitCast(sym, to: GetNameUTF8.self)
            if let c = fn() { return String(cString: c) }
        }
        if let sym = dlsym(handle, "getName") {
            let fn = unsafeBitCast(sym, to: GetNameUTF8.self)
            if let c = fn() {
                let s = String(cString: c)
                if !s.isEmpty, s.utf8.count < 200, s.allSatisfy(\.isASCII) { return s }
            }
        }
        return nil
    }
}

// MARK: - Message / notification constants (NppPluginInterface.h)

enum NppMsg {
    static let getCurrentScintilla: UInt32 = 2028
    static let getCurrentDocIndex: UInt32 = 2047
    static let menuCommand: UInt32 = 2072
    static let getCurrentBufferId: UInt32 = 2084
}

enum NppNotifyCode {
    static let ready: UInt32 = 1001
    static let fileBeforeClose: UInt32 = 1003
    static let fileOpened: UInt32 = 1004
    static let fileClosed: UInt32 = 1005
    static let fileBeforeSave: UInt32 = 1007
    static let fileSaved: UInt32 = 1008
    static let shutdown: UInt32 = 1009
    static let bufferActivated: UInt32 = 1010
    static let scnModified: UInt32 = 2008
}

enum NppIdm {
    static let fileNew = 41001
    static let fileOpen = 41002
    static let fileClose = 41003
    static let fileSave = 41006
    static let fileSaveAll = 41007
    static let fileSaveAs = 41008
    static let fileReload = 41014
    static let editUndo = 42003
    static let editRedo = 42004
    static let editSelectAll = 42007
    static let editDupLine = 42010
    static let editJoinLines = 42013
    static let editUppercase = 42016
    static let editLowercase = 42017
    static let editTrimTrailing = 42024
}

enum NppMod {
    static let insertText: Int32 = 0x1
    static let deleteText: Int32 = 0x2
}

/// Binary layout matching C `NppData` (3× `uint64_t`, 24 bytes — passed by pointer on ARM64).
struct NppDataC {
    var npp: UInt64
    var main: UInt64
    var second: UInt64
}

/// Binary layout matching `Sci_NotifyHeader` + `SCNotification` (160 bytes on LP64).
struct SciNotifyHeaderC {
    var hwndFrom: UnsafeMutableRawPointer?
    var idFrom: UInt
    var code: UInt32
    var _pad: UInt32 = 0
}

struct SCNotificationC {
    var nmhdr: SciNotifyHeaderC = SciNotifyHeaderC(hwndFrom: nil, idFrom: 0, code: 0)
    var position: Int = 0
    var ch: Int32 = 0
    var modifiers: Int32 = 0
    var modificationType: Int32 = 0
    var _padText: UInt32 = 0
    var text: UnsafePointer<CChar>? = nil
    var length: Int = 0
    var linesAdded: Int = 0
    var message: Int32 = 0
    var _padW: UInt32 = 0
    var wParam: UInt = 0
    var lParam: Int = 0
    var line: Int = 0
    var foldLevelNow: Int32 = 0
    var foldLevelPrev: Int32 = 0
    var margin: Int32 = 0
    var listType: Int32 = 0
    var x: Int32 = 0
    var y: Int32 = 0
    var token: Int32 = 0
    var _padAnn: UInt32 = 0
    var annotationLinesAdded: Int = 0
    var updated: Int32 = 0
    var listCompletionMethod: Int32 = 0
    var characterSource: Int32 = 0
    var _padEnd: UInt32 = 0
}

/// Binary layout matching `FuncItemUTF8` on arm64 macOS (88 bytes).
struct FuncItemUTF8Layout {
    var itemName: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )
    var pFunc: UnsafeMutableRawPointer?
    var cmdID: Int32
    var init2Check: UInt8
    var pad0: UInt8
    var pad1: UInt8
    var pad2: UInt8
    var pShKey: UnsafeMutableRawPointer?
}

/// Discovery helpers shared with the menu.
enum PluginHost {
    static var pluginsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("NppMac/plugins", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    struct Entry: Equatable {
        var name: String
        var url: URL
        var loadable: Bool
        var displayName: String
    }

    static func dylibURLs() -> [URL] {
        let dir = pluginsDirectory
        var urls: [URL] = []
        let kids = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for u in kids {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
            if isDir.boolValue {
                let nested = u.appendingPathComponent(u.lastPathComponent).appendingPathExtension("dylib")
                if FileManager.default.fileExists(atPath: nested.path) {
                    urls.append(nested)
                }
            } else if ["dylib", "bundle", "plugin"].contains(u.pathExtension) {
                urls.append(u)
            }
        }
        return urls.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    static func discover() -> [Entry] {
        let runtime = PluginRuntime.shared
        if !runtime.loaded.isEmpty {
            return runtime.loaded.map {
                Entry(
                    name: $0.path.deletingPathExtension().lastPathComponent,
                    url: $0.path,
                    loadable: true,
                    displayName: $0.displayName
                )
            }
        }
        return dylibURLs().map { url in
            var ok = false
            if let h = dlopen(url.path, RTLD_LAZY | RTLD_LOCAL) {
                ok = true
                dlclose(h)
            }
            return Entry(
                name: url.deletingPathExtension().lastPathComponent,
                url: url,
                loadable: ok,
                displayName: url.deletingPathExtension().lastPathComponent
            )
        }
    }
}
