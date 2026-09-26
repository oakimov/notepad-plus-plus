// NppMac source-compatible plugin interface (M4).
// Mirrors PowerEditor/src/MISC/PluginsManager/PluginInterface.h semantics
// for macOS ARM64. Differences from the Win32 original:
//  - HWND handles become opaque uint64_t tokens (NppHandle).
//  - __cdecl / __declspec(dllexport) become default C ABI + visibility.
//  - Plugins build as .dylib, not .dll; see docs/plugin-porting.md.
#pragma once

#include <stdbool.h>
#include <stdint.h>

typedef uint64_t NppHandle;

typedef struct {
    NppHandle _nppHandle;
    NppHandle _scintillaMainHandle;
    NppHandle _scintillaSecondHandle;
} NppData;

typedef void (*PFUNCPLUGINCMD)(void);

typedef struct {
    bool _isCtrl;
    bool _isAlt;
    bool _isShift;
    unsigned char _key;
} ShortcutKey;

#define NPP_MAC_MENU_ITEM_SIZE 64

typedef struct {
    wchar_t _itemName[NPP_MAC_MENU_ITEM_SIZE];
    PFUNCPLUGINCMD _pFunc;
    int _cmdID;
    bool _init2Check;
    ShortcutKey *_pShKey;
} FuncItem;

typedef FuncItem *(*PFUNCGETFUNCSARRAY)(int *);

__attribute__((visibility("default"))) void setInfo(NppData);
__attribute__((visibility("default"))) const wchar_t *getName(void);
__attribute__((visibility("default"))) FuncItem *getFuncsArray(int *);
__attribute__((visibility("default"))) void beNotified(const void *);
__attribute__((visibility("default"))) intptr_t messageProc(unsigned int Message, uintptr_t wParam, intptr_t lParam);
__attribute__((visibility("default"))) bool isUnicode(void);
