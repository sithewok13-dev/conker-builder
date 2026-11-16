// Native File Dialog on iOS: there are no desktop file dialogs, so every dialog
// reports "cancelled". The ROM comes from the Files app instead (rom_import.cpp),
// and mods are off on iOS.
//
// Only the functions RecompFrontend and CBFD-Recompiled call are here.

#include "nfd.h"

extern "C" {
    nfdresult_t NFD_Init(void) {
        return NFD_OKAY;
    }

    void NFD_Quit(void) {}

    void NFD_FreePathN(nfdnchar_t*) {}

    nfdresult_t NFD_OpenDialogN(nfdnchar_t** outPath, const nfdnfilteritem_t*, nfdfiltersize_t, const nfdnchar_t*) {
        *outPath = nullptr;
        return NFD_CANCEL;
    }

    nfdresult_t NFD_OpenDialogMultipleN(const nfdpathset_t** outPaths, const nfdnfilteritem_t*, nfdfiltersize_t,
        const nfdnchar_t*) {
        *outPaths = nullptr;
        return NFD_CANCEL;
    }

    nfdresult_t NFD_PathSet_GetCount(const nfdpathset_t*, nfdpathsetsize_t* count) {
        *count = 0;
        return NFD_OKAY;
    }

    nfdresult_t NFD_PathSet_GetPathN(const nfdpathset_t*, nfdpathsetsize_t, nfdnchar_t** outPath) {
        *outPath = nullptr;
        return NFD_ERROR;
    }

    void NFD_PathSet_Free(const nfdpathset_t*) {}
}
