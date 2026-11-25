// swiftlint:disable file_length
//
//  GameConfigApplicator.swift
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

/// A single setting change to be applied, shown in the preview diff.
///
/// Groups changes by category (Graphics, Performance, DLL Overrides, etc.)
/// with before/after values and an impact indicator. The text fields are
/// localized for display; match on ``kind`` instead of comparing them.
public struct ConfigChange: Sendable, Equatable {
    /// What a change sets, independent of the display language.
    public enum Kind: String, Sendable {
        case graphicsBackend
        case frameRateLimit
        case enhancedSync
        case shaderCache
        case dllOverride
        case environmentVariable
        case winetricksVerb
    }

    /// What this change sets.
    public let kind: Kind
    /// The localized category of the setting (e.g., "Graphics", "Performance").
    public let category: String
    /// The display name of the setting.
    public let settingName: String
    /// The current value as a human-readable string.
    public let currentValue: String
    /// The new value to be applied as a human-readable string.
    public let newValue: String
    /// Whether this change is high-impact (e.g., graphics backend switch, DLL overrides).
    public let isHighImpact: Bool

    public init(
        kind: Kind,
        category: String,
        settingName: String,
        currentValue: String,
        newValue: String,
        isHighImpact: Bool = false
    ) {
        self.kind = kind
        self.category = category
        self.settingName = settingName
        self.currentValue = currentValue
        self.newValue = newValue
        self.isHighImpact = isHighImpact
    }
}

/// Applies and reverts game configurations to bottles.
///
/// The applicator works through existing ``BottleSettings`` properties so changes
/// flow through the ``EnvironmentBuilder`` cascade at launch time. Before mutating
/// any settings, a ``GameConfigSnapshot`` is created for undo/revert.
///
/// ## Usage
///
/// ```swift
/// let snapshot = try GameConfigApplicator.apply(
///     entry: eldenRingEntry,
///     variant: eldenRingEntry.defaultVariant!,
///     to: bottle
/// )
/// // Later, to undo:
/// let verbs = try GameConfigApplicator.revert(bottle: bottle, snapshot: snapshot)
/// ```
///
/// ## Thread Safety
///
/// Apply and revert methods are `@MainActor` because they mutate ``Bottle/settings``,
/// which is `@MainActor`-isolated.
public enum GameConfigApplicator {
    // MARK: - Apply

    /// Applies a game configuration variant to a bottle's settings.
    ///
    /// This method:
    /// 1. Snapshots the current ``BottleSettings`` and the program environment
    ///    variables it replaces
    /// 2. Mutates the bottle's settings based on the variant
    /// 3. Applies the variant's environment variables to the game's launches
    ///    (see ``applyEnvironment(_:entry:to:targets:programURL:)``)
    /// 4. Saves the snapshot to the bottle directory
    /// 5. Returns the snapshot for display and future revert
    ///
    /// Winetricks verbs are not installed here: installing runs winetricks for
    /// minutes, so the app does it afterwards with progress, using
    /// ``pendingWinetricksVerbs(variant:installedVerbs:programURL:)``, and records what
    /// landed with ``recordInstalledVerbs(_:bottleURL:)``.
    ///
    /// - Parameters:
    ///   - entry: The game database entry being applied.
    ///   - variant: The specific variant to apply.
    ///   - bottle: The target bottle whose settings will be mutated.
    ///   - programURL: The program the configuration is applied from, if any. It
    ///     receives the environment variables.
    /// - Returns: The snapshot created before applying changes.
    /// - Throws: An error if the snapshot cannot be encoded or saved.
    @MainActor
    public static func apply(
        entry: GameDBEntry,
        variant: GameConfigVariant,
        to bottle: Bottle,
        programURL: URL? = nil
    ) throws -> GameConfigSnapshot {
        // 1. Snapshot current state. An apply over one not yet reverted keeps that
        // one's snapshot, so a revert goes back to the bottle before either.
        let earlier = GameConfigSnapshot.load(from: bottle.url)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let bottleSettingsData = try earlier?.bottleSettingsData ?? encoder.encode(bottle.settings)

        // 2. Create snapshot. The app records the verbs that install with
        // recordInstalledVerbs.
        var snapshot = GameConfigSnapshot(
            bottleSettingsData: bottleSettingsData,
            appliedEntryId: entry.id,
            appliedVariantId: variant.id,
            timestamp: Date()
        )
        snapshot.programEnvironments = earlier?.programEnvironments
        snapshot.installedVerbs = earlier?.installedVerbs

        // Record the program environment variables this apply replaces
        let environmentTargets = environmentTargets(entry: entry, bottle: bottle, programURL: programURL)
        snapshotEnvironment(variant.environmentVariables ?? [:], of: environmentTargets, into: &snapshot)

        // Record the bottle settings this apply changes. An earlier snapshot without
        // them is from before they were recorded, and its revert stays the old one.
        if earlier == nil || earlier?.bottleChanges != nil {
            let changes = snapshotBottleChanges(
                variant: variant, entry: entry, bottle: bottle, targets: environmentTargets
            )
            snapshot.bottleChanges = earlier?.bottleChanges.map { changes.merged(over: $0) } ?? changes
        }

        // 3. Apply variant settings to bottle
        applyVariantSettings(variant.settings, to: bottle)

        // 4. Apply DLL overrides (deduplicate by DLL name, prefer variant value)
        if let overrides = variant.dllOverrides, !overrides.isEmpty {
            applyDLLOverrides(overrides, to: bottle)
        }

        // 5. Apply custom environment variables to the game's launches
        if let variables = variant.environmentVariables {
            applyEnvironment(
                variables, entry: entry, to: bottle, targets: environmentTargets, programURL: programURL
            )
        }

        // 6. Save snapshot to bottle directory
        try GameConfigSnapshot.save(snapshot, to: bottle.url)

        return snapshot
    }

