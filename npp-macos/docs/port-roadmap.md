# NppMac port roadmap

Phased Notepad++ macOS parity on NSTextView + Rust FFI.

## Done — Phase 1: Languages + syntax highlighting

- Compact A–Z Language menu from `langs.model.xml` (~90 stock langs)
- Tree-sitter grammars (13): rich queries for keyword/type/number/function/operator/string/comment
- Keyword langs: case-insensitive + hyphenated words; comments/strings/numbers/operators/`#preproc`
- XML CDATA interiors highlighted as HTML; diff/LaTeX dedicated scanners
- `stylers.model.xml` colors (incl. TAG/ATTRIBUTE/COMMAND/HEADER/ADDED/DELETED); Style Configurator + Theme menu
- Theme DEFAULT fg preserved on rehighlight; `isRichText`; highlight up to 2 MiB
- Stock-lang highlight audit test in `npp-ffi`

## Done — Phase 2–5: Editor chrome, search, panels, file extras

(See prior commits — wrap, gutter, bookmarks, FiF filters, Folder/Function List,
Document Map, Clipboard History, session/recent/config.xml, …)

## Done — Phase 6: Plugins host

- Discover flat + nested `<Name>/<Name>.dylib`
- `dlopen` retain, `setInfo`, `getNameUTF8`, `getFuncsArrayUTF8` → Plugins submenu
- Invoke `PFUNCPLUGINCMD` from menu (`examples/sample-plugin`)
- `beNotified` (NPPN_* / SCN_MODIFIED) + `nppSendMessage` M4 (`NPPM_GETCURRENTBUFFERID` /
  `GETCURRENTSCINTILLA` / `GETCURRENTDOCINDEX` / `MENUCOMMAND`) — see `docs/plugin-porting.md`

## Done — Phase 7: Print, UDL, themes, column, nativeLang, shortcuts, multi-caret

- Print, UDL load-only, Document Map, Clipboard, Character Panel
- Themes + Appearance + Show Whitespace
- Edit → Column Mode (Option-drag rectangular selection; multi-insert)
- Multi-caret (Cmd-click add/remove; type/delete/paste/arrows; Esc clears)
- Settings → UI Language + dialog-string nativeLang (Preferences, Find, panels)
- Settings → Shortcut Mapper (persist to AppPrefs / `config.xml`)
- Project panels: covered by View → Folder as Workspace

## Out of scope (by design)

- Plugin Admin / full UDL editor / ScintillaCocoa
- Dockable plugin panels (M5) / full Win32 `NPPM_*` surface
