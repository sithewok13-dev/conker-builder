#pragma once

#include <filesystem>
#include <string>

namespace conker {
    // The copy librecomp keeps once a ROM has been accepted (GameEntry::stored_filename()
    // for CBFD-Recompiled's game id), in the app's data folder.
    inline constexpr const char *kStoredRomName = "conker.n64.us.1.0.z64";

    // Finds the player's own ROM in `directory` (the app's Documents, Files >
    // On My iPhone > Conker): a .z64, .v64 or .n64 under any name, or a .zip
    // holding one. A ROM in a .zip is extracted to `scratch`. Sets `rom` to the
    // file to give CBFD-Recompiled's --rom, which checks it is the US version
    // and fixes its byte order. Returns false with a message if there is none.
    bool find_rom(const std::filesystem::path &directory, const std::filesystem::path &scratch,
        std::filesystem::path &rom, std::string &message);
}
