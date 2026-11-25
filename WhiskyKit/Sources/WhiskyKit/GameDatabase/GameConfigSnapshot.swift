//
//  GameConfigSnapshot.swift
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

/// A snapshot of bottle and program settings captured before applying a game configuration.
///
/// Used for the undo/revert flow: the snapshot stores serialized plist data for
/// ``BottleSettings``, enabling exact restoration, and the program environment
/// variables the apply replaced. Winetricks verbs are recorded for informational
/// display only (they are not reversible).
///
/// ## Storage
///
/// A single snapshot file (`GameConfigSnapshot.plist`) is stored in the bottle directory.
/// Each apply overwrites the previous snapshot, following the single-undo design.
///
/// ## Example
///
/// ```swift
/// let snapshot = GameConfigSnapshot(
///     bottleSettingsData: try PropertyListEncoder().encode(bottle.settings),
///     appliedEntryId: "elden-ring",
///     appliedVariantId: "recommended-apple-silicon",
///     timestamp: Date()
/// )
/// try GameConfigSnapshot.save(snapshot, to: bottleURL)
/// ```
public struct GameConfigSnapshot: Codable, Sendable, Equatable {
    /// Serialized ``BottleSettings`` plist data from before the apply.
    public var bottleSettingsData: Data?

    /// Map of program URL string to serialized program settings data.
    ///
    /// Each key is the string representation of the program's URL. Each value
    /// is the PropertyList-encoded settings data for that program. Earlier
    /// versions recorded it; a revert does not restore it, because it would
    /// overwrite program settings changed after the apply. See
    /// ``programEnvironments`` for what a revert puts back.
    public var programSettingsData: [String: Data]?

    /// The environment variables the apply wrote into each program, keyed by
    /// the string representation of the program's URL.
    ///
    /// A revert puts back only these variables, leaving the rest of the
    /// program's settings as they are.
    public var programEnvironments: [String: GameConfigProgramEnvironment]?

    /// The bottle settings the apply changed, with the values they had before it.
    ///
    /// A revert puts back only these, leaving the rest of the bottle's settings
    /// as they are. `nil` in a snapshot written before this was recorded; a
    /// revert then puts back the settings an apply can change from
    /// ``bottleSettingsData``.
    public var bottleChanges: GameConfigBottleChanges?

    /// Winetricks verbs installed during this apply (informational, non-reversible).
    ///
    /// These are recorded so the revert UI can note "Settings reverted;
    /// installed components remain."
    public var installedVerbs: [String]?

    /// The ID of the ``GameDBEntry`` that was applied.
    public var appliedEntryId: String

    /// The ID of the ``GameConfigVariant`` that was applied.
    public var appliedVariantId: String

    /// When the snapshot was created.
    public var timestamp: Date

    /// The filename used for snapshot storage within the bottle directory.
    private static let snapshotFileName = "GameConfigSnapshot.plist"

    /// Creates a new game configuration snapshot.
    ///
    /// - Parameters:
    ///   - bottleSettingsData: Serialized bottle settings from before apply.
    ///   - programSettingsData: Map of program URL to serialized settings.
    ///   - programEnvironments: Map of program URL to the environment variables the apply set.
    ///   - bottleChanges: The bottle settings the apply changed, with their earlier values.
    ///   - installedVerbs: Winetricks verbs installed during this apply.
    ///   - appliedEntryId: The game database entry ID that was applied.
    ///   - appliedVariantId: The variant ID that was applied.
    ///   - timestamp: When the snapshot was created.
    public init(
        bottleSettingsData: Data? = nil,
        programSettingsData: [String: Data]? = nil,
        programEnvironments: [String: GameConfigProgramEnvironment]? = nil,
        bottleChanges: GameConfigBottleChanges? = nil,
        installedVerbs: [String]? = nil,
        appliedEntryId: String,
        appliedVariantId: String,
        timestamp: Date = Date()
    ) {
        self.bottleSettingsData = bottleSettingsData
        self.programSettingsData = programSettingsData
        self.programEnvironments = programEnvironments
        self.bottleChanges = bottleChanges
        self.installedVerbs = installedVerbs
        self.appliedEntryId = appliedEntryId
        self.appliedVariantId = appliedVariantId
        self.timestamp = timestamp
    }

