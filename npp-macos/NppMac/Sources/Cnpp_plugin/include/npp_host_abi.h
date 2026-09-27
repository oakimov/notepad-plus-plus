#ifndef NPP_HOST_ABI_H
#define NPP_HOST_ABI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef intptr_t (*NppSendMessageImpl)(uint64_t hwnd, unsigned int msg, uintptr_t wParam, intptr_t lParam);

/// Called once by the Swift host to install the NPPM_* dispatcher.
void nppRegisterSendMessage(NppSendMessageImpl impl);

/// SendMessage substitute for plugins (exported from the NppMac executable).
intptr_t nppSendMessage(uint64_t hwnd, unsigned int msg, uintptr_t wParam, intptr_t lParam);

#ifdef __cplusplus
}
#endif

#endif
