#include "rom_import.h"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <fstream>
#include <system_error>

#include "miniz.h"

// Based on sote-ios's rom_import.cpp.
namespace conker {
    namespace {
        std::string lowercase_extension(const std::filesystem::path &path) {
            std::string extension = path.extension().string();
            std::transform(extension.begin(), extension.end(), extension.begin(),
                [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
            return extension;
        }

        bool is_rom_extension(const std::string &extension) {
            return extension == ".z64" || extension == ".v64" || extension == ".n64";
        }

        // Extracts the first ROM-looking file inside a .zip to `target`.
        bool extract_zip(const std::filesystem::path &path, const std::filesystem::path &target) {
            mz_zip_archive zip{};
            if (!mz_zip_reader_init_file(&zip, path.string().c_str(), 0)) {
                return false;
            }

            bool found = false;
            const mz_uint count = mz_zip_reader_get_num_files(&zip);
            for (mz_uint i = 0; i < count && !found; i++) {
                char name[512];
                if (mz_zip_reader_is_file_a_directory(&zip, i) ||
                    mz_zip_reader_get_filename(&zip, i, name, sizeof(name)) == 0 ||
                    !is_rom_extension(lowercase_extension(name))) {
                    continue;
                }
                found = mz_zip_reader_extract_to_file(&zip, i, target.string().c_str(), 0);
            }

            mz_zip_reader_end(&zip);
            return found;
        }
    }

    bool find_rom(const std::filesystem::path &directory, const std::filesystem::path &scratch,
        std::filesystem::path &rom, std::string &message) {
        std::error_code error;
        for (const auto &entry : std::filesystem::directory_iterator(directory, error)) {
            if (!entry.is_regular_file(error) || entry.path().filename() == kStoredRomName) {
                continue;
            }

            const std::filesystem::path &path = entry.path();
            const std::string extension = lowercase_extension(path);
            if (is_rom_extension(extension)) {
                rom = path;
                return true;
            }
            if (extension == ".zip") {
                std::filesystem::create_directories(scratch, error);
                const std::filesystem::path target = scratch / "conker-from-zip.z64";
                if (extract_zip(path, target)) {
                    std::fprintf(stderr, "[ios] rom: extracted %s\n", path.filename().string().c_str());
                    rom = target;
                    return true;
                }
                std::fprintf(stderr, "[ios] rom: %s has no .z64/.v64/.n64 inside\n", path.filename().string().c_str());
            }
        }

        message = "Copy your own Conker's Bad Fur Day (USA) ROM into Files > On My iPhone > Conker "
            "(a .z64, .v64 or .n64, or a .zip with one inside), then open the app again.";
        return false;
    }
}
