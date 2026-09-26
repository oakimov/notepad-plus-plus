import AppKit
import Foundation

/// Lightweight plugin shell: discovers `.dylib` / `.bundle` under Application Support.
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
    }

    static func discover() -> [Entry] {
        let dir = pluginsDirectory
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "dylib" || $0.pathExtension == "bundle" || $0.pathExtension == "plugin" }
            .map { Entry(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
