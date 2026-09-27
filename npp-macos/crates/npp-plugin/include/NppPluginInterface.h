// NppMac source-compatible plugin interface (M4).
// Mirrors PowerEditor/src/MISC/PluginsManager/PluginInterface.h semantics
// for macOS ARM64. Differences from the Win32 original:
//  - HWND handles become opaque uint64_t tokens (NppHandle).
//  - __cdecl / __declspec(dllexport) become default C ABI + visibility.
//  - Plugins build as .dylib, not .dll; see docs/plugin-porting.md.
//  - SendMessage(npp, NPPM_*, …) → nppSendMessage(npp, NPPM_*, …)
//    (host exports nppSendMessage; resolve via dlsym(RTLD_DEFAULT, …)).
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <wchar.h>

#ifdef __cplusplus
extern "C" {
#endif

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

/* ---- Notification / Scintilla shim (layouts match Scintilla.h on LP64) ---- */

typedef ptrdiff_t Sci_Position;
typedef uintptr_t uptr_t;
typedef intptr_t sptr_t;

typedef struct Sci_NotifyHeader {
    void *hwndFrom;
    uptr_t idFrom;
    unsigned int code;
} Sci_NotifyHeader;

typedef struct SCNotification {
    Sci_NotifyHeader nmhdr;
    Sci_Position position;
    int ch;
    int modifiers;
    int modificationType;
    const char *text;
    Sci_Position length;
    Sci_Position linesAdded;
    int message;
    uptr_t wParam;
    sptr_t lParam;
    Sci_Position line;
    int foldLevelNow;
    int foldLevelPrev;
    int margin;
    int listType;
    int x;
    int y;
    int token;
    Sci_Position annotationLinesAdded;
    int updated;
    int listCompletionMethod;
    int characterSource;
} SCNotification;

#define SCN_MODIFIED 2008

#define SC_MOD_INSERTTEXT 0x1
#define SC_MOD_DELETETEXT 0x2

/* NPPM_* — numbers match Notepad_plus_msgs.h (NPPMSG = WM_USER+1000 = 2024). */
#define NPPMSG 2024u
#define NPPM_GETCURRENTSCINTILLA (NPPMSG + 4)   /* 2028 */
#define NPPM_GETCURRENTDOCINDEX  (NPPMSG + 23)  /* 2047 */
#define NPPM_MENUCOMMAND         (NPPMSG + 48)  /* 2072 */
#define NPPM_GETCURRENTBUFFERID  (NPPMSG + 60)  /* 2084 */

/* NPPN_* — Notepad_plus_msgs.h */
#define NPPN_FIRST 1000u
#define NPPN_READY            (NPPN_FIRST + 1)   /* 1001 */
#define NPPN_FILEBEFORECLOSE  (NPPN_FIRST + 3)   /* 1003 */
#define NPPN_FILEOPENED       (NPPN_FIRST + 4)   /* 1004 */
#define NPPN_FILECLOSED       (NPPN_FIRST + 5)   /* 1005 */
#define NPPN_FILEBEFORESAVE   (NPPN_FIRST + 7)   /* 1007 */
#define NPPN_FILESAVED        (NPPN_FIRST + 8)   /* 1008 */
#define NPPN_SHUTDOWN         (NPPN_FIRST + 9)   /* 1009 */
#define NPPN_BUFFERACTIVATED  (NPPN_FIRST + 10)  /* 1010 */

/* IDM_* subset (menuCmdID.h) for NPPM_MENUCOMMAND */
#define IDM 40000
#define IDM_FILE (IDM + 1000)
#define IDM_FILE_NEW   (IDM_FILE + 1)
#define IDM_FILE_OPEN  (IDM_FILE + 2)
#define IDM_FILE_CLOSE (IDM_FILE + 3)
#define IDM_FILE_SAVE  (IDM_FILE + 6)
#define IDM_FILE_SAVEAS (IDM_FILE + 8)
#define IDM_FILE_SAVEALL (IDM_FILE + 7)
#define IDM_FILE_RELOAD (IDM_FILE + 14)
#define IDM_EDIT (IDM + 2000)
#define IDM_EDIT_UNDO      (IDM_EDIT + 3)
#define IDM_EDIT_REDO      (IDM_EDIT + 4)
#define IDM_EDIT_SELECTALL (IDM_EDIT + 7)
#define IDM_EDIT_DUP_LINE  (IDM_EDIT + 10)
#define IDM_EDIT_JOIN_LINES (IDM_EDIT + 13)
#define IDM_EDIT_UPPERCASE (IDM_EDIT + 16)
#define IDM_EDIT_LOWERCASE (IDM_EDIT + 17)
#define IDM_EDIT_TRIMTRAILING (IDM_EDIT + 24)

__attribute__((visibility("default"))) void setInfo(NppData);
__attribute__((visibility("default"))) const wchar_t *getName(void);
__attribute__((visibility("default"))) FuncItem *getFuncsArray(int *);
__attribute__((visibility("default"))) void beNotified(SCNotification *);
__attribute__((visibility("default"))) intptr_t messageProc(unsigned int Message, uintptr_t wParam, intptr_t lParam);
__attribute__((visibility("default"))) bool isUnicode(void);

/* Optional UTF-8 exports for NppMac (preferred over wchar_t on Apple platforms). */
__attribute__((visibility("default"))) const char *getNameUTF8(void);

typedef struct {
    char _itemName[NPP_MAC_MENU_ITEM_SIZE];
    PFUNCPLUGINCMD _pFunc;
    int _cmdID;
    bool _init2Check;
    ShortcutKey *_pShKey;
} FuncItemUTF8;

__attribute__((visibility("default"))) FuncItemUTF8 *getFuncsArrayUTF8(int *);

/*
 * Host-provided SendMessage substitute.
 * Implemented by NppMac (C trampoline in Cnpp_plugin); plugins resolve via:
 *   dlsym(RTLD_MAIN_ONLY, "nppSendMessage")   -- preferred
 *   dlsym(RTLD_DEFAULT, "nppSendMessage")     -- fallback
 * NppMac semantics for M4:
 *   NPPM_GETCURRENTBUFFERID  -> LRESULT = active doc index (buffer id)
 *   NPPM_GETCURRENTSCINTILLA -> LRESULT = editor token; if lParam!=0 write view 0/1 to *(int*)lParam
 *   NPPM_GETCURRENTDOCINDEX  -> LRESULT = active doc index
 *   NPPM_MENUCOMMAND         -> lParam = IDM_*; host runs mapped menu action
 */
intptr_t nppSendMessage(NppHandle hwnd, unsigned int msg, uintptr_t wParam, intptr_t lParam);

#ifdef __cplusplus
}
#endif
