# Conker's Bad Fur Day for iOS

The port behind this template: Conker's Bad Fur Day (N64) on iPhone and iPad, built on
[CBFD-Recompiled], [N64Recomp], [N64ModernRuntime] and [RT64] (Metal through
plume). It follows the same plan as the owner's Shadows of the Empire port (SotE).

**This repository holds no ROM-derived code and no game data.** The game's code
is generated from each player's own ROM (the US version, SHA-1
`4cbadd3c4e0729dec46af64ad018050eada4f47a`) in their own private copy, by
`.github/workflows/build.yml`. `.gitignore` blocks ROM files and the
recompiler's output.

## Status

| Step | State |
| --- | --- |
| Repo, GPL-3.0 licence, pinned submodules | done |
| iOS shell: UIKit app, plume on Metal, rdram reservation probe | builds (0.1.0); needs a device run |
| RT64 on iOS with Conker's RT64 patch and the SotE port's Metal fixes | builds (0.1.0) |
| Game code generated from the ROM in CI and compiled for iOS | works (0.1.0) |
| Game layer: CBFD-Recompiled's `host/` code (MIT) and RecompFrontend on iOS, through SDL's UIKit app | first attempt (0.2.0) |
| Touch controls | later |

## Why CBFD-Recompiled

[CBFD-Recompiled] by Sean Ciaschi is MIT-licensed, playable to the end, and
already builds for macOS on Apple Silicon with Metal. It pins N64Recomp to the
same commit the SotE port uses, and RT64 to a commit with the same plume, so the
iOS patches from the SotE port apply unchanged on top of its own. Its repository
holds the function names and addresses the recompiler needs
(`recomp/conker.us.syms.toml`), never the game's code. [ConkerBFDReloaded]
(also MIT, Windows and Linux) builds on it and has extra features worth
borrowing later.

## Layout

