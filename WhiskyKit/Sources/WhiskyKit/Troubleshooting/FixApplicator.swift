// swiftlint:disable file_length
//
//  FixApplicator.swift
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

// MARK: - Fix Preview

/// A preview of what a fix will change before it is applied.
///
/// Shows the current and proposed values for a setting, its scope,
/// and whether the change can be undone.
public struct FixPreview: Sendable {
    /// The human-readable name of the setting being changed.
    public let settingName: String

    /// The current value of the setting.
    public let currentValue: String

    /// The proposed new value after the fix is applied.
    public let newValue: String

    /// Whether this fix targets the bottle or program level.
    public let scope: String

    /// Whether this fix can be reversed via ``FixApplicator/undo(attempt:bottle:program:)``.
    public let isReversible: Bool

    public init(
        settingName: String,
        currentValue: String,
        newValue: String,
        scope: String,
        isReversible: Bool
    ) {
        self.settingName = settingName
        self.currentValue = currentValue
        self.newValue = newValue
        self.scope = scope
        self.isReversible = isReversible
    }
}

// MARK: - Fix Applicator

/// Applies troubleshooting fixes to bottle and program settings with
/// preview, apply, and undo support.
///
/// Follows the ``GPUDetection``/``GameConfigApplicator`` caseless enum pattern.
/// Each fix is identified by a stable `fixId` string that maps to a specific
/// settings mutation. Reversible fixes capture before/after values for undo.
///
/// ## Known Fix IDs
///
/// | Fix ID | Setting | Reversible |
/// |--------|---------|------------|
/// | `switch-backend` | Graphics backend | Yes |
/// | `enable-dxvk-async` | DXVK async shader compilation | Yes |
/// | `set-audio-driver` | Wine audio driver registry key | Yes |
/// | `set-buffer-size` | DirectSound buffer size | Yes |
/// | `enable-esync` | Enhanced sync mode | Yes |
/// | `enable-controller-compat` | Controller compatibility mode | Yes |
/// | `install-winetricks-verb` | Winetricks verb installation | No |
/// | `run-enhanced-diagnostics` | Program WINEDEBUG preset | Yes |
/// | `restart-wineserver` | Wineserver process restart | No |
/// | `set-registry-value` | Arbitrary Wine registry value | Yes |
/// | `apply-launcher-fixes` | Launcher compatibility settings | No |
/// | `apply-game-config` | GameDB recommended configuration | Yes |
public enum FixApplicator { // swiftlint:disable:this type_body_length
    private static let logger = Logger(
        subsystem: "com.franke.Whisky",
        category: "FixApplicator"
    )

    // MARK: - Preview

