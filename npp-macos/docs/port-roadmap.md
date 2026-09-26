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

- Discover flat + nested `<Name>/<Name>.dylib`
- `dlopen` retain, `setInfo`, `getNameUTF8`, `getFuncsArrayUTF8` → Plugins submenu
- Invoke `PFUNCPLUGINCMD` from menu (`examples/sample-plugin`)
- `beNotified` / `messageProc` / `NPPM_*` still open (`docs/plugin-porting.md`)

## Done — Phase 7 (partial): Print, UDL, themes, column, nativeLang

- Print, UDL load-only, Document Map, Clipboard, Character Panel
- Themes + Appearance + Show Whitespace
- Edit → Column Mode (Option-drag rectangular selection; multi-insert)
- Settings → UI Language (Entries + Commands + SubEntries via English-title map)

## Remaining

- `beNotified` + `messageProc` / `NPPM_*` host dispatch
- Multi-caret beyond column rectangles
- Dialog-string nativeLang (Preferences, Find, …)
