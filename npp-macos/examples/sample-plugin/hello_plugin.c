/*
 * Minimal NppMac sample plugin — build:
 *   clang -shared -o HelloNppMac.dylib hello_plugin.c -I ../../crates/npp-plugin/include
 * Install:
 *   mkdir -p ~/Library/Application\ Support/NppMac/plugins/HelloNppMac
 *   cp HelloNppMac.dylib ~/Library/Application\ Support/NppMac/plugins/HelloNppMac/HelloNppMac.dylib
 */
#include "NppPluginInterface.h"
#include <stdio.h>
#include <string.h>

static NppData g_data;

static void hello_cmd(void) {
    fprintf(stderr, "[HelloNppMac] Hello from plugin (npp=%llu)\n",
            (unsigned long long)g_data._nppHandle);
}

void setInfo(NppData data) { g_data = data; }

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

void beNotified(const void *notifyCode) { (void)notifyCode; }

intptr_t messageProc(unsigned int Message, uintptr_t wParam, intptr_t lParam) {
    (void)Message;
    (void)wParam;
    (void)lParam;
    return 0;
}

bool isUnicode(void) { return true; }
