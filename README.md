<div align="center">

# Whisky YAAGL Fork

Whisky for macOS, adjusted for HK4e / Genshin workflows.

![](https://img.shields.io/github/actions/workflow/status/git8e/whisky-yaagl/build.yml?style=for-the-badge)

</div>

## What This App Is

This project is a user-focused fork of [Whisky](https://github.com/Whisky-App/Whisky) for people who want to run HK4e / Genshin-style setups on macOS with less manual tweaking.

Compared with upstream Whisky, this fork mainly adds:

- More Wine runtimes you can choose from when creating a bottle.
- HK4e-oriented options such as SteamPatch, HDR, Retina mode, custom resolution, and a stored game executable.
- Better launch feedback, log access, and one-click tools such as Task Manager.
- A simpler data layout under `~/Library/Application Support/Whisky/`.

This is not an official Whisky build.

## System Requirements

- Apple Silicon Mac
- macOS 14 or later

## Download

You do not need Xcode.

1. Open the repository's `Actions` page.
2. Open the latest successful `Build (macOS)` run.
3. Download the `Whisky.app` artifact.
4. Unzip and remove quarantine:

```bash
unzip -q Whisky.app.zip
xattr -dr com.apple.quarantine "Whisky.app"
open "Whisky.app"
```

## First Launch

On first launch, the app guides you through runtime setup.

- `Wine 11.0 DXMT (signed)` is the recommended default.
- Other supported runtimes are also available in the setup screen.
- Downloads are cached, so each runtime only needs to be installed once.

## Creating A Bottle

When creating a bottle, you can choose:

- Wine runtime
- Windows version
- Retina mode
- SteamPatch
- HDR
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

## Certificate Import

This fork can patch the selected Wine runtime so new prefixes import the required root certificate during setup.

- The certificate payload is bundled in the app.
- This avoids network failures during bottle creation.

## What This Fork Does Not Do

- It does not modify `/etc/hosts`.
- It is not the official upstream Whisky build.
- It is not distributed as a Homebrew cask.

## Need Help?

If a game fails to start, the most useful things to check are:

1. The latest log in `~/Library/Logs/Whisky/`
2. Whether the game executable path still exists
3. Whether an external game drive is still mounted

## Credits

This project is built on top of Whisky and the work of the Wine, DXVK, MoltenVK, CrossOver, and Apple D3DMetal communities.

Please also support the upstream projects that make Whisky possible.
