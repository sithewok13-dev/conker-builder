#pragma once

#include <cstdint>

namespace conker::ios {
    // The touch controls' N64 buttons and stick (-1 to 1, up positive), from the main thread.
    void set_touch_input(uint16_t buttons, float x, float y);
    // A tap: skip the playing cutscene, if one is playing in the next moment.
    void request_skip();
    // A cutscene is playing (the game asked whether to skip it just now).
    bool cutscene_playing();
    // The game is running and none of RecompFrontend's menus is up: the touch controls show.
    bool controls_wanted();
    // Frames presented to the screen (interpolated ones included) and frames the game made, so far.
    void frame_counts(uint64_t* presented, uint64_t* game);
    // The frame rate RT64 presents at (60 or 120; it makes the in-between frames itself, the game
    // keeps its own pace): Settings > Graphics' Framerate set to Manual at that rate, and saved.
    // From the main thread, once the game runs. Returns false if the setting wasn't there yet.
    bool set_max_fps(int fps);

    // Read by CBFD-Recompiled's input poll (patches/cbfd/0001, frontend.cpp) for player 1: the
    // touch controls, and Start pressed for the player as the intro is skipped.
    bool touch_input(uint16_t* buttons, float* x, float* y);
}