    /// Saves a snapshot to the bottle directory.
    ///
    /// Encodes the snapshot as a property list and writes it to
    /// `bottleURL/GameConfigSnapshot.plist`. Overwrites any existing snapshot.
    ///
    /// - Parameters:
    ///   - snapshot: The snapshot to save.
    ///   - bottleURL: The root URL of the bottle directory.
    /// - Throws: An error if encoding or writing fails.
    public static func save(_ snapshot: GameConfigSnapshot, to bottleURL: URL) throws {
        let url = bottleURL.appending(path: snapshotFileName)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(snapshot)
        try data.write(to: url)
    }

    /// Loads a snapshot from the bottle directory.
    ///
    /// Reads and decodes the snapshot from `bottleURL/GameConfigSnapshot.plist`.
    ///
    /// - Parameter bottleURL: The root URL of the bottle directory.
    /// - Returns: The decoded snapshot, or `nil` if the file does not exist or cannot be decoded.
    public static func load(from bottleURL: URL) -> GameConfigSnapshot? {
        let url = bottleURL.appending(path: snapshotFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListDecoder().decode(GameConfigSnapshot.self, from: data)
    }

    /// Deletes the snapshot file from the bottle directory.
    ///
    /// - Parameter bottleURL: The root URL of the bottle directory.
    /// - Throws: An error if the file cannot be removed.
    public static func delete(from bottleURL: URL) throws {
        let url = bottleURL.appending(path: snapshotFileName)
        try FileManager.default.removeItem(at: url)
    }
}

/// The bottle settings an applied game configuration changed, with the values
/// they had before, so a revert can undo exactly those.
///
/// Settings the apply did not touch are `nil` or absent, and a revert leaves
/// them as they are.
public struct GameConfigBottleChanges: Codable, Sendable, Equatable {
    /// A value from before the apply; `value` is `nil` when there was none.
    public struct Previous<Value: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
        public var value: Value?

        public init(_ value: Value?) {
            self.value = value
        }
    }

    public var graphicsBackend: GraphicsBackend?
    public var enhancedSync: EnhancedSync?
    public var shaderCacheEnabled: Bool?
    public var frameRateLimit: FrameRateLimit?
    /// The DLL override each DLL name had, keyed by DLL name.
    public var dllOverrides: [String: Previous<DLLOverrideEntry>] = [:]
    /// The ``GameConfigEnvironment`` each game entry had, keyed by entry ID.
    public var environments: [String: Previous<GameConfigEnvironment>] = [:]

    public init() {}

    /// These changes combined with `earlier`, those of an apply not yet reverted.
    /// Where both recorded a setting, the earlier previous value wins, so a
    /// revert goes back to the bottle as it was before the first apply.
    public func merged(over earlier: GameConfigBottleChanges) -> GameConfigBottleChanges {
        var result = self
        result.graphicsBackend = earlier.graphicsBackend ?? graphicsBackend
        result.enhancedSync = earlier.enhancedSync ?? enhancedSync
        result.shaderCacheEnabled = earlier.shaderCacheEnabled ?? shaderCacheEnabled
        result.frameRateLimit = earlier.frameRateLimit ?? frameRateLimit
        result.dllOverrides.merge(earlier.dllOverrides) { _, earlier in earlier }
        result.environments.merge(earlier.environments) { _, earlier in earlier }
        return result
    }

    /// `settings` with the recorded settings put back.
    public func reverting(_ settings: BottleSettings) -> BottleSettings {
        var result = settings
        if let graphicsBackend { result.graphicsBackend = graphicsBackend }
        if let enhancedSync { result.enhancedSync = enhancedSync }
        if let shaderCacheEnabled { result.shaderCacheEnabled = shaderCacheEnabled }
        if let frameRateLimit { result.frameRateLimit = frameRateLimit }
        for (name, previous) in dllOverrides {
            if let index = result.dllOverrides.firstIndex(where: { $0.dllName == name }) {
                if let value = previous.value {
                    result.dllOverrides[index] = value
                } else {
                    result.dllOverrides.remove(at: index)
                }
            } else if let value = previous.value {
                result.dllOverrides.append(value)
            }
        }
        for (entryId, previous) in environments {
            result.gameConfigEnvironments.removeAll { $0.entryId == entryId }
            if let value = previous.value {
                result.gameConfigEnvironments.append(value)
            }
        }
        return result
    }
}
