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

import Foundation
import os.log

/// Discovery of bottles created by the archived original Whisky app
/// (bundle identifier `com.isaacmarovitz.Whisky`) so this fork can import them.
///
/// The fork uses a different bundle identifier, so it doesn't see the original app's
/// bottles automatically. It is not sandboxed, though, so it can read the original
/// container directly. Discovered bottles are referenced **in place** (no copy) —
/// the same way custom-path bottles already work — so importing is non-destructive
/// and the original app keeps working if it's still installed.
public enum LegacyBottleImport {
    private static let logger = Logger(
        subsystem: Bundle.whiskyBundleIdentifier,
        category: "LegacyBottleImport"
    )

    /// Bundle identifier of the archived original Whisky app.
    public static let legacyBundleIdentifier = "com.isaacmarovitz.Whisky"

    /// `~/Library/Containers/com.isaacmarovitz.Whisky`.
    public static var legacyContainerDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library")
            .appending(path: "Containers")
            .appending(path: legacyBundleIdentifier)
    }

    /// URLs of original-app bottles that are valid (contain a `Metadata.plist`) and are
    /// not already registered in `existingPaths`.
    ///
    /// Sources, in order: the original app's `BottleVM.plist` registry (which also covers
    /// bottles stored at custom paths outside the default Bottles directory), then a scan
    /// of the default `Bottles` directory as a fallback. Results are de-duplicated and
    /// sorted by directory name.
    ///
    /// - Parameters:
    ///   - legacyContainer: the original app's container directory (injectable for testing).
    ///   - existingPaths: bottle paths already registered in this fork, to avoid duplicates.
    public static func importableBottleURLs(
        legacyContainer: URL = legacyContainerDirectory,
        existingPaths: [URL]
    ) -> [URL] {
        let existing = Set(existingPaths.map(\.standardizedFileURL))
        var candidates: [URL] = []

        // 1. The registry plist lists every bottle the original app knew about, including
        //    bottles stored at custom paths outside the Bottles directory.
        let registryURL = legacyContainer.appending(path: "BottleVM").appendingPathExtension("plist")
        if let data = try? Data(contentsOf: registryURL),
           let registry = try? PropertyListDecoder().decode(BottleDataMinimal.self, from: data) {
            candidates.append(contentsOf: registry.paths)
        }

        // 2. Scan the default Bottles directory in case the registry is missing or stale.
        let bottlesDir = legacyContainer.appending(path: "Bottles")
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: bottlesDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            candidates.append(contentsOf: entries)
        }

        var seen = Set<URL>()
        var result: [URL] = []
        for candidate in candidates {
            let standardized = candidate.standardizedFileURL
            guard !existing.contains(standardized), seen.insert(standardized).inserted else { continue }
            guard BottleData.hasMetadata(at: standardized) else { continue }
            result.append(standardized)
        }

        logger.info("Discovered \(result.count) importable legacy bottle(s)")
        return result.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// An importable original-app bottle, with the display name read from its settings.
    public struct DiscoveredBottle: Identifiable, Hashable, Sendable {
        /// The bottle's directory URL (also its identity).
        public let url: URL
        /// The bottle's display name, read from its settings (falls back to the directory name).
        public let name: String
        public var id: URL {
            url
        }
    }

    /// Like ``importableBottleURLs(legacyContainer:existingPaths:)`` but also reads each bottle's
    /// display name. Names are read **non-destructively** (see ``BottleData/metadataName(at:)``) — discovery
    /// must never mutate the original app's bottles.
    public static func importableBottles(
        legacyContainer: URL = legacyContainerDirectory,
        existingPaths: [URL]
    ) -> [DiscoveredBottle] {
        importableBottleURLs(legacyContainer: legacyContainer, existingPaths: existingPaths).map { url in
            DiscoveredBottle(url: url, name: BottleData.metadataName(at: url) ?? url.lastPathComponent)
        }
    }
}
