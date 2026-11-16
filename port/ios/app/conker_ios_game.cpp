// The game side of the iOS app: the touch controls' input, and skipping the intro and
// cutscenes (the hooks patches/cbfd/0002 adds to CBFD-Recompiled's conker.toml).
//
// CBFD-Recompiled ships both skips as mods (Skip Intro, Skip Any Cutscene), but mods can't
// run on iOS, so they're built in here instead, as ConkerBFDReloaded does (MIT; its
// host/src/scene_fixes.cpp and qol.cpp, after CBFD-Recompiled's mods/skip_intro by
// Christopher Conley, MIT).

#include "conker_ios_game.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <exception>

#include "recomp.h"
#include "librecomp/config.hpp"
#include "recompui/config.h"
#include "recompui/recompui.h"
#include "ultramodern/config.hpp"
#include "ultramodern/ultramodern.hpp"

extern "C" void func_1501C730(uint8_t* rdram, recomp_context* ctx);

namespace RT64 {
    // Frames presented to the screen, interpolated ones included (CBFD-Recompiled's rt64.patch).
    uint64_t presentedFrameCount();
}

// Frames the game itself made (patches/cbfd/0001, fps_counter.cpp).
uint64_t conker_ios_game_frames();

namespace {
    using clock = std::chrono::steady_clock;

    int64_t now_ms() {
        return std::chrono::duration_cast<std::chrono::milliseconds>(clock::now().time_since_epoch()).count();
    }

    // The touch controls' state, from the main thread; read by the game's input poll.
    std::atomic<uint16_t> touch_buttons{ 0 };
    std::atomic<float> touch_x{ 0.0f };
    std::atomic<float> touch_y{ 0.0f };
    // A tap asks to skip the playing cutscene until this time.
    std::atomic<int64_t> skip_requested_until{ 0 };
    // When the game last asked whether to skip a cutscene: one is playing.
    std::atomic<int64_t> cutscene_seen{ 0 };

    constexpr uint16_t button_start = 0x1000;
    constexpr int64_t skip_request_ms = 600;

    // Skip Intro. The game boots through 0x25 (the notices and logos), 0x21 (the chainsaw
    // opening) and 0x1D (the bar, where Start brings up the save menu). Once the logos have run
    // 10 frames, the bar is asked for in place of the opening; once it has loaded, what the
    // opening's end would have left behind is set; then Start is pressed for the player.
    enum class Skip { Logos, Bar, PressingStart, Done };
    std::atomic<Skip> skip_state{ Skip::Logos };
    std::atomic<uint8_t*> game_rdram{ nullptr };
    constexpr uint32_t bar = 0x1D;
    constexpr int32_t current_room = (int32_t)0x800BE9F0;
    constexpr int32_t room_timer = (int32_t)0x800E0A90; // refreshes since the room began
    constexpr int32_t logo_frames_before_skip = 10;     // earlier, the bar never loads (the mod's measurement)
    constexpr int32_t press_start_at = 20, stop_start_at = 60; // the bar's room timer

    // Start, pressed for the player in the bar until its timer reaches stop_start_at.
    bool skip_intro_presses_start() {
        uint8_t* rdram = game_rdram.load();
        Skip state = skip_state.load();
        if (rdram == nullptr || (state != Skip::Bar && state != Skip::PressingStart) ||
            (uint32_t)MEM_W(0, current_room) != bar) {
            return false;
        }
        const int32_t timer = MEM_W(0, room_timer);
        if (state == Skip::Bar && timer >= press_start_at) {
            skip_state = Skip::PressingStart;
            state = Skip::PressingStart;
        }
        if (state == Skip::PressingStart && timer >= stop_start_at) {
            skip_state = Skip::Done;
            std::fprintf(stderr, "[ios] intro skipped\n");
            return false;
        }
        return state == Skip::PressingStart;
    }
}

void conker::ios::set_touch_input(uint16_t buttons, float x, float y) {
    touch_buttons = buttons;
    touch_x = x;
    touch_y = y;
}

void conker::ios::request_skip() {
    skip_requested_until = now_ms() + skip_request_ms;
}

bool conker::ios::cutscene_playing() {
    return now_ms() - cutscene_seen.load() < 250;
}

bool conker::ios::controls_wanted() {
    // RecompFrontend's menus capture the mouse; the game's overlays (the aiming reticle,
    // notices) are contexts too, but don't.
    return ultramodern::is_game_started() && !recompui::is_context_capturing_mouse();
}

void conker::ios::frame_counts(uint64_t* presented, uint64_t* game) {
    *presented = RT64::presentedFrameCount();
    *game = conker_ios_game_frames();
}

