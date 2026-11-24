# Runtime dependencies

WhiskyNative's app code is built from this repo. The **Wine runtime** is third-party software that
is installed separately. This file lists what the app bundles and where the runtime comes from.

## The Wine runtime

This build runs an arm64 Wine runtime with the FEX x86 emulator. No runtime is published, so
nothing is downloaded: install a local one with `scripts/install-arm64-runtime.sh <runtime folder>
<version>`. The runtime brings its own graphics layers (DXMT, WineD3D and others) and picks one per
executable from the rules in `WINE_COMPATDB`. The app copies no DLLs into bottles or into the runtime,
and it carries no DXVK, D3DMetal or Game Porting Toolkit payload.

The loader of the runtime must carry Apple's cross-architecture entitlement, or it cannot start x86
programs.

## Bundled in the app

These ship **inside the app bundle** (`WhiskyNative.app/Contents/Resources/`), committed to this repo under
[`Libraries/`](../Libraries) and copied in by the app target's "Embed WhiskyCmd" build phase. They are
**not** part of the Wine runtime.

| Component | Pinned version | Upstream source | Notes |
|-----------|----------------|-----------------|-------|
| **winetricks** | `20260125` | [Winetricks/winetricks](https://github.com/Winetricks/winetricks/releases/tag/20260125) | Self-contained POSIX shell script (LGPL-2.1+). Drives dependency installs (VC++, .NET, DirectX, fonts) and verb queries. Invoked as `bash winetricks <verb>` with the bundled `cabextract` and the runtime's `Wine/bin` on `PATH`. Bump by re-fetching `src/winetricks` at a newer release tag and regenerating `verbs.txt`. |
| **verbs.txt** | generated from winetricks `20260125` | produced by `winetricks list-all` | Verb catalog shown in the Winetricks browser. Regenerate whenever winetricks is bumped: `sh Libraries/winetricks list-all` (drop the leading platform-warning line so the file starts at the first `=====` category header). |
| **cabextract** | prebuilt arm64 binary | [cabextract.org.uk](https://www.cabextract.org.uk/) | Extracts Microsoft `.cab` archives; a hard dependency of many winetricks verbs. Committed as a code-signed-on-copy Mach-O executable. |

## Tracking cadence

- **winetricks:** releases roughly monthly; tracked manually. Bump when a needed verb's download URL
  breaks or a new component is required.
- **Security:** a critical Wine CVE should trigger a runtime rebuild and an app release.
  See `SECURITY.md`.

## Why we consume rather than build

Building and maintaining the macOS Wine runtime is the single most specialized, fragile job in this
ecosystem — it is effectively Gcenx's entire role and CodeWeavers' paid team's. On a deliberately
solo-maintained project (see [`GOVERNANCE.md`](GOVERNANCE.md)), taking that on would
*deepen* the bus-factor risk it was meant to reduce. So we consume upstream binaries and invest instead
in **discipline**: pinned versions, automated staleness detection, and a documented, reproducible assembly.
