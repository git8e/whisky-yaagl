<div align="center">

# Whisky (YAAGL Fork)

_Whisky with per-bottle Wine runtimes + one-time bottle tweaks_

![](https://img.shields.io/github/actions/workflow/status/git8e/whisky-yaagl/build.yml?style=for-the-badge)

</div>

## What This Is

This repository is a fork of [Whisky-App/Whisky](https://github.com/Whisky-App/Whisky) tailored for YAAGL-style workflows:

- Keep upstream Whisky UX and launch behavior.
- Add per-bottle Wine runtime selection (keep WhiskyWine + add 3 additional YAAGL Wine versions).
- Apply tweaks once at bottle creation time (or manually later), not on every game launch.

This is NOT an official Whisky repository.

<img width="650" alt="Config" src="https://github.com/Whisky-App/Whisky/assets/42140194/d0a405e8-76ee-48f0-92b5-165d184a576b">

Familiar UI that integrates seamlessly with macOS

<div align="right">
  <img width="650" alt="New Bottle" src="https://github.com/Whisky-App/Whisky/assets/42140194/ed1a0d69-d8fb-442b-9330-6816ba8981ba">

One-click bottle creation and management

</div>

<img width="650" alt="debug" src="https://user-images.githubusercontent.com/42140194/229176642-57b80801-d29b-4123-b1c2-f3b31408ffc6.png">

Debug and profile with ease

---

Whisky provides a clean and easy to use graphical wrapper for Wine built in native SwiftUI.

This fork adds:

- Multiple Wine runtimes per bottle.
- Bottle-level tools: Metal HUD, Retina mode, SteamPatch, custom resolution, and a pinned game entry (EXE).
- Maintenance actions: clean HK4e tweaks and reset prefix (manual).

Translated on [Crowdin](https://crowdin.com/project/whisky).

---

## System Requirements

- CPU: Apple Silicon (M-series chips)
- OS: macOS Sonoma 14.0 or later

This fork is tested on macOS 15.x.

## Download A Build (No Xcode Needed)

GitHub Actions builds a `Whisky.app.zip` artifact on every push.

- Go to: Actions -> "Build (macOS)" -> latest successful run -> Artifacts -> download `Whisky.app`
- Unzip and remove quarantine:

```bash
unzip -q Whisky.app.zip
xattr -dr com.apple.quarantine "Whisky.app"
open "Whisky.app"
```

## Key Features In This Fork

### Per-Bottle Wine Runtime Selection

During bottle creation you can select:

- WhiskyWine (upstream default)
- Wine 11.0 DXMT (signed)
- Wine 10.18 DXMT Experimental
- Wine 9.9 DXMT

If the selected runtime is not installed, it will be downloaded once and cached.
You can also point to a local archive (`.tar.gz` / `.tar.xz`).

### Bottle HK4e Tools (Manual / One-Time)

In Bottle -> Config -> HK4e:

- Game executable picker (stores the path and adds a Pin)
- SteamPatch: Apply / Remove (copies `steam.exe` + `lsteamclient.dll` into the prefix)
- Custom resolution: Apply / Revert (writes registry keys)
- Clean HK4e Tweaks (SteamPatch remove + resolution revert)
- Reset Prefix (delete prefix contents and recreate a fresh one; keeps Metadata and Program Settings)

Important: this fork does NOT patch/revert on every launch.

### SteamPatch Runtime Assets

SteamPatch needs the Proton extras files. Provide them via:

- Environment variable: `HK4E_RUNTIME_ROOT=/path/to/yaaglwdos`

Expected layout (either):

- `HK4E_RUNTIME_ROOT/sidecar/protonextras/steam64.exe` etc
- `HK4E_RUNTIME_ROOT/protonextras/steam64.exe` etc

## Security / Networking

This fork does not modify `/etc/hosts`.

## Homebrew

Upstream Whisky is available via Homebrew: `brew install --cask whisky`.
This fork is not published as a cask.

## My game isn't working!

Some games need special steps to get working. Check out the [wiki](https://github.com/IsaacMarovitz/Whisky/wiki/Game-Support).

This fork changes Wine runtime selection and adds a few bottle tools; the rest of the behavior is upstream Whisky.

---

## Credits & Acknowledgments

Whisky is possible thanks to the magic of several projects:

- [msync](https://github.com/marzent/wine-msync) by marzent
- [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) by Gcenx and doitsujin
- [MoltenVK](https://github.com/KhronosGroup/MoltenVK) by KhronosGroup
- [Sparkle](https://github.com/sparkle-project/Sparkle) by sparkle-project
- [SemanticVersion](https://github.com/SwiftPackageIndex/SemanticVersion) by SwiftPackageIndex
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) by Apple
- [SwiftTextTable](https://github.com/scottrhoyt/SwiftyTextTable) by scottrhoyt
- [CrossOver 22.1.1](https://www.codeweavers.com/crossover) by CodeWeavers and WineHQ
- D3DMetal by Apple

Special thanks to Gcenx, ohaiibuzzle, and Nat Brown for their support and contributions!

---

<table>
  <tr>
    <td>
        <picture>
          <source media="(prefers-color-scheme: dark)" srcset="./images/cw-dark.png">
          <img src="./images/cw-light.png" width="500">
        </picture>
    </td>
    <td>
        Whisky doesn't exist without CrossOver. Support the work of CodeWeavers using our <a href="https://www.codeweavers.com/store?ad=1010">affiliate link</a>.
    </td>
  </tr>
</table>