Paths below are inside `port/`. The sources under `third_party/` are not in
the repository: `tools/fetch-sources.sh` fetches them at the commits pinned in
`port/sources.txt` (the same as the port's own submodules).

- `third_party/CBFD-Recompiled`: the PC port, pinned. The app uses its tools
  as pinned there:
  - `tools/N64Recomp`: the recompiler. Runs on a desktop (Linux or macOS) to
    turn the ROM into C. Never built for iOS.
  - `tools/N64ModernRuntime`: ultramodern + librecomp, built into the app with
    CBFD-Recompiled's `recomp/n64modernruntime.patch`. Mods (LiveRecomp/sljit,
    and patching code at run time) stay off on iOS.
  - `tools/rt64`: the renderer, built with CBFD-Recompiled's `recomp/rt64.patch`
    (Conker's graphics microcode, widescreen), then `patches/rt64` for iOS.
- `third_party/SDL`: SDL 2.32.10, built statically for iOS. RT64 needs it, and
  the game uses it for its window, controllers, touch and audio.
- `third_party/freetype`: FreeType 2.13.3, for RmlUi's fonts (game build only).
- `patches/rt64/0001` (iOS build, Tier 2 argument buffers: the fix for
  SotE's black screen), `patches/plume/0001`-`0006` (iOS Metal fixes),
  `ios/host_tools/`, `ios/plume/`,
  `ios/compat/`: from the SotE port, unchanged. See each patch's header for
  what each does.
- `ios/app/`: the app. For now the same self-test as the SotE port:
  `memory_probe.cpp` repeats librecomp's rdram setup (reserve 4 GiB, commit
  512 MiB) and `plume_clear.cpp` presents a cleared Metal swap chain.

`CMakeLists.txt` applies the patches at configure time, in order: Conker's
first, then the iOS ones. If a submodule ends up half patched, reset it with
`git -C <submodule> checkout -- .` and configure again.

## The shell's self-test

Launch the app on a device. It shows two lines:

- `rdram: reserved 4096 MiB, committed 512 MiB: OK` means librecomp's memory
  layout works as is.
- `plume: Metal swap chain OK` means the renderer backend runs on iOS.

The screen turns green when both pass and amber when only rendering works.
Every step is logged to `conker-log.txt` (Files app > Conker).

## The game build

The game code is generated from the ROM, so it can't live in this repo. In a
player's copy, `build.yml`'s `rom` job (Linux) checks their ROM
(`tools/rom.py`: finds it in a .zip or .7z, converts .n64 and .v64 to .z64,
checks the SHA-1), applies `patches/cbfd-recomp`, then runs CBFD-Recompiled's
own steps: patch and build N64Recomp, then `recomp/recompile.py`, which writes
`RecompiledFuncs/`. It deletes the ROM and hands that code to the `app` job
(Mac) as a one-day artifact, which the `cleanup` job deletes. The app job
compiles it for iOS as `conker_rom` (`ios/game/`, with CBFD-Recompiled's
compiler flags) together with everything else.

To save Mac minutes, `parts.yml` (run by hand in the public template only)
publishes the `ios-parts` release: RT64's host tools and the results of
CMake's checks (`tools/configure-seed.py`), which take about 8 of a build's
Mac minutes with the Xcode generator. A build uses them when their name
(`tools/parts-key.sh`: a hash of the CMake files, patches, pinned sources,
Xcode and CMake) matches, and otherwise makes them itself.

To generate the code on a Mac instead: copy your ROM to
`third_party/CBFD-Recompiled/conker/baserom.us.z64`, build N64Recomp as
above and run `python3 recomp/recompile.py --bin <its build folder>`. Then
run `tools/configure.sh <that RecompiledFuncs folder> <bundle id>`.

## The game on iOS

The game build (0.2.0) is CBFD-Recompiled's own host program, unchanged but
for `patches/cbfd`, with its launcher and menus (RecompFrontend: recompui on
RmlUi, and recompinput). Nearly all of the port's settings live there, so it
comes along rather than being replaced.

- `ios/app/ConkerGame.mm` is `main()`: SDL owns iOS apps, so it starts SDL's
  UIKit app, which calls back on the main thread. It sends the game's output
  to `conker-log.txt`, points the game's data folder (`APP_FOLDER_PATH`) at
  Documents, finds the ROM there the first time (`rom_import.cpp`) and runs
  CBFD-Recompiled's `main` (renamed `conker_main` by `patches/cbfd/0001`).
- `patches/cbfd/0001` also gives RT64 SDL's Metal view on iOS, full screen at
  native resolution.
- `patches/rt64/0002` keeps RT64's own data (`rt64.json`, its log) in
  Library/Application Support: it wrote `~/.rt64`, and an iOS app's home is
  its container, where it may only write inside Documents, Library and tmp
  (0.2.0 crashed on that at start).
- `patches/recompfrontend/0001` drops the "open mods folder" command (no
  Finder on iOS); `ios/app/nfd_ios.cpp` answers every file dialog with
  "cancelled". CBFD-Recompiled's own RecompFrontend and RmlUi patches go on
  first.
- FreeType (`third_party/freetype`, 2.13.3) is built for RmlUi's fonts; RmlUi
  is built static.

Taps work as mouse clicks in RecompFrontend's menus (SDL's default).
`ConkerGame.mm` scales their positions from UIKit points to the swap chain's
pixels, which the menus are laid out in (0.2.1 missed every button on a 3x
screen). It also pauses GPU work while the app is in the background
(`patches/plume/0007`): iOS fails a backgrounded app's command buffers, and
0.2.2 crashed after switching apps.

### Playing (0.3.0)

