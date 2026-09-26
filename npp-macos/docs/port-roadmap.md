# NppMac port roadmap

Phased Notepad++ macOS parity on NSTextView + Rust FFI.

## Done — Phase 1: Languages + syntax highlighting

- Compact A–Z Language menu from `langs.model.xml` (~90 stock langs)
- `npp_doc_set_language`, language catalog FFI, XML extension map
- Keyword + comment/string fallback; tree-sitter + keyword merge
- `stylers.model.xml` colors in the editor
- Auto-detect, checkmarks, display names in status bar

## Done — Phase 2: Editor chrome + Format

- Word wrap toggle, line-number gutter, zoom in/out/reset
- Bookmarks (toggle / next / prev / clear)
- Encoding UTF-16 LE/BE + EOL Conversion (CRLF/LF/CR)
- Status bar: Ln/Col + EOL + language display name

## Done — Phase 3 (partial): Edit extras + Rust search

- Toggle Line Comment, Sort Lines, Indent / Unindent in Edit menu
- Find panel: Replace / Replace All / Count via `npp-core` search FFI
- Fancy-regex + literal/whole-word find through Rust

## Done — Phase 4 (partial): Session + recent files

- `session.xml` restore on launch / save on quit
- File → Open Recent (+ Clear Menu)
- `read_session` / `read_recent` / `write_recent` in npp-config

## Phase 3 — remaining

Find-in-Files filters; Preferences/`config.xml` binding.

## Phase 4 — remaining

Preferences window bound to real settings, backup on save,
external-change reload.

## Done — Phase 5 (partial): File extras

- Close All but Current, Open Containing Folder, Copy File Path
- Rename…, Delete from Disk (Trash)
- Document switcher jump buttons 1–9

## Phase 5 — remaining

Function List, Folder as Workspace / file browser sidebar.

## Phase 6 — Plugins host + menus shell

Settings/Tools/Macro/Run/Plugins/Window; MD5/SHA; Run…; dylib plugin host.

## Phase 7 — Stretch

UDL load-only, Style Configurator, Document Map, multi-caret/column (best-effort),
Print, nativeLang, Dark Mode themes, Clipboard History / Character panel.
