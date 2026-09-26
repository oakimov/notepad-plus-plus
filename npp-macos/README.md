# NppMac — Notepad++ macOS port (Rust core + native Swift GUI)

In-repo sibling of the Win32 Notepad++ codebase. Faithful behavior port:
internal tab bar, native menubar, multi-encoding I/O, tree-sitter highlighting.

## Status: viable editor (FFI-linked)

Swift AppKit shell talks to Rust through `crates/npp-ffi` (C ABI):

- Native menubar (App/File/Edit/Search/View/Encoding/Language/Help) with Quit
- Internal tab bar (select, drag-reorder, × close with dirty prompt)
- `NSTextView` editor with debounced syntax highlighting
- Find/Replace, Find-in-Files, Go-to-Line, Preferences stub, status bar
- Open/save via `npp-fs` (UTF-8 / UTF-8-BOM / UTF-16 / ANSI)

## Layout

- `crates/npp-core` — buffer, undo, document manager, search, line ops
- `crates/npp-fs` — encoding detect/decode + atomic save
- `crates/npp-config` — langs/stylers/session XML
- `crates/npp-highlight` — tree-sitter + keyword fallback
- `crates/npp-ffi` — C ABI + `include/npp_ffi.h` for Swift
- `crates/npp-plugin` — plugin host skeleton
- `NppMac/` — Swift AppKit app (`Package.swift`)
- `scripts/package-app.sh` / `scripts/notarize.sh` — `.app` + notarization
- `docs/plugin-porting.md` — Win32 DLL → `.dylib` guide

## Build & test

```sh
# From npp-macos/
CARGO_TARGET_DIR=./target cargo test --offline
CARGO_TARGET_DIR=./target cargo build -p npp-ffi --release --offline

cd NppMac
NPP_FFI_LIB_DIR=../target/release swift build
NPP_FFI_LIB_DIR=../target/release swift test
```

`cargo` needs `--offline` unless crates.io is reachable; dependencies live in
the local cargo cache. Build `npp-ffi` before `swift build` (static `libnpp_ffi.a`).

Minimum macOS is 15.0: the installed Rust std is built for 15.0, so
`.cargo/config.toml`, `Package.swift` and `Info.plist` all target 15.0 (a
lower target only produces linker version-mismatch warnings).

## App bundle

```sh
./scripts/package-app.sh          # → dist/NppMac.app
open dist/NppMac.app
```

The Dock/Finder icon is the stock Notepad++ `npp.ico` converted to
`packaging/AppIcon.icns`. Regenerate with `./scripts/make-app-icon.sh`
(requires Pillow + `iconutil`).

### Notarization (optional)

Requires a Developer ID Application certificate and a notarytool profile:

```sh
export NPP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NPP_NOTARY_PROFILE="your-notary-profile"
./scripts/notarize.sh
```

## Plugin note

Win32 `.dll` plugins cannot load on macOS ARM64. Recompile against
`crates/npp-plugin/include/NppPluginInterface.h` as `.dylib`. See
`docs/plugin-porting.md`.

## Out of scope (later milestones)

Dockable panels, macros, full `NPPM_*` / `IDM_*` coverage, style configurator
UI, localization beyond string-table plumbing, App Sandbox, notarized DMG.
