<div align="center">

# Whisky YAAGL Fork

Whisky for macOS, adjusted for HK4e (Genshin), NAP (ZZZ), and HKRPG (Star Rail) workflows.

![](https://img.shields.io/github/actions/workflow/status/git8e/whisky-yaagl/build.yml?style=for-the-badge)

</div>

[中文文档](README.zh-CN.md)

## What This App Is

This project is a user-focused fork of [Whisky](https://github.com/Whisky-App/Whisky) for people who want to run HK4e (Genshin), NAP (ZZZ), and HKRPG (Star Rail) setups on macOS with less manual tweaking.

Compared with upstream Whisky, this fork mainly adds:

- More Wine runtimes you can choose from when creating a bottle.
- Game-oriented options such as SteamPatch, HDR, Retina mode, custom resolution, and a stored game executable.
- Better launch feedback, log access, and one-click tools such as Task Manager.
- A simpler data layout under `~/Library/Application Support/Whisky/`.
- Per-bottle Wine runtime isolation (runtime-level patches do not leak across bottles).
- Bottle duplication that prefers APFS clone (copy-on-write) for speed and disk savings.

This is not an official Whisky build.

## System Requirements

- Apple Silicon Mac
- macOS 14 or later

## Is it safe?

Use it at your own risk. Or enjoying it with a new f2p account.

## Download

1. Open the repository's `Actions` page.
2. Open the latest successful `Build (macOS)` run.
3. Scroll to `Artifacts` and download `Whisky.app.zip`.
4. Open `Finder` and unzip it (double-click).
5. Drag `Whisky.app` into `/Applications`.
6. Launch it from `Applications`.

If macOS blocks the app on first launch:

1. Open `System Settings` -> `Privacy & Security`.
2. Find the blocked app message and click `Open Anyway`.

## First Launch

On first launch, the app guides you through runtime setup.

- `Wine 11.4 DXMT (signed)` is the recommended default.
- Other supported runtimes are also available in the setup screen.
- Downloads are cached. Each bottle then gets its own isolated runtime based on the selected runtime.

## Quick Start

1. Install the app from `Actions` artifacts (see `Download`).
2. Launch the app once and let it download a Wine runtime (recommended: `Wine 11.4 DXMT (signed)`).
3. Create a new bottle:
   - Pick `Game / Region`: `Genshin Impact (hk4eos)` / `原神 (hk4ecn)` / `ZZZ Global (napos)` / `ZZZ China (napcn)` / `Star Rail (hkrpgos)` / `崩坏：星穹铁道 (hkrpgcn)`
   - (Optional, HK4e) enable SteamPatch / HDR
   - (Optional) enable `Launch Fix (test)`
   - (Optional) set proxy host + port
4. In the bottle's config, select your game executable:
   - HK4e: `GenshinImpact.exe` (hk4eos) / `YuanShen.exe` (hk4ecn)
   - ZZZ: `ZenlessZoneZero.exe`
   - Star Rail: `StarRail.exe`
5. Launch from the pinned program (or the program list).

## Creating A Bottle

When creating a bottle, you can choose:

- Wine runtime
- Windows version
- Retina mode
- Game / region preset (HK4e / NAP / HKRPG)
- (HK4e) SteamPatch
- (HK4e) HDR
- (Optional) `Launch Fix (test)`
- Proxy server host and port
- Optional custom resolution
- Optional game executable to pin on the bottle home screen

The bottle creation flow prepares the prefix, applies the selected one-time settings, and stores them for later reuse.

## HK4e / Genshin Features

In `Bottle -> Config -> HK4e`, you can manage:

- Game executable path
- Left Command as Ctrl
- Launch Fix (test)
- SteamPatch
- HDR
- Custom resolution

This fork keeps HK4e settings persistent where possible, so the app does not need to rewrite the same registry values on every launch.

## NAP / ZZZ Features

In `Bottle -> Config -> NAP`, you can manage:

- Game executable path
- Launch Fix (test)
- Fix WebView
- Custom resolution

## HKRPG / Star Rail Features

In `Bottle -> Config -> HKRPG`, you can manage:

- Game executable path
- Launch Fix (test)

HKRPG launch is wrapped with Jadeite inside the bottle prefix (downloaded and installed automatically when needed). WebView registry cleanup is applied automatically for HKRPG (no UI toggle).

## Compared With YAAGL

This fork borrows HK4e workflow ideas from YAAGL, but adapts them to Whisky's bottle-first model (multiple bottles, preconfigured setup) instead of a single-app, per-launch patch/revert flow.

- Bottle isolation: keep OS/CN and different game setups in separate bottles.
- Preconfigured workflow: most game options are applied when creating a bottle or toggled in Config (instead of per-launch patch/revert).
- Per-bottle runtime isolation: runtime-level changes stay inside each bottle’s isolated runtime.
- Better troubleshooting UX: per-launch logs and clearer errors (e.g. missing files on external drives).
- Multi-game concurrency: multiple bottles can launch the same or different games at the same time.

## Storage Location

This fork stores data here:

- `~/Library/Application Support/Whisky/`
  - `Bottles/`
  - `Libraries/`
  - `Downloads/`
- `~/Library/Logs/Whisky/`

If older Whisky data exists, the app will try to migrate it on first launch.

Note: per-bottle runtime isolation works best on APFS volumes (so the app can use clone/copy-on-write when duplicating bottles).

## Logs

Logs are stored in:

- `~/Library/Logs/Whisky/`

Recent versions of this fork try to keep one launch session in one log file, so startup troubleshooting is easier.

## Need Help?

If a game fails to start, the most useful things to check are:

1. The latest log in `~/Library/Logs/Whisky/`
2. Whether the game executable path still exists
3. Whether an external game drive is still mounted

## Credits

This project is built on top of Whisky and the work of the Wine, DXVK, MoltenVK, CrossOver, and Apple D3DMetal communities.

## Special Thanks

- [YAAGL](https://github.com/yaagl/yet-another-anime-game-launcher) for the HK4e-oriented workflow ideas and reference behavior.
- [Whisky](https://github.com/Whisky-App/Whisky) for the base app and the macOS Wine bottle experience.
- OpenCode (gpt-5.2) for porting work and documentation.

Please also support the upstream projects that make this fork possible.
