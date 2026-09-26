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

## Done — Phase 4 (partial): Session + prefs + disk watch

- `session.xml` restore on launch / save on quit (gated by preference)
- File → Open Recent (+ Clear Menu)
- Preferences: wrap, line numbers, backup, session, disk watch, tab width
- `.bak` backup before save; auto-reload clean tabs on disk change

## Done — Phase 5 (partial): File extras + panels

- Close All but Current, Open Containing Folder, Copy File Path
- Rename…, Delete from Disk (Trash)
- Document switcher jump buttons 1–9
- Folder as Workspace sidebar, Function List (regex symbols)

## Done — Phase 6 (partial): Tools / Run / Settings

- Settings → Preferences, Tools MD5/SHA-256 (file + selection), Run… (`$FILE`)
- Window menu shell

## Phase 3 — remaining

Find-in-Files filters.

## Phase 4 — remaining

`config.xml` / deeper stylers Preferences.

## Phase 6 — remaining

Macro menu, Plugins dylib host.

## Phase 7 — Stretch

UDL load-only, Style Configurator, Document Map, multi-caret/column (best-effort),
Print, nativeLang, Dark Mode themes, Clipboard History / Character panel.
