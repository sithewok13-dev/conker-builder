// iOS entry point for the game build (built when the ROM-derived code is there).
//
// SDL owns the app on iOS: SDL_UIKitRunApp starts UIKit with SDL's app delegate,
// which calls run_game on the main thread once the app has launched. run_game
// sets the game up the iOS way, then runs CBFD-Recompiled's own main
// (conker_main, patches/cbfd), whose loop pumps SDL's events and with them UIKit's.
//
//  - Everything the game writes (settings, saves, the stored ROM, mods) goes to
//    Documents, which the Files app shows as On My iPhone > Conker.
//  - Its output goes to Documents/conker-log.txt.
//  - The ROM comes from Documents too (rom_import.cpp), the first time.

#define SDL_MAIN_HANDLED
#include <SDL.h>
#include <SDL_main.h>

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <sys/utsname.h>
#include <unistd.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <vector>

#include "rom_import.h"
#include "touch_controls.h"

int conker_main(int argc, char** argv);
// patches/plume/0007: GPU work waits while this is set.
extern "C" void plume_metal_set_gpu_paused(bool paused);

namespace {
    std::filesystem::path documents_directory() {
        NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                                                inDomains:NSUserDomainMask].firstObject;
        return std::filesystem::path(documents.path.fileSystemRepresentation);
    }

    // A fresh log on each launch, unbuffered, so after a crash its last line shows
    // the step that was running.
    void redirect_output(const std::filesystem::path &documents) {
        const std::string log = (documents / "conker-log.txt").string();
        if (std::freopen(log.c_str(), "w", stdout) != nullptr) {
            std::setvbuf(stdout, nullptr, _IONBF, 0);
            dup2(fileno(stdout), STDERR_FILENO);
            std::setvbuf(stderr, nullptr, _IONBF, 0);
        }
    }

    // Pointer positions, and the app leaving and returning to the foreground.
    //
    // The menus (recompui) lay themselves out in the swap chain's pixels, while SDL reports
    // touches, as mouse events, in UIKit points: a tap on a button landed at a third of its
    // position on a 3x screen. Positions are scaled to pixels as SDL queues the events;
    // relative motion (camera drags) is left as it is.
    float pointer_scale = 1.0f;

    int SDLCALL scale_pointer_events(void *, SDL_Event *event) {
        auto scale = [](Sint32 &value) { value = (Sint32)std::lround(value * pointer_scale); };
        switch (event->type) {
            case SDL_MOUSEMOTION:
                scale(event->motion.x);
                scale(event->motion.y);
                break;
            case SDL_MOUSEBUTTONDOWN:
            case SDL_MOUSEBUTTONUP:
                scale(event->button.x);
                scale(event->button.y);
                break;
            case SDL_MOUSEWHEEL:
                scale(event->wheel.mouseX);
                scale(event->wheel.mouseY);
                break;
            // iOS doesn't let a backgrounded app submit GPU work: switching apps crashed the game.
            // SDL sends these as the app leaves and re-enters the foreground, synchronously,
            // through this filter.
            case SDL_APP_WILLENTERBACKGROUND:
                std::fprintf(stderr, "[ios] to the background: GPU work paused\n");
                plume_metal_set_gpu_paused(true);
                break;
            case SDL_APP_DIDENTERFOREGROUND:
                std::fprintf(stderr, "[ios] back in the foreground: GPU work resumed\n");
                plume_metal_set_gpu_paused(false);
                break;
            default:
                break;
        }
        return 1;
    }

    // 0.3.0 rendered at the full screen's resolution and the display's 120 Hz, RecompFrontend's
    // desktop defaults, which made the game choppy on a phone. Newer builds default to 480p and
    // 60 frames a second on iOS (patches/recompfrontend/0002); a settings file saved by an older
    // build is moved to those once. Settings > Graphics can raise them again.
    void apply_ios_graphics_defaults_once(const std::filesystem::path &documents) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        if ([defaults integerForKey:@"iosGraphicsDefaults"] >= 1) {
            return;
        }
        [defaults setInteger:1 forKey:@"iosGraphicsDefaults"];

        NSString *path = [NSString stringWithUTF8String:(documents / "graphics.json").c_str()];
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data == nil) {
            return;
        }
        NSMutableDictionary *graphics = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        if (![graphics isKindOfClass:NSMutableDictionary.class]) {
            return;
        }
        graphics[@"res_option"] = @"Original2x";
        graphics[@"rr_option"] = @"Manual";
        graphics[@"rr_manual_value"] = @60;
        NSData *updated = [NSJSONSerialization dataWithJSONObject:graphics options:NSJSONWritingPrettyPrinted error:nil];
        if (updated != nil && [updated writeToFile:path atomically:YES]) {
            std::fprintf(stderr, "[ios] graphics: 480p (Original 2x) at 60 FPS, once\n");
        }
    }

    // The touch controls' looking (the right stick, drags, the gyro) is sent as the mouse, which
    // CBFD-Recompiled scales by Mouse: Sensitivity. Its default is 100% on iOS since 0.3.0, but a
    // settings file saved by an older build kept 0, which turns the mouse off: set it once.
    void apply_ios_mouse_default_once(const std::filesystem::path &documents) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        if ([defaults integerForKey:@"iosMouseDefaults"] >= 1) {
            return;
        }
        [defaults setInteger:1 forKey:@"iosMouseDefaults"];

        NSString *path = [NSString stringWithUTF8String:(documents / "mouse_gyro.json").c_str()];
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data == nil) {
            return;
        }
        NSMutableDictionary *mouse = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        if (![mouse isKindOfClass:NSMutableDictionary.class] || [mouse[@"mouse_sensitivity"] doubleValue] > 0) {
            return;
        }
        mouse[@"mouse_sensitivity"] = @100;
        mouse[@"mouse_turns_camera"] = @"On";
        NSData *updated = [NSJSONSerialization dataWithJSONObject:mouse options:NSJSONWritingPrettyPrinted error:nil];
        if (updated != nil && [updated writeToFile:path atomically:YES]) {
            std::fprintf(stderr, "[ios] mouse: sensitivity 100%% (the touch controls' looking), once\n");
        }
    }

    void show_message(const char *message) {
        std::fprintf(stderr, "[ios] %s\n", message);
        SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_INFORMATION, "Conker's Bad Fur Day", message, nullptr);
    }

    int run_game(int, char **argv) {
        const std::filesystem::path documents = documents_directory();
        redirect_output(documents);

        struct utsname system_info;
        uname(&system_info);
        NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        std::fprintf(stderr, "[ios] Conker %s on %s, %s %s\n", version.UTF8String, system_info.machine,
            UIDevice.currentDevice.systemName.UTF8String, UIDevice.currentDevice.systemVersion.UTF8String);

        // recompui keeps the game's data in APP_FOLDER_PATH when it's set.
        setenv("APP_FOLDER_PATH", documents.c_str(), 1);
        apply_ios_graphics_defaults_once(documents);
        apply_ios_mouse_default_once(documents);

        SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
        SDL_SetHint(SDL_HINT_IOS_HIDE_HOME_INDICATOR, "1");
        // Sound plays with the ring/silent switch on silent too, as in a game app.
        SDL_SetHint(SDL_HINT_AUDIO_CATEGORY, "playback");
        // SDL lists the iPhone's accelerometer as a joystick, which the game took for a controller.
        SDL_SetHint(SDL_HINT_ACCELEROMETER_AS_JOYSTICK, "0");
        // SDL's Metal view renders at the screen's native scale (SDL_WINDOW_ALLOW_HIGHDPI).
        pointer_scale = (float)UIScreen.mainScreen.nativeScale;
        SDL_SetEventFilter(scale_pointer_events, nullptr);
        std::fprintf(stderr, "[ios] touch positions scaled by %.2f\n", pointer_scale);

        std::vector<std::string> args{ argv[0] };
        std::error_code error;
        if (!std::filesystem::is_regular_file(documents / conker::kStoredRomName, error)) {
            std::filesystem::path rom;
            std::string message;
            if (!conker::find_rom(documents, std::filesystem::temp_directory_path(error), rom, message)) {
                show_message(message.c_str());
                return EXIT_FAILURE;
            }
            std::fprintf(stderr, "[ios] rom: using %s\n", rom.filename().string().c_str());
            args.push_back("--rom");
            args.push_back(rom.string());
        }

        // The touch controls go over SDL's window once the game has made it (they show only
        // while the game runs, not in the launcher).
        dispatch_async(dispatch_get_main_queue(), ^{
            conker_touch_controls_install();
        });

        std::vector<char *> game_argv;
        for (std::string &arg : args) {
            game_argv.push_back(arg.data());
        }
        game_argv.push_back(nullptr);
        const int result = conker_main((int)args.size(), game_argv.data());
        std::fprintf(stderr, "[ios] the game returned %d\n", result);
        if (result != EXIT_SUCCESS) {
            show_message("The game couldn't start. If you just added your ROM, make sure it's the USA version. "
                "conker-log.txt in Files > On My iPhone > Conker says what happened.");
        }
        return result;
    }
}

int main(int argc, char *argv[]) {
    return SDL_UIKitRunApp(argc, argv, run_game);
}
