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

## Done — Phase 3 (partial): Edit extras

- Toggle Line Comment, Sort Lines, Indent / Unindent in Edit menu
- Full FFI search/lineops + Find replace-all still pending

## Phase 3 — remaining

Wire `npp-core` search/lineops through FFI; Find replace-one/all/count;
Find-in-Files filters.

## Phase 4 — Session, recent files, Preferences

`session.xml` / `config.xml`, File→Recent, Preferences bound to settings,
backup on save, external-change reload.

## Phase 5 — View panels + File extras

Document list, Function List, Folder as Workspace, Close Multiple, Open
Containing Folder, Rename/Delete/Save Copy As.

## Phase 6 — Plugins host + menus shell

Settings/Tools/Macro/Run/Plugins/Window; MD5/SHA; Run…; dylib plugin host.

## Phase 7 — Stretch

UDL load-only, Style Configurator, Document Map, multi-caret/column (best-effort),
Print, nativeLang, Dark Mode themes, Clipboard History / Character panel.
