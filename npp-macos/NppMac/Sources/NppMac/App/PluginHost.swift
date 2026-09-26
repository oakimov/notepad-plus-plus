import AppKit
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

/// Loads and retains Notepad++-compatible `.dylib` plugins; builds Plugins menu entries.
final class PluginRuntime: NSObject {
    static let shared = PluginRuntime()

    struct Loaded {
        var path: URL
        var handle: UnsafeMutableRawPointer
        var displayName: String
        var commands: [PluginCommandTarget]
    }

    private(set) var loaded: [Loaded] = []

    /// Opaque `NppData` tokens (never dereference).
    private let nppHandle: UInt64 = 1
    private let editorMain: UInt64 = 2
    private let editorSecond: UInt64 = 3

    var pluginsDirectory: URL { PluginHost.pluginsDirectory }

    func reload() {
        unloadAll()
        for url in PluginHost.dylibURLs() {
            if let plugin = load(url: url) {
                loaded.append(plugin)
            }
        }
    }

    func unloadAll() {
        for p in loaded {
            dlclose(p.handle)
        }
        loaded.removeAll()
    }

    private func load(url: URL) -> Loaded? {
        guard let handle = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else {
            return nil
        }

        // Layout must match C `FuncItemUTF8` (verified: sizeof=88, pFunc@64).
        assert(MemoryLayout<FuncItemUTF8Layout>.stride == 88)

        // ARM64: NppData (3× uint64) is passed in x0–x2 — same as three UInt64 args.
        if let sym = dlsym(handle, "setInfo") {
            typealias SetInfoFn = @convention(c) (UInt64, UInt64, UInt64) -> Void
            let fn = unsafeBitCast(sym, to: SetInfoFn.self)
            fn(nppHandle, editorMain, editorSecond)
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

        return Loaded(path: url, handle: handle, displayName: display, commands: commands)
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
