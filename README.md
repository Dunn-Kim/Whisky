<div align="center">

  # Whisky 🥃
  *Wine but a bit stronger*

  > **Active community fork.** The original [whisky-app/whisky](https://github.com/whisky-app/whisky)
  > was archived on April 9, 2025 with a final maintenance notice. This fork, maintained by
  > [@frankea](https://github.com/frankea), continues development — addressing the backlog of
  > upstream issues and adding new functionality. Not affiliated with the original project or
  > getwhisky.app.

  > **This repository is a fork of that fork.** [Dunn-Kim/Whisky](https://github.com/Dunn-Kim/Whisky)
  > follows [frankea/Whisky](https://github.com/frankea/Whisky) and carries a few changes of its own,
  > listed under [Fork changes](CHANGELOG.md#fork-changes). Everything else here, this README
  > included, is upstream's. Builds from this fork don't check for updates, ship without
  > upstream's telemetry token and install this fork's own Wine runtime. If something breaks, check that it also happens on upstream's build
  > before reporting it there. Not affiliated with frankea/Whisky, the original project or
  > getwhisky.app.

  ![](https://img.shields.io/github/actions/workflow/status/frankea/Whisky/CI.yml?style=for-the-badge&label=CI)
  [![](https://img.shields.io/codecov/c/github/frankea/Whisky?style=for-the-badge&logo=codecov&label=Coverage&flag=whiskykit)](https://codecov.io/gh/frankea/Whisky)
  [![](https://img.shields.io/github/downloads/frankea/Whisky/total?style=for-the-badge&logo=github&label=Downloads)](https://github.com/frankea/Whisky/releases)
  [![](https://img.shields.io/github/downloads/frankea/Whisky/latest/total?style=for-the-badge&label=Latest)](https://github.com/frankea/Whisky/releases/latest)
  [![](https://img.shields.io/github/issues/frankea/Whisky?style=for-the-badge)](https://github.com/frankea/Whisky/issues)
  [![Documentation](https://img.shields.io/badge/Documentation-DocC-blue?style=for-the-badge)](https://frankea.github.io/Whisky/documentation/whiskykit/)
</div>

## Overview

Whisky provides a clean and easy-to-use graphical wrapper for Wine built in native SwiftUI. You can make and manage bottles, install and run Windows apps and games, and unlock the full potential of your Mac with no technical knowledge required.

<img width="650" alt="Whisky in action" src="./images/demo.gif">

<img width="650" alt="Config" src="./images/config-screenshot.png">

*Familiar UI that integrates seamlessly with macOS*

<div align="right">
  <img width="650" alt="New Bottle" src="./images/new-bottle-screenshot.png">

  *One-click bottle creation and management*
</div>

<img width="650" alt="debug" src="./images/debug-screenshot.png">

*Debug and profile with ease*

---

## arm64-native branch (experimental)

This branch builds **WhiskyNative**. It runs Windows programs on an arm64 Wine runtime and the FEX x86 emulator, with no Rosetta 2. Apple ends Rosetta 2 for most apps in macOS 28, and the Rosetta build of Whisky stops working then.

- **Installs next to Whisky.** WhiskyNative has its own bundle ID (`io.github.dunn-kim.WhiskyNative`), its own data, the `whisky-native://` URL scheme and the `whisky-native` command line tool. It shares nothing with the Rosetta build.
- **Build and install.** No release and no arm64 runtime are published yet, so you build the app and install a runtime yourself. See the steps below.
- **Move your bottles.** **File → Copy Bottles from Another Whisky…** copies a bottle from the Rosetta build of Whisky, or from the original Whisky, into a new arm64 bottle. It copies the program files, program settings, user registry keys and fonts. It does not copy Windows dependencies; most programs need none on this engine. It never writes to the source bottle, and it refuses to run while the source app is open.
- **What is gone.** Rosetta 2, GPTK/D3DMetal and DXVK. Whisky no longer copies DLLs into bottles. The graphics backends are Recommended, DXMT and WineD3D. Chromium front ends run on WineD3D.
- **Visual C++ runtime.** Microsoft's x64 VC++ and UCRT DLLs break the runtime's own arm64 processes. Whisky keeps them out of `system32` and `syswow64` and moves them into the bottle's `VC Runtime` folder before each start. Only Unity games use the Microsoft runtime, and they get it per game.
- **Known limits.** No runtime is published. The runtime's loader must be signed with Apple's cross-architecture entitlement, or x86 programs do not start. A Unity game has been tested end to end; the branch is experimental and many programs are untested.

### Build and run

1. Clone the branch. A blobless clone is much smaller; [CONTRIBUTING.md](CONTRIBUTING.md#cloning) explains why:

   ```sh
   git clone --filter=blob:none -b arm64-native https://github.com/Dunn-Kim/Whisky.git
   ```

2. Open `Whisky.xcodeproj` in Xcode 16 or later on an Apple Silicon Mac, then build and run. The project signs ad hoc by default (`Signing.xcconfig`), so it needs no Apple developer account. To sign with your own team, create `Signing.local.xcconfig` next to it (git ignores it) with `DEVELOPMENT_TEAM = <your team ID>`, `CODE_SIGN_IDENTITY = Apple Development` and `ENABLE_HARDENED_RUNTIME = YES`. Ad hoc builds leave the hardened runtime off: its library validation refuses the ad hoc Sparkle framework.
3. Quit WhiskyNative, then install a runtime: `scripts/install-arm64-runtime.sh <runtime folder> <version>`. For example, use the `wine` folder of a Mach9 v0.4.0 release (Zlib licence): `scripts/install-arm64-runtime.sh ~/Downloads/mach9/wine 0.4.0`. Its loader is already signed with the cross-architecture entitlement.
4. Open the app again. Copy your bottles with the migration sheet, or create new ones.

## Key Features

- **arm64 Wine engine** - An arm64 Wine runtime with the FEX x86 emulator, installed with `scripts/install-arm64-runtime.sh`
- **DXMT & WineD3D Graphics** - DirectX 11 through native Metal translation (DXMT) out of the box, with WineD3D where Chromium needs it
- **Launcher Compatibility** - Built-in support for Steam, Epic, EA App, Rockstar, Battle.net, and more
- **Controller Support** - SDL environment variable controls for gamepad detection and mapping issues
- **Stability Diagnostics** - One-click diagnostic reports for troubleshooting crashes and freezes
- **Native SwiftUI** - Beautiful, familiar macOS interface

## System Requirements

- **CPU**: Apple Silicon (M-series chips). WhiskyNative is arm64 only and does not need Rosetta 2.
- **OS**: macOS Sequoia 15.0 or later

## Installation

There is no release of WhiskyNative yet, so build it from source. The Homebrew cask and the DMGs of [frankea/Whisky](https://github.com/frankea/Whisky) install the Rosetta build, **Whisky.app**, not this one. The steps are under [Build and run](#build-and-run). The app is `WhiskyNative.app`.

### Copying bottles from Whisky

WhiskyNative cannot use a bottle of the Rosetta build in place: an x86_64 prefix does not work with the arm64 runtime. Choose **File → Copy Bottles from Another Whisky…** to copy bottles into new arm64 bottles. It lists the bottles of the Rosetta build of Whisky (`~/Library/Containers/com.franke.Whisky/`) and of the original [whisky-app/whisky](https://github.com/whisky-app/whisky) (`~/Library/Containers/com.isaacmarovitz.Whisky/`). Quit the other app first.

The source bottle is only read. The old **Bottle → Export** and **File → Import Bottle** route still works if you would rather move a bottle by hand or to another Mac.

## Uninstalling

Dragging **WhiskyNative.app** to the Trash removes the app but leaves the Wine runtime, your bottles, and app data behind. Reinstalling does not lose your bottles.

> ⚠️ **Back up your bottles first if you want to keep them.** Removing the container below deletes every bottle stored in its default location. Bottles you created in a custom folder live wherever you put them. Check **Bottle → Reveal in Finder** before deleting anything.

To remove WhiskyNative **completely**, delete the app and then these paths (all under `~/Library`):

```sh
# 1. The app itself
rm -rf "/Applications/WhiskyNative.app"

# 2. The command line tool link, if you installed it
sudo rm -f /usr/local/bin/whisky-native

# 3. Bottles + bottle list (default bottle location is inside this container)
rm -rf ~/Library/Containers/io.github.dunn-kim.WhiskyNative
rm -rf ~/Library/Containers/io.github.dunn-kim.WhiskyNative.WhiskyThumbnail

# 4. The Wine runtime, the FEX code cache and other app support
rm -rf ~/Library/Application\ Support/io.github.dunn-kim.WhiskyNative

# 5. Caches, logs, preferences, and saved state
rm -rf ~/Library/Caches/io.github.dunn-kim.WhiskyNative
rm -rf ~/Library/Logs/io.github.dunn-kim.WhiskyNative
rm -rf ~/Library/HTTPStorages/io.github.dunn-kim.WhiskyNative
rm -f  ~/Library/Preferences/io.github.dunn-kim.WhiskyNative.plist
```

If you also created bottles in a **custom location**, delete those folders too. The Rosetta build of Whisky keeps its own data under `com.franke.Whisky`, and none of the steps above touch it.

## Telemetry (opt-in)

Whisky sends **no data by default**. During first-run setup you can opt in to
anonymous usage telemetry — a checkbox that is **off** unless you tick it, and a
toggle you can change anytime in **Settings → Privacy**.

When (and only when) enabled, Whisky sends five events covering the first-run
funnel, so the maintainer can see where new installs fail:

| Event | Properties |
| --- | --- |
| `runtime_install_started` | — |
| `runtime_install_succeeded` | — |
| `runtime_install_failed` | `reason`: one of `download_failed`, `verify_failed`, `tarball_missing`, `extract_failed`, `runtime_incomplete` |
| `first_bottle_created` | — |
| `first_program_launch_attempted` | — |

`runtime_install_started` is sent once per setup attempt; the `_succeeded` /
`_failed` events are sent per install attempt (so retries are counted). The two
`first_…` events are sent at most once per install.

No personal data, file names, paths, raw error text, or identifiers tied to you
are ever sent. Events carry a random per-install anonymous ID (reset if you opt
out). Every event Whisky can send is the list above, and all of it is declared in
one file, [`Whisky/Utils/Telemetry.swift`](Whisky/Utils/Telemetry.swift), with
every automatic-capture feature of the analytics SDK disabled and no person
profile ever created (`identify()` is never called). Each event also carries the
SDK's standard context — app and macOS version, hardware model, locale, and more;
see [SECURITY.md](SECURITY.md) for the full list. Like any HTTPS request,
PostHog's ingestion sees the connecting IP (GeoIP enrichment is disabled); none
of this is tied to your identity.

## Translations

Whisky is translated into 22 languages, and translations are managed on Crowdin.
To help translate, or to fix a translation you've spotted, join the
[Whisky Crowdin project](https://crowdin.com/project/frankea-whisky). If Crowdin
asks you to join, use the access request prompt on the project page. New and
updated translations sync into the app automatically, so please contribute
there rather than by opening a pull request; see
[CONTRIBUTING.md](CONTRIBUTING.md#localization) for how strings get from the
code to Crowdin and back.

## Documentation

- **[Support](docs/SUPPORT.md)** - Where to file bugs and what to expect from a single-maintainer fork
- **[Governance & continuity](docs/GOVERNANCE.md)** - Who maintains this and the honest bus-factor situation
- **[Runtime dependencies](docs/DEPENDENCIES.md)** - The Wine runtime this build needs and the tools the app bundles

WhiskyKit, the core framework powering Whisky, has comprehensive API documentation:

- **[WhiskyKit API Documentation](https://frankea.github.io/Whisky/documentation/whiskykit/)** - Full API reference with usage examples
- **[Getting Started Guide](https://frankea.github.io/Whisky/documentation/whiskykit/gettingstarted)** - Learn how to integrate WhiskyKit
- **[Architecture Overview](https://frankea.github.io/Whisky/documentation/whiskykit/architecture)** - Understand how WhiskyKit components work together

### Troubleshooting

- **[Launcher Troubleshooting](docs/LauncherTroubleshooting.md)** - Fix issues with Steam, Epic, Battle.net, etc.
- **[Steam Compatibility Guide](docs/SteamCompatibility.md)** - Detailed guide for Steam on WhiskyNative
- **[Stability Troubleshooting](docs/StabilityTroubleshooting.md)** - Diagnose crashes, freezes, reboots, and kernel panics
- **Controller Issues** - Enable "Controller Compatibility Mode" in Bottle Config → Controller & Input
- **[Game Configurations](https://github.com/frankea/Whisky/blob/main/WhiskyKit/Sources/WhiskyKit/GameDatabase/Resources/GameDB.json)** - 80+ curated per-game compatibility configs, also browsable in-app under Game Configurations

### Upstream issue audit

Per-issue accounting of how this fork addresses the open issues from the
archived upstream repo. Read [docs/AUDIT.md](docs/AUDIT.md) for the
methodology — including how to read the `addressed-direct` vs
`addressed-categorical` distinction and what `unverified` GameDB entries
actually mean.

### Test coverage

The Coverage badge above is scoped to the **`whiskykit` flag** — line
coverage of the framework that holds the bottle, Wine, GameDB, and
PE-parser logic, measured by `swift test --enable-code-coverage` per
[`.github/workflows/CI.yml`](.github/workflows/CI.yml). The blended
project-wide number on the [Codecov dashboard](https://codecov.io/gh/frankea/Whisky)
reads much lower because it averages in the SwiftUI app target, which
only receives best-effort UI-test coverage. Read the badge as
"WhiskyKit unit-test coverage," not full-app coverage.

WhiskyUITests gives behavioural coverage of the SwiftUI surface (toolbar,
create-bottle sheet, fixture-dependent flows). CI now runs them with
`-enableCodeCoverage YES` and uploads the resulting app-target coverage to
Codecov under a separate `whiskyapp` flag (best-effort — the upload never gates
CI). Because UI tests exercise far less of the app than the unit tests do of
WhiskyKit, expect the app-target number to read lower than the WhiskyKit badge
above.

---

## Credits & Acknowledgments

Whisky is possible thanks to the magic of several projects:

- [msync](https://github.com/marzent/wine-msync) by marzent
- [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) by Gcenx and doitsujin (the Rosetta build of Whisky)
- [DXMT](https://github.com/3Shain/dxmt) by 3Shain
- [MoltenVK](https://github.com/KhronosGroup/MoltenVK) by KhronosGroup
- [Sparkle](https://github.com/sparkle-project/Sparkle) by sparkle-project
- [SemanticVersion](https://github.com/SwiftPackageIndex/SemanticVersion) by SwiftPackageIndex
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) by Apple
- [CrossOver](https://www.codeweavers.com/crossover) by CodeWeavers and WineHQ
- D3DMetal by Apple (the Rosetta build of Whisky)

Special thanks to Gcenx, ohaiibuzzle, Nat Brown, and [Isaac Marovitz](https://github.com/IsaacMarovitz) (original author) for their support and contributions!

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
        Whisky doesn't exist without CrossOver. If you want a fully-supported commercial Wine experience on macOS, check out <a href="https://www.codeweavers.com/crossover">CrossOver</a> from CodeWeavers. (This fork has no affiliate arrangement and receives nothing from CrossOver sales.)
    </td>
  </tr>
</table>