    // MARK: - Revert

    /// Reverts a bottle's settings to the state captured in the snapshot.
    ///
    /// Puts back the settings, DLL overrides and stored game environments the apply
    /// changed (``GameConfigSnapshot/bottleChanges``), then the program environment
    /// variables in ``GameConfigSnapshot/programEnvironments``. Everything else, such
    /// as pins, the bottle's name or a DLL override added since, stays. A snapshot
    /// from before the changes were recorded puts back the settings an apply can
    /// change from ``GameConfigSnapshot/bottleSettingsData`` instead. The `didSet`
    /// observers handle automatic persistence.
    ///
    /// - Parameters:
    ///   - bottle: The bottle whose settings will be restored.
    ///   - snapshot: The snapshot from a previous ``apply(entry:variant:to:programURL:)`` call.
    /// - Returns: A list of winetricks verbs that were installed after the original apply
    ///   (non-reversible, for UI display: "Settings reverted; installed components remain").
    /// - Throws: An error if the snapshot data cannot be decoded or the snapshot file cannot be deleted.
    @MainActor
    public static func revert(
        bottle: Bottle,
        snapshot: GameConfigSnapshot
    ) throws -> [String] {
        // 1. Restore bottle settings
        if let changes = snapshot.bottleChanges {
            bottle.settings = changes.reverting(bottle.settings)
        } else if let settingsData = snapshot.bottleSettingsData {
            let saved = try PropertyListDecoder().decode(BottleSettings.self, from: settingsData)
            var restored = bottle.settings
            restored.graphicsBackend = saved.graphicsBackend
            restored.enhancedSync = saved.enhancedSync
            restored.shaderCacheEnabled = saved.shaderCacheEnabled
            restored.frameRateLimit = saved.frameRateLimit
            restored.dllOverrides = saved.dllOverrides
            restored.gameConfigEnvironments = saved.gameConfigEnvironments
            bottle.settings = restored
        }
        restoreProgramEnvironments(from: snapshot, in: bottle)

        // 2. Delete the snapshot file
        try GameConfigSnapshot.delete(from: bottle.url)

        // 3. Return installed verbs as non-reversible items
        return snapshot.installedVerbs ?? []
    }

    // MARK: - Pending Winetricks Verbs

