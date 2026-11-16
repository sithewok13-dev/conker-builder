# Conker's Bad Fur Day for iPhone: build your own

Turn **your own** Conker's Bad Fur Day cartridge's ROM into an iPhone app, all from your phone. GitHub builds it
for free.

It's **Conker's Bad Fur Day on iPhone**, running natively: the N64 game's code recompiled into an iPhone app, not
an emulator. With touch controls, 60 or 120 frames a second and controller support.

## What you need

- A free [GitHub account](https://github.com/signup).
- **Your Conker's Bad Fur Day ROM, the US (NTSC) version**, dumped from your own cartridge: a .z64, .n64 or .v64
  file, or a .zip or .7z with it inside. The build checks it's the right one and says so in plain words if
  not. The European (PAL) version doesn't work.
- A way to install apps from outside the App Store (see [Installing](#installing)).
- An iPhone or iPad with iOS 16 or newer, and about 100 MB free.

## Make it

1. **Share your ROM.** Put the file in Google Drive (or Dropbox). In Drive: tap **⋮ > Share**, set
   **General access** to **Anyone with the link**, then **Copy link**.
2. **Make your copy of this page.** Tap the green **Use this template** button at the top, then **Create a new
   repository**. Any name, choose **Private** (your ROM goes in it), **Create repository**.
   *Don't see the button? In Safari, tap **aA > Request Desktop Website**.*
3. **Build.** In your copy: **Actions** > **Build Conker for iPhone** > **Run workflow**. Paste your link in the
   first box and tap the green **Run workflow**. It takes about 15 minutes; you can close the page.
   A green tick means done. A red cross: tap it to see what went wrong, in plain words.
   *Once it has your ROM, you can set your Drive link back to Restricted.*
4. **Get the app and your ROM.** On your copy's front page, scroll to **Releases**:
   - **Conker app**: tap **Conker.ipa** and install it (see below).
   - **Your ROM**: tap **conker.z64** to download it (your ROM, checked and in the right byte order).
5. **Play.** Open the app once: it says it needs your ROM, and its folder appears in the **Files** app. Move
   **conker.z64** from *Downloads* to **On My iPhone > Conker** and open the app again. It keeps its own copy, so
   you can delete conker.z64 from that folder afterwards.

## Installing

| | Cost | Computer? |
|---|---|---|
| **[SideStore](https://sidestore.io)** | Free (your Apple ID) | Once, to set it up. After that, open SideStore and tap **Refresh All** at least once a week: if you go past 7 days, SideStore and your apps expire and you'll need the computer again. |
| **[Signulous](https://www.signulous.com)** or **[UDID Registrations](https://www.udidregistrations.com)** | About $20 a year | No. Upload the IPA to their site and install from there. |
| **[Feather](https://github.com/khcrysalis/Feather)** | Your own [Apple Developer account](https://developer.apple.com/programs/) ($99 a year), or a signing service's certificate | No |

<details>
<summary>More options and details</summary>

- **[AltStore](https://altstore.io)** and **Sideloadly** are free too, but need a computer every week or every
  install.
- **[AppDB PLUS](https://appdb.to)** (about €12 a year) works like Feather: it needs a developer account or
  certificate.
- UDID Registrations also gives you certificate files you can use in Feather.
- Signing services are third parties, not part of this project. Apple sometimes revokes their certificates; the
  app then won't open until the service re-signs it.

</details>

## Updating

In your copy: **Actions** > **Build Conker for iPhone** > **Run workflow**, with the link box **empty**. Every build
takes the newest version of the port from this page, and the ROM it kept last time. Install the new Conker.ipa
the same way; your saves and settings stay.

<details>
<summary>Don't want your ROM kept in your copy?</summary>

Untick **Keep a copy of your ROM** when you run the build. It then deletes the copy it kept before, and every
build needs your link again. Put your own ROM on your phone in step 5 instead (a .z64, .n64, .v64 or a .zip with
it inside; not a .7z).

</details>

## Playing

- **Move:** a stick appears under your left thumb.
- **Look and aim:** drag anywhere else. A touch that starts between the stick's side and the buttons is a
  **right stick** under your thumb: it keeps turning the camera while you push it, faster the further.
- **A**, **B** and the four **C** buttons on the right; **Z** under **L**; **L** and **R** at the top.
- **START** at the bottom: tap for Start. Hold it (0.45 s) for the tray:
  - **GYRO**: aim by tilting the phone, off, while touching, or always. **SENS** sets how much.
  - **OPACITY** of the buttons, and **D-PAD** to show the D-pad.
  - **FPS**: tap to show the frame rate; hold for **60 or 120** frames a second (120 needs a ProMotion screen;
    the game itself still runs at its own pace, the frames in between are made smooth).
- **The intro is skipped**: Start Game goes straight to the save menu.
- **Tap the open screen to skip a cutscene**, any cutscene, even the first time.
- The game's own menus (settings, graphics, controls) work with taps.
- Controllers (Xbox, PlayStation, MFi) work too.

## Good to know

- **Keep your copy private** and don't share the app: it's made from your ROM, and your copy holds your ROM. The
  build stops if your copy is public.
- A build uses about 10 minutes of a Mac and 5 of Linux. GitHub counts a Mac minute in a private repo as 10 of
  a free account's 2,000 a month, so a build costs about **105 minutes**: around 15 to 20 builds a month. If
  GitHub's Macs have changed since this page's last update, a build takes about 8 Mac minutes longer (its log
  says "No ready-made parts match").
- The right ROM's SHA-1 (in the .z64 byte order) is `4cbadd3c4e0729dec46af64ad018050eada4f47a`. The build
  converts .n64 and .v64 to .z64 itself.
- Problems? The app writes `conker-log.txt` in *Files > On My iPhone > Conker*.
- **This is early: expect bugs.** Only lightly tested on an iPhone so far. I'm sorry for anything that goes wrong; if
  something does, a note with your phone's model and `conker-log.txt` helps.

## Credits

With warm thanks to everyone whose work this is:

- **Sean Ciaschi and the contributors of [CBFD-Recompiled](https://github.com/sciaschi/CBFD-Recompiled)**: the PC
  port this is built on, its launcher and settings, and the recompiler setup. The macOS port and ROM hack support
  by [nitrostemp](https://github.com/nitrostemp).
- **The [Conker's Bad Fur Day decompilation](https://github.com/mkst/conker) team (mkst and contributors)**, whose
  work CBFD-Recompiled is built on.
- **Wiseguy (Mr-Wiseguy) and contributors** for [N64Recomp](https://github.com/N64Recomp/N64Recomp),
  [N64ModernRuntime](https://github.com/N64Recomp/N64ModernRuntime) and
  [RecompFrontend](https://github.com/N64Recomp/RecompFrontend).
- **Darío and contributors** for the [RT64](https://github.com/rt64/rt64) renderer and
  [plume](https://github.com/renderbag/plume), which draws it with Metal.
- **[ConkerBFDReloaded](https://github.com/DahSidiAbdallah/ConkerBFDReloaded)** by dahmedvall95: the intro and
  cutscene skips follow its built-in versions.
- **[SDL](https://www.libsdl.org)** and **[FreeType](https://freetype.org)**.
- **[sithewok13-dev](https://github.com/sithewok13-dev)**: the iPhone version, touch controls and this template.

Licence: GPL-3.0 (see [LICENSE](LICENSE)), because N64ModernRuntime is GPL-3.0. CBFD-Recompiled's own code,
N64Recomp, RT64 and plume are MIT. How the port works: [port/README.md](port/README.md).

Conker's Bad Fur Day and Conker are trademarks of Rare Ltd. and Microsoft. This project is not affiliated with or
endorsed by Rare, Microsoft or Nintendo. It contains nothing of the game: you build from your own ROM.