bool conker::ios::set_max_fps(int fps) {
    // RT64 interpolates up to the rate asked, capped at what the screen reports (60 on a phone
    // without ProMotion). The game's logic never reads it.
    namespace options = recompui::config::graphics::options;
    try {
        recomp::config::Config& config = recompui::config::get_graphics_config();
        config.set_option_value(options::rr_option, (uint32_t)ultramodern::renderer::RefreshRate::Manual);
        config.apply_option_value(options::rr_option);
        config.set_option_value(options::rr_manual_value, (double)fps);
        config.apply_option_value(options::rr_manual_value);
        config.save_config();
    } catch (const std::exception& e) {
        std::fprintf(stderr, "[ios] frame rate: settings not ready (%s)\n", e.what());
        return false;
    }

    ultramodern::renderer::GraphicsConfig graphics = ultramodern::renderer::get_graphics_config();
    graphics.rr_option = ultramodern::renderer::RefreshRate::Manual;
    graphics.rr_manual_value = fps;
    ultramodern::renderer::set_graphics_config(graphics);
    std::fprintf(stderr, "[ios] frame rate: RT64 presents up to %d a second\n", fps);
    return true;
}

bool conker::ios::touch_input(uint16_t* buttons, float* x, float* y) {
    *buttons = touch_buttons.load();
    *x = touch_x.load();
    *y = touch_y.load();
    if (skip_intro_presses_start()) {
        *buttons |= button_start;
    }
    return true;
}

// func_151DE6D4 (the logos' frame) at its return: after 10 frames, ask for the bar in place of
// the opening, as the logos' own end asks for the opening.
extern "C" void conker_skip_intro_logos(uint8_t* rdram, recomp_context* ctx) {
    game_rdram = rdram;
    if (skip_state != Skip::Logos || MEM_W(0, room_timer) < logo_frames_before_skip) {
        return;
    }
    skip_state = Skip::Bar;
    MEM_B(0, (int32_t)0x8008FE28) = 2;
    MEM_B(0, (int32_t)0x800E0B94) = 1; // boot phase
    MEM_B(0, (int32_t)0x800D2E40) = 0;
    // func_1501C730(6, bar, 0, 0, 1), from a hook: registers saved and put back, the fifth
    // argument in this function's outgoing argument space.
    recomp_context saved = *ctx;
    const int32_t saved_arg = MEM_W(0x10, ctx->r29);
    ctx->r4 = 6;
    ctx->r5 = (int32_t)bar;
    ctx->r6 = 0;
    ctx->r7 = 0;
    MEM_W(0x10, ctx->r29) = 1;
    func_1501C730(rdram, ctx);
    MEM_W(0x10, saved.r29) = saved_arg;
    *ctx = saved;
    MEM_B(0, (int32_t)0x800E0B96) = 0xFF;
}

// func_15007A70 (a room change) at its return, the room loaded: in the bar, what the opening's
// end (func_151DE85C) would have left behind. Without it the bar is empty and Start does nothing.
extern "C" void conker_skip_intro_room_loaded(uint8_t* rdram, recomp_context* ctx) {
    (void)ctx;
    game_rdram = rdram;
    if (skip_state != Skip::Bar || (uint32_t)MEM_W(0, current_room) != bar || MEM_W(0, room_timer) > 5) {
        return;
    }
    MEM_B(0, (int32_t)0x800D2E40) = 0;
    MEM_B(0, (int32_t)0x800E0B94) = 3; // boot phase
    MEM_B(0, (int32_t)0x8008FD80) = 1;
    MEM_B(0, (int32_t)0x8008FE28) = 2;
    MEM_B(0, (int32_t)0x8008FDA4) = 0;
    const int32_t game_state = MEM_W(0, (int32_t)0x8008FDD4);
    if (game_state != 0) {
        MEM_B(0x3E, game_state) = 0;
        MEM_B(0x2B, game_state) = 5;
        MEM_B(0x2C, game_state) = 5;
    }
}

// func_1501E05C, the game's "skip the playing cutscene?" check, where its paths meet before
// returning ($v0 the answer): a tap says yes, for any cutscene, even unwatched or ones the game
// never lets you skip (as CBFD-Recompiled's Skip Any Cutscene mod allows). Not the game over (the
// throne room, 0x18, its cutscene 0x0F): forced to end, it ends in the throne room as if it were a
// level; the game skips it itself, to the menu, on a press.
extern "C" void conker_skip_cutscene_result(uint8_t* rdram, recomp_context* ctx) {
    cutscene_seen = now_ms();
    const bool game_over = (uint32_t)MEM_W(0, current_room) == 0x18 &&
        (uint8_t)MEM_BU(0, (int32_t)0x800C35E8) == 0x0F;
    if (game_over || now_ms() > skip_requested_until.load()) {
        return;
    }
    skip_requested_until = 0;
    ctx->r2 = 1;
    std::fprintf(stderr, "[ios] cutscene skipped (room %02X)\n", (uint32_t)MEM_W(0, current_room));
}