    /// Returns a preview of what the fix will change without applying it.
    ///
    /// Reads the current value of the target setting and computes the proposed
    /// new value. Returns `nil` for unknown fix IDs.
    ///
    /// - Parameters:
    ///   - fixId: The stable fix identifier.
    ///   - params: Parameters from the flow node (e.g., `"backend": "dxvk"`).
    ///   - bottle: The bottle to inspect.
    ///   - program: The program to inspect, if applicable.
    /// - Returns: A ``FixPreview`` describing the change, or `nil` if the fix ID is unknown.
    @MainActor
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    public static func preview(
        fixId: String,
        params: [String: String],
        bottle: Bottle,
        program: Program?
    ) -> FixPreview? {
        if let fix = settingFix(fixId) {
            return FixPreview(
                settingName: fix.label,
                currentValue: fix.current(bottle.settings).display,
                newValue: fix.target(params).display,
                scope: "bottle",
                isReversible: true
            )
        }

        switch fixId {
        case "install-winetricks-verb":
            let verb = params["verb"] ?? "unknown"
            return FixPreview(
                settingName: "Winetricks Verb",
                currentValue: "Not installed",
                newValue: verb,
                scope: "bottle",
                isReversible: false
            )

        case "run-enhanced-diagnostics":
            guard let program else { return nil }
            let preset = params["preset"].flatMap(WineDebugPreset.init(rawValue:)) ?? .verbose
            return FixPreview(
                settingName: "WINEDEBUG Preset",
                currentValue: program.settings.activeWineDebugPreset?.rawValue ?? "default",
                newValue: preset.rawValue,
                scope: "program",
                isReversible: true
            )

        case "set-registry-value":
            let name = params["settingName"] ?? params["valueName"] ?? "Registry value"
            let current: String = if let key = params["key"], let valueName = params["valueName"] {
                WineRegistryFile.readValue(
                    bottleURL: bottle.url, key: key, valueName: valueName
                ) ?? "Not set"
            } else {
                "Unknown"
            }
            let newValue = params["value"].flatMap { $0.isEmpty ? nil : $0 } ?? "Not set"
            return FixPreview(
                settingName: name,
                currentValue: current,
                newValue: newValue,
                scope: "bottle",
                isReversible: true
            )

        case "apply-launcher-fixes":
            let launcher = program.flatMap { LauncherType.detect(from: $0.url) }
            return FixPreview(
                settingName: "Launcher compatibility fixes",
                currentValue: launcher.map(\.displayName) ?? "No launcher detected",
                newValue: "Reapplied",
                scope: "bottle",
                isReversible: false
            )

        case "apply-game-config":
            guard let program,
                  let match = GameMatcher.bestMatch(
                      metadata: ProgramMetadata(
                          exeName: program.url.lastPathComponent, exeURL: program.url
                      ),
                      against: GameDBLoader.loadDefaults()
                  ),
                  let variant = match.entry.defaultVariant
            else {
                return nil
            }
            let changes = GameConfigApplicator.previewChanges(variant: variant, bottle: bottle)
            return FixPreview(
                settingName: "Game configuration: \(match.entry.title)",
                currentValue: changes.isEmpty
                    ? "Already matches" : "\(changes.count) setting(s) differ",
                newValue: variant.label,
                scope: "bottle",
                isReversible: true
            )

        case "restart-wineserver":
            return FixPreview(
                settingName: "Wineserver",
                currentValue: "Running",
                newValue: "Restarted",
                scope: "bottle",
                isReversible: false
            )

        default:
            logger.warning("Unknown fixId for preview: \(fixId)")
            return nil
        }
    }

    // MARK: - Apply

    /// Applies a fix to the bottle or program settings.
    ///
    /// Captures the before-value from the current state, mutates the setting,
    /// and returns a ``FixAttempt`` with the result. Settings changes are
    /// immediate writes via ``BottleSettings`` `didSet` auto-save.
    ///
    /// Some fixes involve async operations (winetricks, Wine registry commands).
    /// For those, `apply()` returns a ``FixAttempt`` with `.pending` result.
    /// The engine's verify step confirms completion.
    ///
    /// - Parameters:
    ///   - fixId: The stable fix identifier.
    ///   - params: Parameters from the flow node.
    ///   - bottle: The bottle to modify.
    ///   - program: The program to modify, if applicable.
    /// - Returns: A ``FixAttempt`` recording what was changed.
    @MainActor
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    public static func apply(
        fixId: String,
        params: [String: String],
        bottle: Bottle,
        program: Program?
    ) -> FixAttempt {
        if let fix = settingFix(fixId) {
            let before = fix.current(bottle.settings).raw
            let target = fix.target(params).raw
            _ = fix.write(bottle, target)
            return FixAttempt(fixId: fixId, beforeValue: before, afterValue: target, result: fix.result)
        }

        switch fixId {
        case "install-winetricks-verb":
            // Winetricks installation is async and non-reversible.
            // The actual install is delegated to the Winetricks infrastructure.
            let verb = params["verb"] ?? "unknown"
            return FixAttempt(
                fixId: fixId,
                beforeValue: nil,
                afterValue: verb,
                result: .pending
            )

        case "run-enhanced-diagnostics":
            guard let program else {
                logger.info("run-enhanced-diagnostics needs a program context")
                return FixAttempt(fixId: fixId, result: .failed)
            }
            let preset = params["preset"].flatMap(WineDebugPreset.init(rawValue:)) ?? .verbose
            let before = program.settings.activeWineDebugPreset?.rawValue ?? "default"
            program.settings.activeWineDebugPreset = preset
            return FixAttempt(
                fixId: fixId,
                beforeValue: before,
                afterValue: preset.rawValue,
                result: .applied
            )

        case "set-registry-value":
            guard let key = params["key"], let valueName = params["valueName"] else {
                logger.error("set-registry-value needs 'key' and 'valueName' params")
                return FixAttempt(fixId: fixId, result: .failed)
            }
            let before = WineRegistryFile.readValue(
                bottleURL: bottle.url, key: key, valueName: valueName
            )
            let value = params["value"] ?? ""
            writeRegistryValue(
                key: key,
                valueName: valueName,
                value: value,
                type: registryType(for: params["valueType"]),
                bottle: bottle
            )
            // The write runs through wine reg; the verify step re-reads the
            // prefix to confirm it landed.
            return FixAttempt(
                fixId: fixId,
                beforeValue: before,
                afterValue: value.isEmpty ? nil : value,
                result: .pending,
                params: params
            )

        case "apply-launcher-fixes":
            guard let program, let launcher = LauncherType.detect(from: program.url) else {
                logger.info("apply-launcher-fixes: no launcher detected for this program")
                return FixAttempt(fixId: fixId, result: .failed)
            }
            LauncherFixes.apply(to: bottle, launcher: launcher, force: true)
            return FixAttempt(
                fixId: fixId,
                beforeValue: nil,
                afterValue: launcher.rawValue,
                result: .applied
            )

        case "apply-game-config":
            guard let program,
                  let match = GameMatcher.bestMatch(
                      metadata: ProgramMetadata(
                          exeName: program.url.lastPathComponent, exeURL: program.url
                      ),
                      against: GameDBLoader.loadDefaults()
                  ),
                  let variant = match.entry.defaultVariant
            else {
                logger.info("apply-game-config: no confident game match for this program")
                return FixAttempt(fixId: fixId, result: .failed)
            }
            do {
                _ = try GameConfigApplicator.apply(
                    entry: match.entry, variant: variant, to: bottle, programURL: program.url
                )
                return FixAttempt(
                    fixId: fixId,
                    beforeValue: nil,
                    afterValue: "\(match.entry.title) (\(variant.label))",
                    result: .applied
                )
            } catch {
                logger.error("apply-game-config failed: \(error.localizedDescription)")
                return FixAttempt(fixId: fixId, result: .failed)
            }

        case "restart-wineserver":
            // Non-reversible: kills the wineserver process
            Wine.killBottle(bottle: bottle)
            return FixAttempt(
                fixId: fixId,
                beforeValue: "running",
                afterValue: "restarted",
                result: .applied
            )

        default:
            logger.warning("Unknown fixId for apply: \(fixId)")
            return FixAttempt(
                fixId: fixId,
                beforeValue: nil,
                afterValue: nil,
                result: .failed
            )
        }
    }

