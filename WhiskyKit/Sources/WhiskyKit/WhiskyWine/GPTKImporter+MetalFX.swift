//
//  GPTKImporter+MetalFX.swift
//  WhiskyKit
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import os.log

/// MetalFX has exactly one entry point: the DLSS API. D3DMetal links MetalFX and
/// builds its scalers, but only for a game that calls `NVSDK_NGX_D3D12_*` in
/// `nvngx.dll`, which Apple implements as `nvngx-on-metalfx.dll`. With no such
/// DLL in the tree `D3DM_ENABLE_METALFX=1` has nothing to hook, which is why
/// MetalFX could not be enabled in any bottle.
///
/// Two things make this more than a file copy:
///
/// - The bridge is a hybrid PE and unixlib module. Its `DllMain` calls
///   `__wine_init_unix_call` before anything else and returns false when that
///   fails, so the PE on its own loads as a builtin and immediately dies with
///   `ERROR_DLL_INIT_FAILED`, which reads like a corrupt DLL and is not. It needs
///   a unix half beside it, exactly like the four D3D forwarders.
/// - Builtins are keyed by their PE export name, and this one exports as
///   `nvngx.dll` rather than the filename Apple ships it under.
///
/// `nvapi64.dll`, Apple's other NVIDIA bridge, deliberately stays
/// out: Chromium probes for an NVIDIA GPU, and handing it one makes it load
/// D3DMetal and take Steam's helper process down. Nothing probes for nvngx that
/// way, so the bridge itself is safe to deploy on its own.
///
/// Leaving it out is not free. A title built on NVIDIA Streamline asks NVAPI
/// about the GPU before it will consider DLSS at all, and Wine's `nvapi64`
/// exports nothing, so Streamline decides there is no NVIDIA driver and offers
/// no DLSS option. Those titles get the bridge and cannot reach it, with nothing
/// in any log to say why. A title calling NGX directly is unaffected.
///
/// Fixing that means a real `nvapi64` for the game but not for the launcher
/// helper, so a per-exe `AppDefaults` override rather than the environment every
/// child inherits. Left to a follow-up, which is why frankea/Whisky#198 stays
/// open.
extension GPTKBridge {
    /// Apple's MetalFX bridge. It ships as `nvngx-on-metalfx.dll` but has to be
    /// installed as `nvngx.dll`, because that is what its PE export directory says.
    static let metalFX = GPTKBridge(
        sourceName: "nvngx-on-metalfx.dll", installedName: "nvngx.dll", unixName: "nvngx.so"
    )
}

extension GPTKImporter {
    /// Puts the bridge in the tree under its export name with a unix half beside
    /// it. Does nothing when the payload is too old to carry one.
    ///
    /// Purely additive: Wine ships no `nvngx.dll`, so unlike the forwarders there
    /// is no builtin here to back up and nothing to restore on the way out.
    ///
    /// A destination already matching the store is left alone, so the launch-time
    /// ``ensureMetalFXBridgeInstalled()`` does not rewrite it every time.
    /// Anything else is replaced, which is not the rule
    /// ``removeMetalFXBridge(fromLibraryFolder:usingStore:)`` follows: deleting
    /// a file someone else put there cannot be undone, and overwriting one in a
    /// tree we manage is what repair means.
    static func installMetalFXBridge(intoLibraryFolder folder: URL, usingStore store: URL) throws {
        guard let source = source(of: .metalFX, inStore: store) else { return }
        let fileManager = FileManager.default
        let destination = installedPE(of: .metalFX, inLibraryFolder: folder)
        let link = unixLink(of: .metalFX, inLibraryFolder: folder)

        if !isInstalled(.metalFX, inLibraryFolder: folder, usingStore: store) {
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }

        try fileManager.createDirectory(
            at: link.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try linkUnixHalf(link)
        logger.info("Installed the MetalFX bridge as \(GPTKBridge.metalFX.installedName, privacy: .public)")
    }

    /// Takes the bridge back out, leaving anything this store did not install.
    ///
    /// The unix link goes only when it points where we pointed it; `removeItem`
    /// acts on the link itself, so a dangling one is cleared too.
    static func removeMetalFXBridge(fromLibraryFolder folder: URL, usingStore store: URL) {
        let fileManager = FileManager.default
        guard isInstalled(.metalFX, inLibraryFolder: folder, usingStore: store) else { return }
        try? fileManager.removeItem(at: installedPE(of: .metalFX, inLibraryFolder: folder))

        let link = unixLink(of: .metalFX, inLibraryFolder: folder)
        let target = try? fileManager.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false))
        if target == unixLinkDestination {
            try? fileManager.removeItem(at: link)
        }
    }

    // MARK: - Prefixes

    /// Takes a prefix's placeholder back out, which makes the bridge unreachable
    /// from that bottle without touching the shared tree.
    ///
    /// Removes any builtin-marked entry, not just a copy this app wrote:
    /// `wineboot` writes its own stub for every builtin it finds, so a prefix
    /// update after the bridge was installed recreates one, and leaving that in
    /// place would quietly defeat the opt-out. A *native* DLL is left alone,
    /// that is someone's own `nvngx`, not something we or Wine put there.
    static func clearMetalFXBridgePlaceholder(inBottle bottle: URL) {
        let placeholder = bottle.appending(path: "drive_c").appending(path: "windows")
            .appending(path: "system32").appending(path: GPTKBridge.metalFX.installedName)
        guard FileManager.default.fileExists(atPath: placeholder.path(percentEncoded: false)) else { return }
        // A throwing `isNativePE` compares unequal to `false` and so keeps the
        // file. Deliberate: a placeholder too short or unreadable to hold the
        // marker is not something anyone chose to put here, and only wineboot
        // and this app write to the name.
        guard (try? Wine.isNativePE(placeholder)) == false else { return }
        try? FileManager.default.removeItem(at: placeholder)
    }

    /// Installs the bridge into a tree that already holds the payload.
    ///
    /// An install set up before the bridge existed has the payload deployed and
    /// never deploys again, so it would stay without MetalFX until it happened
    /// to reimport. Idempotent and cheap enough to run at launch.
    ///
    /// Deliberately seeds no prefixes. The tree-side bridge is inert on its own,
    /// and which bottles can reach it is ``Wine/applyMetalFX(bottle:backend:)``'s
    /// decision at launch, from the per-bottle setting.
    public static func ensureMetalFXBridgeInstalled() {
        let folder = WhiskyWineInstaller.libraryFolder
        guard isDeployed(inLibraryFolder: folder) else { return }

        do {
            try installMetalFXBridge(intoLibraryFolder: folder, usingStore: storeFolder)
        } catch {
            logger.error("Installing the MetalFX bridge failed: \(error.localizedDescription)")
        }
    }
}
