//
//  VCRuntimeIsolation.swift
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

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "VCRuntimeIsolation")

/// Keeps Microsoft's VC++ 2015-2022 runtime out of the runtime's system folders.
///
/// Wine's own helper programs (`start.exe`, `reg.exe`, `cmd.exe`, the services)
/// are native arm64 processes. When winetricks' `vcrun2019` or a game's
/// `vc_redist` puts Microsoft's x64 `ucrtbase.dll` and friends into `system32`,
/// every one of them dies loading it and nothing launches. So before Wine runs,
/// the native copies move into the bottle's store (`VC Runtime/<machine>`) and
/// the runtime's own builtins go back. Only Unity games get the Microsoft DLLs,
/// copied next to their executable (``placeForUnity(executable:store:)``).
public enum VCRuntimeIsolation {
    /// What winetricks' `vcrun2019` and `ucrtbase2019` override: VC++ 14 and the UCRT.
    static let isolatedNames = [
        "api-ms-win-crt-conio-l1-1-0", "api-ms-win-crt-heap-l1-1-0", "api-ms-win-crt-locale-l1-1-0",
        "api-ms-win-crt-math-l1-1-0", "api-ms-win-crt-private-l1-1-0", "api-ms-win-crt-runtime-l1-1-0",
        "api-ms-win-crt-stdio-l1-1-0", "api-ms-win-crt-time-l1-1-0",
        "atl140", "concrt140", "msvcp140", "msvcp140_1", "msvcp140_2", "msvcp140_atomic_wait",
        "msvcp140_codecvt_ids", "ucrtbase", "vcamp140", "vccorlib140", "vcomp140", "vcruntime140",
        "vcruntime140_1"
    ]

    /// What a Unity game gets next to it: the VC++ DLLs, not the UCRT, which
    /// stays the runtime's builtin.
    static let unityNames = isolatedNames.filter { $0 != "ucrtbase" && !$0.hasPrefix("api-ms-win-crt-") }

    /// A native file ``isolate(prefix:runtimeLibWine:)`` moved out of a system folder.
    public struct Moved: Equatable, Sendable {
        public let name: String
        /// The system folder it came from: `system32` or `syswow64`.
        public let folder: String
        /// `x64`, `x86`, `arm64` or `other`: the store folder it went to.
        public let machine: String
    }

    /// The bottle's store of native VC++ DLLs, one folder per machine.
    public static func store(prefix: URL) -> URL {
        prefix.appending(path: "VC Runtime")
    }

    /// Moves native copies of the VC++ and UCRT DLLs out of `system32` and
    /// `syswow64` into the store, and puts the runtime's builtin in their place.
    ///
    /// A file is left alone when it is Wine's own, or when the runtime has no
    /// builtin of that name to replace it with. Nothing is deleted except an
    /// older store copy of the same file.
    ///
    /// - Parameters:
    ///   - prefix: The Wine prefix root.
    ///   - runtimeLibWine: The runtime's `lib/wine` folder.
    /// - Returns: What was moved, in order.
    @discardableResult
    public static func isolate(prefix: URL, runtimeLibWine: URL) -> [Moved] {
        let fileManager = FileManager.default
        let windows = prefix.appending(path: "drive_c").appending(path: "windows")
        var moved: [Moved] = []
        for (folder, builtins) in [("system32", "aarch64-windows"), ("syswow64", "i386-windows")] {
            for name in isolatedNames {
                let file = windows.appending(path: folder).appending(path: name + ".dll")
                let builtin = runtimeLibWine.appending(path: builtins).appending(path: name + ".dll")
                guard VCRedistDetector.isNativePE(file), fileManager.fileExists(atPath: builtin.path) else {
                    continue
                }
                let machine = machine(of: file).map(machineName) ?? "other"
                let target = store(prefix: prefix).appending(path: machine)
                let stored = target.appending(path: name + ".dll")
                do {
                    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                    try? fileManager.removeItem(at: stored)
                    try fileManager.moveItem(at: file, to: stored)
                } catch {
                    logger.error("Could not move \(name, privacy: .public) from \(folder, privacy: .public): \(error)")
                    continue
                }
                do {
                    try fileManager.copyItem(at: builtin, to: file)
                } catch {
                    logger.error("Could not restore the builtin \(name, privacy: .public): \(error)")
                    try? fileManager.moveItem(at: stored, to: file)
                    continue
                }
                moved.append(Moved(name: name, folder: folder, machine: machine))
            }
        }
        return moved
    }