    // MARK: - Undo

    /// Reverses a previously applied fix if it is reversible.
    ///
    /// Uses the ``FixAttempt/fixId`` and ``FixAttempt/beforeValue`` to restore
    /// the previous state. Returns `false` for non-reversible fixes (winetricks,
    /// dependency install, wineserver restart).
    ///
    /// - Parameters:
    ///   - attempt: The fix attempt to undo.
    ///   - bottle: The bottle to restore.
    ///   - program: The program to restore, if applicable.
    /// - Returns: `true` if the undo succeeded, `false` if the fix is non-reversible.
    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    public static func undo(
        attempt: FixAttempt,
        bottle: Bottle,
        program: Program?
    ) -> Bool {
        if let fix = settingFix(attempt.fixId) {
            guard let before = attempt.beforeValue else { return false }
            return fix.write(bottle, before)
        }

        switch attempt.fixId {
        case "run-enhanced-diagnostics":
            guard let program else { return false }
            // A before-value that names no preset ("default") clears it
            program.settings.activeWineDebugPreset = attempt.beforeValue
                .flatMap(WineDebugPreset.init(rawValue:))
            return true

        case "set-registry-value":
            guard let params = attempt.params,
                  let key = params["key"], let valueName = params["valueName"]
            else {
                return false
            }
            writeRegistryValue(
                key: key, valueName: valueName, value: attempt.beforeValue ?? "",
                type: registryType(for: params["valueType"]), bottle: bottle
            )
            return true

        case "apply-game-config":
            guard let snapshot = GameConfigSnapshot.load(from: bottle.url) else { return false }
            return (try? GameConfigApplicator.revert(bottle: bottle, snapshot: snapshot)) != nil

        case "install-winetricks-verb",
             "apply-launcher-fixes",
             "restart-wineserver":
            // Non-reversible fixes cannot be undone
            logger.info("Fix '\(attempt.fixId)' is not reversible")
            return false

        default:
            logger.warning("Unknown fixId for undo: \(attempt.fixId)")
            return false
        }
    }

