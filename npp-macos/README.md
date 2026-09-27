# NppMac — Notepad++ macOS port (Rust core + native Swift GUI)

In-repo sibling of the Win32 Notepad++ codebase. Faithful behavior port:
internal tab bar, native menubar, multi-encoding I/O, tree-sitter + keyword highlighting.

## Status: full-port shell (NSTextView + Rust FFI)

Swift AppKit shell talks to Rust through `crates/npp-ffi` (C ABI). Phases 1–7 from
`docs/port-roadmap.md` are largely in place; remaining polish is tracked there.

- Native menubar (App/File/Edit/Search/View/Encoding/Language/Settings/Tools/Macro/Run/Plugins/Window/Help)
- **Language menu**: compact A–Z for all stock langs from `langs.model.xml`,
  set-language, auto-detect, checkmarks, status-bar display names
- Syntax highlighting: tree-sitter (13) + keyword fallback (case-insensitive,
  hyphenated words, diff/LaTeX scanners, XML CDATA→HTML); colors from `stylers.model.xml`
- Tabs, Find/Replace/FiF, session/recent/`config.xml`, Preferences, Style Configurator
- Panels: Folder workspace, Function List, Document Map, Clipboard History, Character Panel
- Plugins: `dlopen` host for nested `.dylib` (UTF-8 exports); see `docs/plugin-porting.md`
- Themes / Appearance / UI Language / Print / Column Mode / Show Whitespace
- Open/save via `npp-fs` (UTF-8 / UTF-8-BOM / UTF-16 / ANSI); EOL conversion
- View: wrap, line numbers, zoom, bookmarks; Edit: comment, sort, indent, …

## Layout

- `crates/npp-core` — buffer, undo, document manager, search, line ops
- `crates/npp-fs` — encoding detect/decode + atomic save
- `crates/npp-config` — langs/stylers/session XML
- `crates/npp-highlight` — tree-sitter + keyword fallback + display names
- `crates/npp-ffi` — C ABI + `include/npp_ffi.h` for Swift
- `crates/npp-plugin` — plugin host skeleton
- `NppMac/` — Swift AppKit app (`Package.swift`)
- `scripts/package-app.sh` / `scripts/notarize.sh` — `.app` + notarization
- `docs/plugin-porting.md` — Win32 DLL → `.dylib` guide
- `docs/port-roadmap.md` — remaining port phases

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

Bundles `langs.model.xml` and `stylers.model.xml` into Resources.

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

## Remaining work

See `docs/port-roadmap.md`. UDL v2.1 editor is in (Language → User-Defined
Language…). Still deferred: App Sandbox, notarized DMG, Plugin Admin,
ScintillaCocoa.
