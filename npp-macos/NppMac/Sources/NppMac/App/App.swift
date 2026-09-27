import AppKit

/// Application entry point. Menubar + window shell; editor core in Rust via FFI.
@main
struct NppMacApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        // NSApplication.delegate is weak; keep ours alive for the whole run loop.
        withExtendedLifetime(delegate) {
            app.delegate = delegate
            app.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: MainWindowController?
    /// Files that arrived via Apple Event before the window existed.
    private var pendingFiles: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        SessionStore.loadConfig()
        AppPrefs.applyAppearance()
        NativeLang.loadCurrent()
        applyAppIcon()
        MenuBuilder.build()
        ShortcutMapper.captureDefaultsFromMenus()
        ShortcutMapper.applyOverrides()
        MenuBuilder.applyNativeLangTitles()
        let controller = MainWindowController(documents: DocumentStore(engine: NppEngine(langsModel: Self.langsModelPath())))
        windowController = controller
        MenuBuilder.retarget(to: controller)
        PluginRuntime.shared.menuTarget = controller
        PluginRuntime.shared.syncFromStore(selectedIndex: 0)
        // NPPN_READY already sent from MainWindowController.init (after plugin load).
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        var paths = pendingFiles
        pendingFiles.removeAll()
        paths.append(contentsOf: CommandLine.arguments.dropFirst())
        if let env = ProcessInfo.processInfo.environment["NPP_OPEN"], !env.isEmpty {
            paths.append(contentsOf: env.split(separator: ":").map(String.init))
        }
        paths = paths.filter { !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0) }
        // De-dupe while preserving order.
        var seen = Set<String>()
        paths = paths.filter { seen.insert($0).inserted }
        if !paths.isEmpty {
            // Defer one turn so the window finishes ordering front before buffer load.
            DispatchQueue.main.async {
                controller.openPaths(paths)
            }
        } else {
            DispatchQueue.main.async {
                controller.restoreSessionIfNeeded()
            }
        }
    }

    /// Stock `langs.model.xml` copied into the bundle by `package-app.sh` (nil under `swift run`).
    private static func langsModelPath() -> String? {
        Bundle.main.url(forResource: "langs.model", withExtension: "xml")?.path
    }

    private func applyAppIcon() {
        let name = "AppIcon"
        var urls: [URL] = []
        if let u = Bundle.main.url(forResource: name, withExtension: "icns") { urls.append(u) }
        if let u = Bundle.main.url(forResource: name, withExtension: "png") { urls.append(u) }
        let exeDir = Bundle.main.bundleURL.deletingLastPathComponent()
        urls.append(exeDir.appendingPathComponent("NppMac_NppMac.bundle").appendingPathComponent("\(name).png"))
        urls.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name).icns"))
        urls.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name).png"))
        for url in urls {
            if let image = NSImage(contentsOf: url) {
                NSApp.applicationIconImage = image
                return
            }
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        enqueueOrOpen([filename])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        enqueueOrOpen(filenames)
        sender.reply(toOpenOrPrint: .success)
    }

    private func enqueueOrOpen(_ files: [String]) {
        if let wc = windowController {
            DispatchQueue.main.async { wc.openPaths(files) }
        } else {
            pendingFiles.append(contentsOf: files)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowController?.showWindow(nil)
        }
        return true
    }

    /// Prompt for every unsaved document before quitting (Cmd-Q / Dock Quit).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        windowController?.persistSession()
        SessionStore.saveConfig()
        guard let wc = windowController, wc.hasUnsavedDocuments else { return .terminateNow }
        wc.confirmCloseAll { proceed in
            if proceed { wc.persistSession() }
            sender.reply(toApplicationShouldTerminate: proceed)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