    // MARK: - Setting Fixes

    /// A fix that sets one bottle setting, described once for preview, apply and undo.
    private struct SettingFix {
        let label: String
        let result: FixResult
        /// The current value as previewed and as recorded for undo.
        let current: (BottleSettings) -> (display: String, raw: String)
        /// The value the fix sets, from the flow node params.
        let target: ([String: String]) -> (display: String, raw: String)
        /// Writes a raw value back; `false` when it names no valid value.
        let write: @MainActor (Bottle, String) -> Bool
    }

    @MainActor
    private static func settingFix(_ fixId: String) -> SettingFix? {
        switch fixId {
        case "switch-backend":
            choice(
                "Graphics Backend", \.graphicsBackend, param: "backend", fallback: .recommended,
                display: \.displayName
            )
        case "enable-dxvk-async":
            toggle("DXVK Async Shader Compilation", \.dxvkAsync)
        case "set-audio-driver":
            // Registry write is async; pending until the engine verifies it
            choice(
                "Audio Driver", \.audioDriver, param: "driver", fallback: .coreaudio,
                display: \.displayName, result: .pending
            )
        case "set-buffer-size":
            // Registry write is async; pending until the engine verifies it
            choice(
                "Audio Buffer Size", \.audioLatencyPreset, param: "preset", fallback: .stable,
                display: \.displayName, result: .pending
            )
        case "enable-esync":
            SettingFix(
                label: "Enhanced Sync",
                result: .applied,
                current: { settings in
                    let mode = String(describing: settings.enhancedSync)
                    return (mode, mode)
                },
                target: { _ in ("esync", "esync") },
                write: { bottle, raw in
                    // A value naming no mode restores sync off
                    bottle.settings.enhancedSync = [EnhancedSync.none, .esync, .msync]
                        .first { String(describing: $0) == raw } ?? EnhancedSync.none
                    return true
                }
            )
        case "enable-controller-compat":
            toggle("Controller Compatibility Mode", \.controllerCompatibilityMode)
        default:
            nil
        }
    }

    @MainActor
    private static func toggle(_ label: String, _ keyPath: WritableKeyPath<BottleSettings, Bool>) -> SettingFix {
        SettingFix(
            label: label,
            result: .applied,
            current: { settings in
                (settings[keyPath: keyPath] ? "Enabled" : "Disabled", String(settings[keyPath: keyPath]))
            },
            target: { _ in ("Enabled", "true") },
            write: { bottle, raw in
                bottle.settings[keyPath: keyPath] = raw == "true"
                return true
            }
        )
    }

    @MainActor
    private static func choice<Value: RawRepresentable>(
        _ label: String,
        _ keyPath: WritableKeyPath<BottleSettings, Value>,
        param: String,
        fallback: Value,
        display: @escaping (Value) -> String,
        result: FixResult = .applied
    ) -> SettingFix where Value.RawValue == String {
        SettingFix(
            label: label,
            result: result,
            current: { settings in (display(settings[keyPath: keyPath]), settings[keyPath: keyPath].rawValue) },
            target: { params in
                let value = params[param].flatMap(Value.init(rawValue:)) ?? fallback
                return (display(value), value.rawValue)
            },
            write: { bottle, raw in
                guard let value = Value(rawValue: raw) else { return false }
                bottle.settings[keyPath: keyPath] = value
                return true
            }
        )
    }

    // MARK: - Registry Helpers

    private static func registryType(for name: String?) -> RegistryType {
        switch name {
        case "dword": .dword
        case "qword": .qword
        case "binary": .binary
        default: .string
        }
    }

    /// Fires the registry write without blocking the caller. An empty value
    /// deletes the entry, which is how an override is cleared.
    @MainActor
    private static func writeRegistryValue(
        key: String, valueName: String, value: String, type: RegistryType, bottle: Bottle
    ) {
        Task {
            do {
                if value.isEmpty {
                    try await Wine.deleteRegistryValue(bottle: bottle, key: key, name: valueName)
                } else {
                    try await Wine.addRegistryKey(
                        bottle: bottle, key: key, name: valueName, data: value, type: type
                    )
                }
            } catch {
                logger.error(
                    "Registry write \(key)\\\(valueName) failed: \(error.localizedDescription)"
                )
            }
        }
    }
}

// swiftlint:enable file_length