    /// The winetricks verbs the variant needs for a program.
    ///
    /// The VC++ runtime verbs are left out for a program on disk that is not a
    /// Unity game: the runtime keeps what they install out of the system
    /// folders, and only a Unity game gets it (``VCRuntimeIsolation``).
    /// Without a program, every verb stays.
    ///
    /// - Parameters:
    ///   - variant: The game configuration variant.
    ///   - programURL: The program the configuration is applied from, if any.
    /// - Returns: The verbs, in the variant's order.
    public static func requiredWinetricksVerbs(variant: GameConfigVariant, programURL: URL?) -> [String] {
        let verbs = variant.winetricksVerbs ?? []
        guard let programURL, FileManager.default.fileExists(atPath: programURL.path(percentEncoded: false)),
              !VCRuntimeIsolation.isUnityGame(executable: programURL)
        else { return verbs }
        return verbs.filter { !VCRuntimeIsolation.winetricksVerbs.contains($0) }
    }

    /// Returns winetricks verbs required by the variant that are not yet installed.
    ///
    /// - Parameters:
    ///   - variant: The game configuration variant.
    ///   - installedVerbs: The set of verbs already installed in the bottle.
    ///   - programURL: The program the configuration is applied from, if any.
    /// - Returns: An array of verb names that still need to be installed.
    public static func pendingWinetricksVerbs(
        variant: GameConfigVariant,
        installedVerbs: Set<String>,
        programURL: URL?
    ) -> [String] {
        requiredWinetricksVerbs(variant: variant, programURL: programURL).filter { !installedVerbs.contains($0) }
    }

    // MARK: - Preview Changes

    // swiftlint:disable function_body_length
    /// Generates a preview of what settings would change if a variant were applied.
    ///
    /// Compares each non-nil field in the variant's settings against the current
    /// bottle settings and returns an array of ``ConfigChange`` values grouped
    /// by category.
    ///
    /// - Parameters:
    ///   - variant: The variant to preview.
    ///   - bottle: The bottle whose current settings are compared.
    ///   - entry: The entry the variant belongs to. With it, environment variables
    ///     are compared against where the apply puts them; without it they are
    ///     all listed as not set.
    ///   - programURL: The program the configuration is applied from, if any.
    ///   - installedVerbs: The winetricks verbs the bottle already has, which are
    ///     left out of the verbs to install.
    /// - Returns: An array of changes, with high-impact changes flagged.
    @MainActor
    public static func previewChanges(
        variant: GameConfigVariant,
        bottle: Bottle,
        entry: GameDBEntry? = nil,
        programURL: URL? = nil,
        installedVerbs: Set<String> = []
    ) -> [ConfigChange] {
        var changes: [ConfigChange] = []
        let settings = variant.settings
        let graphics = String(localized: "gameConfig.detail.graphics")
        let performance = String(localized: "gameConfig.detail.performance")
        let notSet = String(localized: "gameConfig.preview.value.notSet")

        // Graphics settings
        if let backend = settings.graphicsBackend, backend != bottle.settings.graphicsBackend {
            changes.append(ConfigChange(
                kind: .graphicsBackend,
                category: graphics,
                settingName: String(localized: "config.graphics.backend"),
                currentValue: bottle.settings.graphicsBackend.displayName,
                newValue: backend.displayName,
                isHighImpact: true
            ))
        }

        changes += frameRateLimitChanges(settings: settings, bottle: bottle, category: graphics)

        // Performance settings
        if let enhancedSync = settings.enhancedSync, enhancedSync != bottle.settings.enhancedSync {
            changes.append(ConfigChange(
                kind: .enhancedSync,
                category: performance,
                settingName: String(localized: "config.enhancedSync"),
                currentValue: describeEnhancedSync(bottle.settings.enhancedSync),
                newValue: describeEnhancedSync(enhancedSync)
            ))
        }

        if let shaderCache = settings.shaderCacheEnabled, shaderCache != bottle.settings.shaderCacheEnabled {
            changes.append(ConfigChange(
                kind: .shaderCache,
                category: performance,
                settingName: String(localized: "config.shaderCache"),
                currentValue: describeEnabled(bottle.settings.shaderCacheEnabled),
                newValue: describeEnabled(shaderCache)
            ))
        }

        // DLL overrides
        if let overrides = variant.dllOverrides, !overrides.isEmpty {
            let existingNames = Set(bottle.settings.dllOverrides.map(\.dllName))
            let newOverrides = overrides.filter { !existingNames.contains($0.dllName) }
            let updatedOverrides = overrides.filter { existingNames.contains($0.dllName) }

            for override in newOverrides {
                changes.append(ConfigChange(
                    kind: .dllOverride,
                    category: String(localized: "gameConfig.detail.dllOverrides"),
                    settingName: override.dllName,
                    currentValue: notSet,
                    newValue: override.mode.displayName,
                    isHighImpact: true
                ))
            }

            for override in updatedOverrides {
                if let existing = bottle.settings.dllOverrides.first(where: {
                    $0.dllName == override.dllName
                }),
                    existing.mode != override.mode {
                    changes.append(ConfigChange(
                        kind: .dllOverride,
                        category: String(localized: "gameConfig.detail.dllOverrides"),
                        settingName: override.dllName,
                        currentValue: existing.mode.displayName,
                        newValue: override.mode.displayName,
                        isHighImpact: true
                    ))
                }
            }
        }

        // Environment variables
        changes += environmentChanges(variant: variant, entry: entry, bottle: bottle, programURL: programURL)

        // Winetricks verbs
        changes += winetricksChanges(variant: variant, installedVerbs: installedVerbs, programURL: programURL)

        return changes
    }

