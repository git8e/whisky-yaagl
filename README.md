<div align="center">

# Whisky YAAGL Fork

Whisky for macOS, adjusted for HK4e (Genshin) and NAP (ZZZ) workflows.

![](https://img.shields.io/github/actions/workflow/status/git8e/whisky-yaagl/build.yml?style=for-the-badge)

</div>

[中文文档](README.zh-CN.md)

## What This App Is

This project is a user-focused fork of [Whisky](https://github.com/Whisky-App/Whisky) for people who want to run HK4e (Genshin) and NAP (ZZZ) setups on macOS with less manual tweaking.

Compared with upstream Whisky, this fork mainly adds:

- More Wine runtimes you can choose from when creating a bottle.
- Game-oriented options such as SteamPatch, HDR, Retina mode, custom resolution, and a stored game executable.
- Better launch feedback, log access, and one-click tools such as Task Manager.
- A simpler data layout under `~/Library/Application Support/Whisky/`.

This is not an official Whisky build.

## System Requirements

- Apple Silicon Mac
- macOS 14 or later

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
- Downloads are cached, so each runtime only needs to be installed once.

## Quick Start

1. Install the app from `Actions` artifacts (see `Download`).
2. Launch the app once and let it download a Wine runtime (recommended: `Wine 11.4 DXMT (signed)`).
3. Create a new bottle:
   - Pick `Game / Region`: `Genshin Impact (hk4eos)` / `原神 (hk4ecn)` / `ZZZ Global (napos)` / `ZZZ China (napcn)`
   - (Optional, HK4e) enable SteamPatch / HDR
   - (Optional) set proxy host + port
4. In the bottle's config, select your game executable:
   - HK4e: `GenshinImpact.exe` (hk4eos) / `YuanShen.exe` (hk4ecn)
   - ZZZ: `ZenlessZoneZero.exe`
5. Launch from the pinned program (or the program list).

## Creating A Bottle

When creating a bottle, you can choose:

- Wine runtime
- Windows version
- Retina mode
- Game / region preset (HK4e / NAP)
- (HK4e) SteamPatch
- (HK4e) HDR
- Proxy server host and port
- Optional custom resolution
- Optional game executable to pin on the bottle home screen

The bottle creation flow prepares the prefix, applies the selected one-time settings, and stores them for later reuse.

## HK4e / Genshin Features

In `Bottle -> Config -> HK4e`, you can manage:

- Game executable path
- Left Command as Ctrl
- SteamPatch
- HDR
- Custom resolution

This fork keeps HK4e settings persistent where possible, so the app does not need to rewrite the same registry values on every launch.

## NAP / ZZZ Features

In `Bottle -> Config -> NAP`, you can manage:

- Game executable path
- Fix WebView
- Custom resolution

## Useful Tools

Each bottle includes quick access to:

- Open `C:` drive
- Terminal
- Task Manager
- Control Panel
- Registry Editor
- Wine Configuration
- Open Logs / Open Latest Log

If a pinned game lives on an external drive and that drive is disconnected, the app now warns you that the target file cannot be found.

## Proxy Support

Bottle creation and bottle configuration both support proxy settings.

- The setting is stored per bottle.
- It is written into Wine Internet Settings.
- Host and port are configured separately.
- You can enable, disable, or change it later from the bottle config page.

## Compared With YAAGL

This fork borrows HK4e workflow ideas from YAAGL, but adapts them to Whisky's bottle-first model (multiple bottles, preconfigured setup) instead of a single-app, per-launch patch/revert flow.

- Bottle isolation: keep OS/CN and different game setups in separate bottles.
- Configure ahead of time: DXMT injection, SteamPatch, proxy, and HK4e settings are applied during bottle creation or when toggled in Config.
- Less launch-time work: most settings are persisted and only re-applied when missing.
- Shared-runtime aware: changes that touch Wine runtimes are treated as runtime-level and designed to be idempotent across bottles.
- Better troubleshooting UX: per-launch logs, one-click tools, and clearer “file not found” errors (e.g. external drives).
- Easier Wine switching: downloaded runtimes are cached, so switching versions does not require re-downloading.
- Native macOS app experience: GUI-first workflow with integrated tools and logs.
- Faster day-to-day flow: fewer external steps than YAAGL’s per-launch patch/revert approach.
- Fewer failure modes: less fragile launch-time patching, and clearer error surfaces when something does go wrong.
- Multi-game concurrency: multiple bottles can launch the same or different games at the same time.

## Storage Location

This fork stores data here:

- `~/Library/Application Support/Whisky/`
  - `Bottles/`
  - `Libraries/`
  - `Downloads/`
- `~/Library/Logs/Whisky/`

If older Whisky data exists, the app will try to migrate it on first launch.

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
