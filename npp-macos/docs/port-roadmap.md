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

## Done — Phase 3: Edit extras + Rust search + FiF filters

- Toggle Line Comment, Sort Lines, Indent / Unindent in Edit menu
- Find panel: Replace / Replace All / Count via `npp-core` search FFI
- Fancy-regex + literal/whole-word find through Rust
- Find-in-Files: include globs, directory excludes, case/word/regex options

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

## Done — Phase 6 (partial): Tools / Run / Macro / Plugins shell

- Settings → Preferences, Tools MD5/SHA-256, Run… (`$FILE`)
- Macro record/stop/playback/save (text-insert steps)
- Plugins menu: discover `.dylib`/`.bundle` under Application Support, open folder
- Window menu shell

## Done — Phase 7 (partial): Print + UDL load-only

- File → Print…
- Language → Load UDL… (keyword highlighting from `.udl.xml`)
- `parse_udl` / `npp_udl_load` FFI

## Phase 4 — remaining

`config.xml` / deeper stylers Preferences.

## Phase 6 — remaining

Full Notepad++ plugin ABI / dylib load + invoke.

## Phase 7 — remaining

Style Configurator, Document Map, multi-caret/column (best-effort),
nativeLang, Dark Mode themes, Clipboard History / Character panel.
