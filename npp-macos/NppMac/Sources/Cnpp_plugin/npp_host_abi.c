#include "npp_host_abi.h"

static NppSendMessageImpl g_npp_send_impl;

void nppRegisterSendMessage(NppSendMessageImpl impl) {
    g_npp_send_impl = impl;
}

intptr_t nppSendMessage(uint64_t hwnd, unsigned int msg, uintptr_t wParam, intptr_t lParam) {
    if (!g_npp_send_impl) {
        return 0;
    }
    return g_npp_send_impl(hwnd, msg, wParam, lParam);
}