    /// For a Unity game, copies the store's VC++ DLLs for its architecture next
    /// to its executable, and names the ones that load natively there.
    ///
    /// A file already in the game's folder is never replaced.
    ///
    /// - Parameters:
    ///   - executable: The game's executable.
    ///   - store: The bottle's store (``store(prefix:)``).
    /// - Returns: The DLL names (without `.dll`) that are native PEs next to the
    ///   executable, which want `n,b`. Empty unless `UnityPlayer.dll` sits there.
    public static func placeForUnity(executable: URL, store: URL) -> [String] {
        let fileManager = FileManager.default
        let folder = executable.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: folder.appending(path: "UnityPlayer.dll").path),
              let machine = machine(of: executable).map(machineName), machine == "x64" || machine == "x86"
        else { return [] }
        for name in unityNames {
            let source = store.appending(path: machine).appending(path: name + ".dll")
            let target = folder.appending(path: name + ".dll")
            guard fileManager.fileExists(atPath: source.path), !fileManager.fileExists(atPath: target.path) else {
                continue
            }
            do {
                try fileManager.copyItem(at: source, to: target)
            } catch {
                logger.error("Could not place \(name, privacy: .public) for Unity: \(error)")
            }
        }
        return unityNames.filter { VCRedistDetector.isNativePE(folder.appending(path: $0 + ".dll")) }
    }

    /// The `DllOverrides` value names a launch should delete: set A names
    /// (`name` or `*name`) whose data asks for the native copy, except those
    /// the bottle's own settings set.
    ///
    /// - Parameters:
    ///   - values: The key's values as ``WineRegistryFile/rawValues(bottleURL:key:)`` gives them.
    ///   - userNames: The lowercased names the bottle settings set deliberately.
    static func staleOverrides(in values: [String: String], keeping userNames: Set<String>) -> [String] {
        values.compactMap { name, data in
            let bare = (name.hasPrefix("*") ? String(name.dropFirst()) : name).lowercased()
            guard isolatedNames.contains(bare), !userNames.contains(bare),
                  data.drop(while: { $0 == "\"" }).first?.lowercased() == "n"
            else { return nil }
            return name
        }.sorted()
    }

    /// The PE machine field of an image: `0x8664` x64, `0x14c` x86, `0xAA64` arm64.
    static func machine(of url: URL) -> UInt16? {
        (try? PEFile(url: url))?.coffFileHeader.machine
    }

    private static func machineName(_ machine: UInt16) -> String {
        switch machine {
        case 0x8664: "x64"
        case 0x14C: "x86"
        case 0xAA64: "arm64"
        default: "other"
        }
    }
}

extension Wine {
    /// The runtime's `lib/wine` folder, where its builtin DLLs are.
    static let runtimeLibWine = WhiskyWineInstaller.libraryFolder
        .appending(path: "Wine").appending(path: "lib").appending(path: "wine")

    /// Readies a bottle for a Wine process: the VC++ runtime out of the system
    /// folders, the user profile under the name this runtime uses, and FEX's
    /// cache folder in place. Call it before any Wine process starts in the bottle.
    public static func prepareBottleForWine(bottleURL: URL) {
        isolateVCRuntime(bottleURL: bottleURL)
        WineUserProfile.reconcile(bottleURL: bottleURL)
        ensureFEXCacheFolder()
    }

    /// Runs ``VCRuntimeIsolation/isolate(prefix:runtimeLibWine:)`` for a bottle.
    private static func isolateVCRuntime(bottleURL: URL) {
        let moved = VCRuntimeIsolation.isolate(prefix: bottleURL, runtimeLibWine: runtimeLibWine)
        if !moved.isEmpty {
            let names = moved.map { "\($0.folder)/\($0.name)" }.joined(separator: ", ")
            logger.info("Moved native VC++ files into the VC Runtime store: \(names, privacy: .public)")
        }
    }
}