- **The intro is skipped**: Start Game goes straight to the save menu, as
  CBFD-Recompiled's Skip Intro mod does it. Mods can't run on iOS, so this,
  and skipping cutscenes, are built in (`ios/app/conker_ios_game.cpp`, after
  ConkerBFDReloaded's own built-in versions, MIT), through three hooks that
  `patches/cbfd-recomp/0001` adds to CBFD-Recompiled's `conker.toml`. CI
  applies it before generating the game code.
- **A tap on the open screen skips the playing cutscene**, any cutscene, even
  the first time (not the game over, which the game ends itself on a press).
- **Touch controls** (`ios/app/touch_controls.mm`), carried over from
  the SotE port: a floating stick in the lower left; drag anywhere else to look;
  A, B and the C buttons on the right, Z under L, L and R at the top; START at
  the bottom (tap for Start, hold 0.45 s for the tray: GYRO off / while
  touching / always, SENS, OPACITY, D-PAD). They show while the game runs and
  hide in RecompFrontend's menus. Looking and the gyro are sent as the mouse,
  which CBFD-Recompiled's mouse camera and aiming use; the iOS build sets
  Mouse: Sensitivity to 100% by default (`patches/cbfd/0001`), and its
  controller input takes the touch controls for player 1.
- **Right stick** (0.3.1): a touch that starts between the left stick's area
  and the buttons is a floating right stick, shown under the thumb only; it
  turns the camera as long as it's pushed, faster the further, through the
  same mouse camera (Mouse: Sensitivity is set to 100% once for settings
  saved by an older build, which kept 0, the mouse off). **FPS** in the tray shows frames presented a second and
  the game's own (up to 30).
- **Graphics** (0.3.1): RecompFrontend's defaults (the full screen's
  resolution, the display's 120 Hz) made the game choppy on a phone. On iOS
  they're now 480p (Original 2x) at 60 frames a second
  (`patches/recompfrontend/0002`), and a settings file from an older build is
  moved to those once (`ConkerGame.mm`). Settings > Graphics can raise them.
  The touch controls hide only for RecompFrontend's menus, which capture the
  mouse, not for the game's own overlays (the aiming reticle, notices).
- **60 or 120 FPS** (0.3.3): hold the tray's FPS for 0.45 s (a ring) to switch
  between 60 and 120 frames a second, with a note and a haptic; a tap still
  shows or hides the readout, and the button says which ("FPS 60"). 60 is the
  default, and the choice is remembered. It sets Settings > Graphics >
  Framerate to Manual at that rate (applied again at each launch) and asks the
  screen for it (`Info.plist`'s `CADisableMinimumFrameDurationOnPhone` lets an
  iPhone go above 60). The game keeps its own pace (up to 30 a second, the
  readout's "Game"): RT64 makes the frames in between, moving Conker, his
  shadow and the camera between the game's frames, so 120 is smoother, not
  faster. A screen without ProMotion, or Low Power Mode, stays at 60. 0.3.0's
  choppy 120 was most likely RT64 aiming at 120 while iOS held the screen at 60 (that
  `Info.plist` key was missing), at the full screen's resolution. Every 5
  seconds of play, `conker-log.txt` gets a line with the frames presented a
  second, the time per frame and the game's own frames.
- A game controller works too.

## Next

1. A way into RecompFrontend's settings during play from the touch controls.
2. Conker-specific extras (cheats, photos).

## Building

Players build with `.github/workflows/build.yml` (see the top README).
Locally on a Mac with Xcode, from the repository's top folder:

```sh
tools/fetch-sources.sh app
tools/configure.sh /path/to/RecompiledFuncs io.github.you.conker
open build/ConkeriOS.xcodeproj   # pick your team under Signing, then run on a device
```

Without `CONKER_GENERATED_DIR` (`cmake -S port -B build -G Xcode
-DCMAKE_SYSTEM_NAME=iOS`) it builds the ROM-free self-test shell instead.

## Licence

GPL-3.0 (see `LICENSE`), because N64ModernRuntime is GPL-3.0. CBFD-Recompiled's
own code, N64Recomp, RT64 and plume are MIT; the texture-pack hashing that
CBFD-Recompiled adds to RT64 is GPL-2.0-or-later, which GPL-3.0 covers. Credit
for the PC port goes to Sean Ciaschi and CBFD-Recompiled's contributors, and to
the mkst/conker decompilation it is built on.

Conker's Bad Fur Day is © Rare Ltd. This project is not affiliated with or
endorsed by Rare, Microsoft or Nintendo.

[CBFD-Recompiled]: https://github.com/sciaschi/CBFD-Recompiled
[ConkerBFDReloaded]: https://github.com/DahSidiAbdallah/ConkerBFDReloaded
[N64Recomp]: https://github.com/N64Recomp/N64Recomp
[N64ModernRuntime]: https://github.com/N64Recomp/N64ModernRuntime
[RT64]: https://github.com/rt64/rt64
