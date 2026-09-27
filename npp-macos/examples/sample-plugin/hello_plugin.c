/*
 * Minimal NppMac sample plugin — build:
 *   clang -shared -fPIC -o HelloNppMac.dylib hello_plugin.c \
 *     -I ../../crates/npp-plugin/include
 * Install:
 *   mkdir -p ~/Library/Application\ Support/NppMac/plugins/HelloNppMac
 *   cp HelloNppMac.dylib \
 *     ~/Library/Application\ Support/NppMac/plugins/HelloNppMac/HelloNppMac.dylib
 *
 * Exercises beNotified (logs NPPN_* / SCN_MODIFIED) and nppSendMessage
 * (NPPM_GETCURRENTBUFFERID) from the "Say Hello" command.
 */
#include "NppPluginInterface.h"

#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

static NppData g_data;

typedef intptr_t (*NppSendMessageFn)(NppHandle, unsigned int, uintptr_t, intptr_t);
static NppSendMessageFn g_send;

static NppSendMessageFn resolve_send(void) {
    if (g_send) {
        return g_send;
    }
    /* Prefer main executable — plugins are RTLD_LOCAL. */
    g_send = (NppSendMessageFn)dlsym(RTLD_MAIN_ONLY, "nppSendMessage");
    if (!g_send) {
        g_send = (NppSendMessageFn)dlsym(RTLD_DEFAULT, "nppSendMessage");
    }
    return g_send;
}

static void hello_cmd(void) {
    NppSendMessageFn send = resolve_send();
    intptr_t buf = send ? send(g_data._nppHandle, NPPM_GETCURRENTBUFFERID, 0, 0) : -1;
    intptr_t sci = send ? send(g_data._nppHandle, NPPM_GETCURRENTSCINTILLA, 0, 0) : -1;
    fprintf(stderr,
            "[HelloNppMac] Hello (npp=%llu bufferId=%ld scintilla=%ld)\n",
            (unsigned long long)g_data._nppHandle,
            (long)buf,
            (long)sci);
}

void setInfo(NppData data) {
    g_data = data;
    (void)resolve_send();
}

const char *getNameUTF8(void) { return "Hello NppMac"; }

const wchar_t *getName(void) {
    static const wchar_t name[] = L"Hello NppMac";
    return name;
}

static FuncItemUTF8 g_funcs[1];

FuncItemUTF8 *getFuncsArrayUTF8(int *nb) {
    memset(g_funcs, 0, sizeof(g_funcs));
    strncpy(g_funcs[0]._itemName, "Say Hello", NPP_MAC_MENU_ITEM_SIZE - 1);
    g_funcs[0]._pFunc = hello_cmd;
    g_funcs[0]._cmdID = 0;
    g_funcs[0]._init2Check = false;
    g_funcs[0]._pShKey = NULL;
    *nb = 1;
    return g_funcs;
}

FuncItem *getFuncsArray(int *nb) {
    *nb = 0;
    return NULL;
}

void beNotified(SCNotification *notifyCode) {
    if (!notifyCode) {
        return;
    }
    unsigned int code = notifyCode->nmhdr.code;
    switch (code) {
    case NPPN_READY:
        fprintf(stderr, "[HelloNppMac] NPPN_READY\n");
        break;
    case NPPN_FILEOPENED:
        fprintf(stderr, "[HelloNppMac] NPPN_FILEOPENED idFrom=%llu\n",
                (unsigned long long)notifyCode->nmhdr.idFrom);
        break;
    case NPPN_FILESAVED:
        fprintf(stderr, "[HelloNppMac] NPPN_FILESAVED idFrom=%llu\n",
                (unsigned long long)notifyCode->nmhdr.idFrom);
        break;
    case NPPN_FILEBEFORECLOSE:
        fprintf(stderr, "[HelloNppMac] NPPN_FILEBEFORECLOSE idFrom=%llu\n",
                (unsigned long long)notifyCode->nmhdr.idFrom);
        break;
    case NPPN_FILECLOSED:
        fprintf(stderr, "[HelloNppMac] NPPN_FILECLOSED idFrom=%llu\n",
                (unsigned long long)notifyCode->nmhdr.idFrom);
        break;
    case NPPN_BUFFERACTIVATED:
        fprintf(stderr, "[HelloNppMac] NPPN_BUFFERACTIVATED idFrom=%llu\n",
                (unsigned long long)notifyCode->nmhdr.idFrom);
        break;
    case SCN_MODIFIED:
        fprintf(stderr,
                "[HelloNppMac] SCN_MODIFIED pos=%ld len=%ld lines=%ld mod=0x%x\n",
                (long)notifyCode->position,
                (long)notifyCode->length,
                (long)notifyCode->linesAdded,
                notifyCode->modificationType);
        break;
    case NPPN_SHUTDOWN:
        fprintf(stderr, "[HelloNppMac] NPPN_SHUTDOWN\n");
        break;
    default:
        break;
    }
}

intptr_t messageProc(unsigned int Message, uintptr_t wParam, intptr_t lParam) {
    (void)Message;
    (void)wParam;
    (void)lParam;
    return 0;
}

bool isUnicode(void) { return true; }
