import AppKit
import Darwin
import Foundation

/// Discovers and probes Notepad++-style macOS plugins under Application Support.
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
        /// `dlopen` succeeded.
        var loadable: Bool
        /// Optional `getName` / folder display name.
        var displayName: String
    }

    /// Flat `*.dylib` plus nested `<Name>/<Name>.dylib` (Win32 plugin layout).
    static func discover() -> [Entry] {
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
        return urls.map { url in
            let probed = probe(url)
            return Entry(
                name: url.deletingPathExtension().lastPathComponent,
                url: url,
                loadable: probed.ok,
                displayName: probed.name ?? url.deletingPathExtension().lastPathComponent
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private static func probe(_ url: URL) -> (ok: Bool, name: String?) {
        let path = url.path
        guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else {
            return (false, nil)
        }
        defer { dlclose(handle) }
        // Prefer UTF-8 helper if a plugin exports it; else try getName as C string.
        typealias GetNameUTF8 = @convention(c) () -> UnsafePointer<CChar>?
        typealias GetNameW = @convention(c) () -> UnsafePointer<UInt16>?
        if let sym = dlsym(handle, "getNameUTF8") {
            let fn = unsafeBitCast(sym, to: GetNameUTF8.self)
            if let c = fn() {
                return (true, String(cString: c))
            }
        }
        if let sym = dlsym(handle, "getName") {
            // Many stubs export a C string; wchar_t* would need conversion.
            let fn = unsafeBitCast(sym, to: GetNameUTF8.self)
            if let c = fn() {
                // Heuristic: if it looks like ASCII C string, use it.
                let s = String(cString: c)
                if !s.isEmpty, s.utf8.count < 200, s.allSatisfy({ $0.isASCII }) {
                    return (true, s)
                }
            }
            return (true, nil)
        }
        // Library opens but no Notepad++ exports — still "loadable" as a dylib.
        return (true, nil)
    }
}
