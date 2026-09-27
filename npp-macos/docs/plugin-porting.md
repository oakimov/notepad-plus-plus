# Plugin porting guide (Win32 DLL → NppMac .dylib)

Source: `PowerEditor/src/MISC/PluginsManager/PluginInterface.h:28-73`
(6 C exports, `NppData` = 3× `HWND`), `Notepad_plus_msgs.h` (118 `NPPM_*`).

## Why rebuilds are required

Win32 plugin binaries cannot load on macOS ARM64: different CPU ABI,
`HWND`/`LRESULT`/`LoadLibrary` do not exist. NppMac is **source-compatible**:
same export names and `FuncItem`/`ShortcutKey` shapes, new header
`crates/npp-plugin/include/NppPluginInterface.h`.

## Mechanical changes

| Win32 original | NppMac |
|---|---|
| `#include "PluginInterface.h"` | `#include "NppPluginInterface.h"` |
| `NppData` with `HWND` fields | `NppData` with `NppHandle` (`uint64_t`) tokens — never dereference, pass back to `NPPM_*` calls |
| `__cdecl`, `__declspec(dllexport)` | default C ABI, `visibility("default")` (already in the header) |
| `.dll` + `LoadLibrary` | `.dylib` in `~/Library/Application Support/NppMac/plugins/<Name>/<Name>.dylib`, loaded via `dlopen` |
| `SendMessage(npp, NPPM_*, …)` with HWNDs | `nppSendMessage(npp, NPPM_*, …)` — host exports the symbol; resolve with `dlsym(RTLD_MAIN_ONLY, "nppSendMessage")` (fallback: `RTLD_DEFAULT`) |

## Preferred macOS exports (UTF-8)

`wchar_t` on Apple is 32-bit; Swift interop is awkward. Export these as well:

| Symbol | Purpose |
|---|---|
| `getNameUTF8` | Plugin menu title (`const char *`) |
| `getFuncsArrayUTF8` | `FuncItemUTF8[]` with `char _itemName[64]` |

The host calls `setInfo`, then prefers UTF-8 helpers, then falls back to probing `getName` as ASCII C string.
After `setInfo` it also `dlsym`s `beNotified` and `messageProc`.

Sample: `examples/sample-plugin/hello_plugin.c`

```bash
cd examples/sample-plugin
clang -shared -fPIC -o HelloNppMac.dylib hello_plugin.c \
  -I ../../crates/npp-plugin/include
mkdir -p ~/Library/Application\ Support/NppMac/plugins/HelloNppMac
cp HelloNppMac.dylib \
  ~/Library/Application\ Support/NppMac/plugins/HelloNppMac/HelloNppMac.dylib
```

Then **Plugins → Refresh Plugin List** — you should see **Hello NppMac → Say Hello**.
Run the app from a terminal to see `[HelloNppMac]` stderr logs for `NPPN_*` / `SCN_MODIFIED`
and buffer/scintilla tokens when invoking **Say Hello**.

## Host support today

| Feature | Status |
|---|---|
| Discover flat + nested `<Name>/<Name>.dylib` | Done |
| `dlopen` + keep handle | Done |
| `setInfo(NppData)` | Done (opaque tokens; ARM64 passes struct by hidden pointer) |
| `getNameUTF8` / `getFuncsArrayUTF8` → Plugins submenu | Done |
| Invoke `PFUNCPLUGINCMD` from menu | Done |
| `beNotified` edit / file events | Done (`SCN_MODIFIED`, `NPPN_READY`, `NPPN_FILEOPENED`, `NPPN_FILESAVED`, `NPPN_FILEBEFORECLOSE`/`CLOSED`, `NPPN_BUFFERACTIVATED`, `NPPN_SHUTDOWN`) |
| `nppSendMessage` / `NPPM_*` dispatch | Done (M4 subset below) |
| Classic `wchar_t` `FuncItem` / `getFuncsArray` | Not loaded (use UTF-8 exports) |

## M4 message subset

| Message | NppMac behaviour |
|---|---|
| `NPPM_GETCURRENTBUFFERID` (2084) | LRESULT = active doc index (buffer id) |
| `NPPM_GETCURRENTSCINTILLA` (2028) | LRESULT = editor token; if `lParam ≠ 0` write view `0`/`1` to `*(int*)lParam` |
| `NPPM_GETCURRENTDOCINDEX` (2047) | LRESULT = active doc index |
| `NPPM_MENUCOMMAND` (2072) | `lParam` = `IDM_*`; host runs mapped Swift menu action (File New/Open/Close/Save/…, Edit Undo/Redo/…) |

`beNotified` payloads are `SCNotification`-shaped (160 bytes on LP64). Edit events use UTF-8 byte offsets from `NSTextView`.

Dockable panels (`DockingWnd`) arrive in M5 — modeless dialogs first.
