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
| `SendMessage(npp, NPPM_*, …)` with HWNDs | same message numbers (M4 subset first), handles are tokens |

## M4 message subset

`NPPM_GETCURRENTBUFFERID`, `NPPM_GETCURRENTSCINTILLA`, `NPPM_MENUCOMMAND`
(via the shared `IDM_*` table from `menuCmdID.h`), `beNotified` edit events
translated from the Rust buffer into `SCNotification`-shaped payloads.
Dockable panels (`DockingWnd`) arrive in M5 — modeless dialogs first.
