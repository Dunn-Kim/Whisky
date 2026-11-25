//
//  LegacyBottleImport.swift
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

import AppKit
import Foundation
import os.log

/// Discovery of bottles created by the other Whisky apps, so this build can copy them.
///
/// Bottles made by the Rosetta (x86_64) builds hold an x86_64 prefix, which this arm64
/// runtime can't use in place, and the runtime would rewrite the other app's prefix.
/// So a bottle is never registered where it is: ``LegacyBottleImport`` finds it, and
/// the migration functions in `LegacyBottleMigration.swift` copy it into a new bottle.
/// Nothing here writes to a source container.
public enum LegacyBottleImport {
    private static let logger = Logger(
        subsystem: Bundle.whiskyBundleIdentifier,
        category: "LegacyBottleImport"
    )

    /// A Whisky app whose bottles can be copied.
    public struct SourceApp: Hashable, Sendable {
        /// The app's bundle identifier, which names its container and its running process.
        public let bundleIdentifier: String
        /// What the migration sheet calls the app.
        public let displayName: String
        /// The app's container directory.
        public let container: URL

        public init(bundleIdentifier: String, displayName: String, container: URL? = nil) {
            self.bundleIdentifier = bundleIdentifier
            self.displayName = displayName
            self.container = container ?? BottleData.container(for: bundleIdentifier)
        }

        /// The app's Wine folder, ending in a separator: every Wine process it starts runs from there.
        var wineRoot: String {
            WhiskyWineInstaller.applicationFolder.deletingLastPathComponent()
                .appending(path: bundleIdentifier).appending(path: "Libraries").appending(path: "Wine")
                .path(percentEncoded: false) + "/"
        }
    }

    /// The apps bottles are copied from, the Rosetta build of this fork first.
    public static let sourceApps = [
        SourceApp(bundleIdentifier: "com.franke.Whisky", displayName: "Whisky (Rosetta build)"),
        SourceApp(bundleIdentifier: "com.isaacmarovitz.Whisky", displayName: "Whisky (original)")
    ]

    /// Minimal decode of a source app's bottle registry. Same plist shape as
    /// ``BottleData`` — we only need the registered paths.
    private struct LegacyRegistry: Decodable {
        var paths: [URL]
    }

    /// Whether any source app's container exists at all. Used to decide whether the
    /// migration option is worth offering in the UI.
    public static func containerExists(apps: [SourceApp] = sourceApps) -> Bool {
        apps.contains { FileManager.default.fileExists(atPath: $0.container.path(percentEncoded: false)) }
    }

    /// Whether `app`, or a Wine process it started, is running. Its files, above all its
    /// registry, aren't consistent while its wineserver writes them, so its bottles aren't
    /// copied until both have quit. Wine processes outlive the app when its kill-on-quit is off.
    public static func isRunning(_ app: SourceApp) -> Bool {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty else {
            return true
        }
        // Unknown counts as running: copying a bottle mid-write is worse than asking again.
        return WineProcessScanner.runningPIDs(under: app.wineRoot, includingServer: true).map { !$0.isEmpty } ?? true
    }

    /// An importable bottle of a source app, with the display name read from its settings.
    public struct DiscoveredBottle: Identifiable, Hashable, Sendable {
        /// The bottle's directory URL (also its identity).
        public let url: URL
        /// The bottle's display name, read from its settings (falls back to the directory name).
        public let name: String
        /// The app the bottle came from.
        public let app: SourceApp
        public var id: URL {
            url
        }
    }

    /// The bottles of `apps` that are valid (contain a `Metadata.plist`) and that no bottle in
    /// `existingPaths` records as its migration source, `apps` in order and each app's bottles
    /// sorted by directory name.
    ///
    /// Per app: its `BottleVM.plist` registry (which also covers bottles at custom paths
    /// outside the default Bottles directory), then a scan of its `Bottles` directory.
    /// Settings are read **non-destructively** (see ``readOnlySettings(at:)``).
    ///
    /// - Parameters:
    ///   - apps: the source apps (injectable for testing).
    ///   - existingPaths: bottle paths registered in this app; their `migratedFrom` marks
    ///     the sources already copied.
    public static func importableBottles(
        apps: [SourceApp] = sourceApps,
        existingPaths: [URL]
    ) -> [DiscoveredBottle] {
        let migrated = Set(
            existingPaths.compactMap { readOnlySettings(at: $0)?.migratedFrom }.map(BottleData.comparablePath)
        )
        var seen = Set<String>()
        var result: [DiscoveredBottle] = []
        for app in apps {
            let found = bottleURLs(in: app.container)
                .filter {
                    let path = BottleData.comparablePath($0)
                    return !migrated.contains(path) && seen.insert(path).inserted
                }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            result += found.map { url in
                DiscoveredBottle(url: url, name: readOnlySettings(at: url)?.name ?? url.lastPathComponent, app: app)
            }
        }
        logger.info("Discovered \(result.count) importable bottle(s)")
        return result
    }

    /// Whether `url` is a bottle of one of `apps`: inside its container, or listed in
    /// its bottle registry from a custom location. Such a bottle is copied with the
    /// migration functions, never registered where it is.
    public static func isSourceAppBottle(_ url: URL, apps: [SourceApp] = sourceApps) -> Bool {
        let path = BottleData.comparablePath
        let target = path(url)
        return apps.contains { app in
            target.hasPrefix(path(app.container) + "/") || bottleURLs(in: app.container).map(path).contains(target)
        }
    }

    private static func bottleURLs(in container: URL) -> [URL] {
        var candidates: [URL] = []

        // 1. The registry plist lists every bottle the app knew about, including
        //    bottles stored at custom paths outside the Bottles directory.
        if let data = try? Data(contentsOf: BottleData.entriesFile(in: container)),
           let registry = try? PropertyListDecoder().decode(LegacyRegistry.self, from: data) {
            candidates.append(contentsOf: registry.paths)
        }

        // 2. Scan the default Bottles directory in case the registry is missing or stale.
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: BottleData.bottlesDir(in: container),
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            candidates.append(contentsOf: entries)
        }

        var seen = Set<String>()
        return candidates.map(\.standardizedFileURL).filter {
            seen.insert(BottleData.comparablePath($0)).inserted && isBottle(at: $0)
        }
    }

    /// Reads a bottle's settings from its `Metadata.plist` **without writing anything**.
    ///
    /// This decodes `BottleSettings` directly via `PropertyListDecoder` (whose `init(from:)` is
    /// pure). It deliberately does **not** use `BottleSettings.decode(from:)` or construct a
    /// `Bottle`: both of those rewrite the metadata file when the bottle's file/wine version
    /// differs from the current app's defaults, and that would silently mutate the user's
    /// original bottles just by opening the migration sheet. Returns `nil` if the metadata
    /// is missing or undecodable.
    static func readOnlySettings(at bottleURL: URL) -> BottleSettings? {
        let metadata = bottleURL.appending(path: "Metadata").appendingPathExtension("plist")
        guard let data = try? Data(contentsOf: metadata) else { return nil }
        return try? PropertyListDecoder().decode(BottleSettings.self, from: data)
    }

    /// A directory is treated as a bottle when it contains a `Metadata.plist`, the marker
    /// ``Bottle`` and ``BottleData`` use to recognise a real bottle on disk.
    private static func isBottle(at url: URL) -> Bool {
        let metadata = url.appending(path: "Metadata").appendingPathExtension("plist")
        return FileManager.default.fileExists(atPath: metadata.path(percentEncoded: false))
    }
}
