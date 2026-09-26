# NppMac port roadmap

Phased Notepad++ macOS parity on NSTextView + Rust FFI.

## Done — Phase 1: Languages + syntax highlighting

- Compact A–Z Language menu from `langs.model.xml` (~90 stock langs)
- Keyword + comment/string fallback; tree-sitter + keyword merge
- `stylers.model.xml` colors; Style Configurator + Theme menu

## Done — Phase 2–5: Editor chrome, search, panels, file extras

(See prior commits — wrap, gutter, bookmarks, FiF filters, Folder/Function List,
Document Map, Clipboard History, session/recent/config.xml, …)

## Done — Phase 6 (partial): Plugins host

- Plugins menu: nested `<Name>/<Name>.dylib` + flat scan, `dlopen` probe
- `getNameUTF8` / `getName` when exported; open plugins folder
- Full `FuncItem` / `beNotified` dispatch still evolving (`docs/plugin-porting.md`)

## Done — Phase 7 (partial): Print, UDL, themes, column, nativeLang

- Print, UDL load-only, Document Map, Clipboard, Character Panel
- Themes + Appearance + Show Whitespace
- Edit → Column Mode (Option-drag rectangular selection; multi-insert)
- Settings → UI Language (nativeLang Entries for top-level menus)

## Remaining

- Full plugin ABI (`setInfo` / `getFuncsArray` / `messageProc` invoke)
- Deeper nativeLang (all menu item ids, dialogs)
- Multi-caret beyond column rectangles