    /// The frame rate cap a variant would change, as a preview row.
    @MainActor
    private static func frameRateLimitChanges(
        settings: GameConfigVariantSettings, bottle: Bottle, category: String
    ) -> [ConfigChange] {
        guard let limit = settings.frameRateLimit, limit != bottle.settings.frameRateLimit else { return [] }
        return [ConfigChange(
            kind: .frameRateLimit,
            category: category,
            settingName: String(localized: "config.frameRateLimit"),
            currentValue: bottle.settings.frameRateLimit.label,
            newValue: limit.label
        )]
    }

    // swiftlint:enable function_body_length

    // MARK: - Private Helpers

    /// Applies variant settings to the bottle's settings.
    @MainActor
    private static func applyVariantSettings(
        _ settings: GameConfigVariantSettings,
        to bottle: Bottle
    ) {
        if let graphicsBackend = settings.graphicsBackend {
            bottle.settings.graphicsBackend = graphicsBackend
        }

        if let enhancedSync = settings.enhancedSync {
            bottle.settings.enhancedSync = enhancedSync
        }

        if let shaderCacheEnabled = settings.shaderCacheEnabled {
            bottle.settings.shaderCacheEnabled = shaderCacheEnabled
        }

        if let frameRateLimit = settings.frameRateLimit {
            bottle.settings.frameRateLimit = frameRateLimit
        }
    }

    /// Appends DLL overrides to the bottle, deduplicating by DLL name (variant value wins).
    @MainActor
    private static func applyDLLOverrides(_ overrides: [DLLOverrideEntry], to bottle: Bottle) {
        var existingByName: [String: Int] = [:]
        for (index, entry) in bottle.settings.dllOverrides.enumerated() {
            existingByName[entry.dllName] = index
        }

        var updatedOverrides = bottle.settings.dllOverrides

        for override in overrides {
            if let existingIndex = existingByName[override.dllName] {
                // Replace existing with variant value
                updatedOverrides[existingIndex] = override
            } else {
                // Append new override
                updatedOverrides.append(override)
            }
        }

        bottle.settings.dllOverrides = updatedOverrides
    }

    /// Returns a localized description of an EnhancedSync value.
    private static func describeEnhancedSync(_ sync: EnhancedSync) -> String {
        switch sync {
        case .none:
            String(localized: "config.enhancedSync.none")
        case .msync:
            String(localized: "config.enhancedSync.msync")
        }
    }

    /// Returns a localized description of an on/off setting.
    private static func describeEnabled(_ isEnabled: Bool) -> String {
        isEnabled ? String(localized: "config.retinaMode.on") : String(localized: "config.retinaMode.off")
    }
}

// swiftlint:enable file_length
