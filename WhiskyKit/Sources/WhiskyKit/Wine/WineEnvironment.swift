// swiftlint:disable function_body_length
//
//  WineEnvironment.swift
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

private let envLogger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "WineEnvironment")

// swiftlint:disable cyclomatic_complexity
extension Wine {
    /// Construct an environment merging the bottle values with the given values
    /// using EnvironmentBuilder with 8-layer resolution.
    ///
    /// Each Wine process launch resolves through this method, which populates
    /// an ``EnvironmentBuilder`` with base, platform, bottleManaged, launcherManaged,
    /// bottleUser, programUser, featureRuntime, and callsiteOverride layers.
    /// WINEDLLOVERRIDES is composed per-DLL via ``DLLOverrideResolver``.
    ///
    /// Invalid environment variable keys (those not matching `[A-Za-z_][A-Za-z0-9_]*`)
    /// are filtered out with a debug log message, as macOS silently ignores them.
    ///
    /// - Parameters:
    ///   - bottle: The bottle whose settings configure the environment.
    ///   - environment: Caller-provided environment variables (typically from `Program.generateEnvironment()`).
    ///   - programOverrides: Optional per-program setting overrides. `nil` fields inherit from bottle.
    ///   - steeredExecutables: Executables of this launch that run on WineD3D
    ///     whatever the bottle picks, beside the bottle's own launcher and the front-end table.
    ///   - programBackends: The executables with a backend of their own, which beats the rest.
    /// - Returns: The fully resolved environment dictionary for passing to a Wine process.
    @MainActor
    public static func constructWineEnvironment(
        for bottle: Bottle,
        environment: [String: String] = [:],
        programOverrides: ProgramOverrides? = nil,
        programSettings: ProgramSettings? = nil,
        gameProfileEnvironment: [String: String] = [:],
        steeredExecutables: [String] = [],
        programBackends: [(executable: String, backend: GraphicsBackend)] = [],
        unityDLLs: [String] = []
    ) -> [String: String] {
        var builder = EnvironmentBuilder()
        // The lowest layer, so the user's own override for the same DLL wins.
        var dllResolver = DLLOverrideResolver(
            managed: unityDLLs.map {
                (entry: DLLOverrideEntry(dllName: $0, mode: .nativeThenBuiltin), source: .launcher("Unity"))
            },
            bottleCustom: [], programCustom: []
        )

        // Layer 1: Base -- WINEPREFIX, default WINEDEBUG, GST_DEBUG
        builder.set("WINEPREFIX", bottle.url.path, layer: .base)
        builder.set("WINEDEBUG", "fixme-all", layer: .base)
        builder.set("GST_DEBUG", "1", layer: .base)

        // Layer 2: Platform -- macOS compatibility fixes
        // Apply fixes from the MacOSCompatibilityFixes registry with reason strings.
        for fix in MacOSCompatibilityFixes.activeFixes() {
            builder.set(fix.key, fix.value, layer: .platform, reason: fix.reason)
        }
        // Forward host timezone so games that read system time/date behave correctly.
        // macOS does not export TZ by default; without this, Wine sees UTC.
        if ProcessInfo.processInfo.environment["TZ"] == nil {
            builder.set(
                "TZ", TimeZone.current.identifier, layer: .platform,
                reason: "Host timezone forwarding"
            )
        }

        // Layer 3: Bottle managed -- settings-derived env vars (sync, Metal, perf)
        // Resolved on the main actor here so the nonisolated settings layer does
        // not have to reach for NSScreen itself.
        let displayRefreshRate = FrameRateLimit.mainDisplayRefreshRate()
        bottle.settings.populateBottleManagedLayer(builder: &builder, displayRefreshRate: displayRefreshRate)

        // Layer 4: Launcher managed -- launcher compatibility overrides
        bottle.settings.populateLauncherManagedLayer(builder: &builder)

        // Input compatibility (bottleManaged layer -- input settings are bottle-managed toggles)
        bottle.settings.populateInputCompatibilityLayer(builder: &builder)

        // Layer 5: Game profile -- GameDB variant environment for this launch.
        // Beats bottle/launcher defaults, loses to anything the user set.
        for (key, value) in gameProfileEnvironment {
            if isValidEnvKey(key) {
                builder.set(key, value, layer: .gameProfile, reason: "GameDB profile")
            } else {
                envLogger.debug("Skipping invalid game profile key '\(key)' in constructWineEnvironment")
            }
        }

        // Layer 6: Bottle user (empty for now -- no bottle-level custom env vars UI yet)

        // Layer 7: Program user (caller-provided environment dict, typically from Program.generateEnvironment())
        if !environment.isEmpty {
            for (key, value) in environment {
                if isValidEnvKey(key) {
                    builder.set(key, value, layer: .programUser)
                } else {
                    envLogger.debug("Skipping invalid environment key '\(key)' in constructWineEnvironment")
                }
            }
        }

        // Apply per-program overrides to the programUser layer
        if let overrides = programOverrides {
            applyProgramOverrides(
                overrides,
                builder: &builder,
                dllResolver: &dllResolver,
                bottleBackend: bottle.settings.graphicsBackend,
                bottleFrameRateLimit: bottle.settings.frameRateLimit,
                displayRefreshRate: displayRefreshRate
            )
        }

        // The program's own WINEDLLOVERRIDES, merged rather than replaced: the
        // composed value used to be assigned over it, so it did nothing whenever
        // the bottle had any override at all. Program-custom, after the program's
        // overrides, so the DLLs it names beat every preset and the rest of the
        // composition stands. Only the program's own value: a GameDB profile's
        // must not outrank the user's bottle overrides.
        if let programValue = environment["WINEDLLOVERRIDES"] {
            dllResolver.programCustom.append(contentsOf: DLLOverrideResolver.parse(programValue))
        }

        // Layer 8: featureRuntime -- diagnostic WINEDEBUG preset override
        if let preset = programSettings?.activeWineDebugPreset, preset != .normal {
            builder.set("WINEDEBUG", preset.winedebugValue, layer: .featureRuntime)
        }

        // Layer 9: callsiteOverride is left empty (populated by direct callers)

        // Collect bottle custom DLL overrides for the resolver
        dllResolver.bottleCustom = bottle.settings.dllOverrides

        // Resolve the builder and capture provenance for launch logging
        let (resolved, provenance) = builder.resolve()
        var result = resolved

        // The runtime picks its graphics layer per executable from these rules.
        let rules = compatdbRules(
            bottleBackend: bottle.settings.graphicsBackend,
            steeredExecutables: steeredExecutables + (bottle.settings.detectedLauncher?.helperExecutables ?? []),
            programBackends: programBackends,
            userRules: result["WINE_COMPATDB"]
        )
        if let rules {
            result["WINE_COMPATDB"] = rules
        }

        // Compose WINEDLLOVERRIDES from DLLOverrideResolver (outside the builder)
        let (overrideString, _) = dllResolver.resolve()
        if !overrideString.isEmpty {
            result["WINEDLLOVERRIDES"] = overrideString
        }

        // Launch logging: safe summary of bottle, active layers, and whitelisted keys
        logLaunchSummary(bottleName: bottle.settings.name, provenance: provenance, environment: result)

        return result
    }

    /// Applies per-program overrides to the programUser layer of the builder.
    ///
    /// Each non-nil field in the overrides sets the corresponding environment variable(s)
    /// in the ``EnvironmentLayer/programUser`` layer, which has higher priority than
    /// bottleManaged and launcherManaged layers.
    static func applyProgramOverrides(
        _ overrides: ProgramOverrides,
        builder: inout EnvironmentBuilder,
        dllResolver: inout DLLOverrideResolver,
        bottleBackend: GraphicsBackend = .recommended,
        bottleFrameRateLimit: FrameRateLimit = .unlimited,
        displayRefreshRate: Int? = nil
    ) {
        // Enhanced sync override
        if let enhancedSync = overrides.enhancedSync {
            builder.set("WINEMSYNC", enhancedSync == .msync ? "1" : "0", layer: .programUser)
        }

        // Metal HUD override. The bottle value lands in the bottleManaged layer
        // and reaches every process in the prefix, launcher windows included, so
        // a program that wants the HUD to itself sets it here.
        //
        // Removal rather than "0": the resolved environment must not carry the
        // variable at all -- absence is off to the HUD, and a removal also
        // shadows the bottle's value instead of contradicting it. (Verified on
        // macOS 27.2: MTL_HUD_ENABLED=1 draws the HUD; =0 and absent do not.)
        if let metalHud = overrides.metalHud {
            if metalHud {
                builder.set("MTL_HUD_ENABLED", "1", layer: .programUser)
            } else {
                builder.remove("MTL_HUD_ENABLED", layer: .programUser)
            }
        }

        // Shader cache override, on the variable DXMT reads.
        if let shaderCache = overrides.shaderCacheEnabled {
            if !shaderCache {
                builder.set("DXMT_SHADER_CACHE", "0", layer: .programUser)
            } else {
                builder.remove("DXMT_SHADER_CACHE", layer: .programUser)
            }
        }

        // Input override: controller compatibility SDL hints at program level
        if let controllerCompat = overrides.controllerCompatibilityMode {
            // When compat mode is overridden, control whether SDL hints are applied
            if controllerCompat {
                if let disableHIDAPI = overrides.disableHIDAPI, disableHIDAPI {
                    builder.set("SDL_JOYSTICK_HIDAPI", "0", layer: .programUser)
                }
                if let allowBG = overrides.allowBackgroundEvents, allowBG {
                    builder.set("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", "1", layer: .programUser)
                }
                let mapping = overrides.disableControllerMapping ?? false
                let labels = overrides.useButtonLabels ?? false
                if mapping || labels {
                    builder.set("SDL_GAMECONTROLLER_USE_BUTTON_LABELS", "1", layer: .programUser)
                } else {
                    builder.set("SDL_GAMECONTROLLER_USE_BUTTON_LABELS", "0", layer: .programUser)
                }
            } else {
                // Program overrides compat mode off: remove all SDL hints
                builder.remove("SDL_JOYSTICK_HIDAPI", layer: .programUser)
                builder.remove("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", layer: .programUser)
                builder.remove("SDL_GAMECONTROLLER_USE_BUTTON_LABELS", layer: .programUser)
            }
        }

        // Frame rate cap. Re-resolved here whenever the program overrides either
        // the cap or the backend, because the two are coupled: only DXMT has a
        // limiter, so a program moved to WineD3D drops the bottle's DXMT_CONFIG.
        if overrides.graphicsBackend != nil || overrides.frameRateLimit != nil {
            let chosen = overrides.graphicsBackend ?? bottleBackend
            let effectiveBackend = chosen == .recommended ? GraphicsBackendResolver.resolve() : chosen
            let fps = (overrides.frameRateLimit ?? bottleFrameRateLimit)
                .resolved(displayRefreshRate: displayRefreshRate)
            if effectiveBackend == .dxmt {
                // The cap is one entry of DXMT_CONFIG, so it is merged, not set: a
                // DXMT_CONFIG from the program's environment keeps its other
                // entries. 0 is DXMT's "no cap" and cancels the bottle's.
                builder.merge("DXMT_CONFIG", "d3d11.preferredMaxFrameRate=\(fps ?? 0)", layer: .programUser)
            } else {
                // WineD3D has no frame limiter.
                builder.remove("DXMT_CONFIG", layer: .programUser)
            }
        }

        // Program-specific DLL overrides (structured entries)
        if let dllOverrides = overrides.dllOverrides {
            dllResolver.programCustom.append(contentsOf: dllOverrides)
        }
    }

    /// Where FEX keeps the x86 code it has translated, so later runs skip most JIT work:
    /// `~/Library/Application Support/{bundle-identifier}/FEXCache/`.
    public static let fexCacheFolder = WhiskyWineInstaller.applicationFolder.appending(path: "FEXCache")

    /// Creates the folder FEX writes its code cache to (`FEX_DISKCACHEPATH`) before
    /// Wine starts. Failing to create it is logged: the program still runs, only
    /// without a cache.
    static func ensureFEXCacheFolder() {
        do {
            try FileManager.default.createDirectory(
                at: fexCacheFolder, withIntermediateDirectories: true
            )
        } catch {
            envLogger.error("Could not create the FEX cache folder: \(error.localizedDescription)")
        }
    }

    /// Logs a safe launch summary at info level.
    ///
    /// Only logs the bottle name, active layers, and whitelisted non-sensitive keys.
    /// Does NOT log full environment dict, WINEPREFIX paths, or user-set custom env vars.
    private static func logLaunchSummary(
        bottleName: String,
        provenance: EnvironmentProvenance,
        environment: [String: String]
    ) {
        let layerNames = provenance.activeLayers.sorted().map { layer -> String in
            switch layer {
            case .base: "base"
            case .platform: "platform"
            case .bottleManaged: "bottleManaged"
            case .launcherManaged: "launcherManaged"
            case .gameProfile: "gameProfile"
            case .bottleUser: "bottleUser"
            case .programUser: "programUser"
            case .featureRuntime: "featureRuntime"
            case .callsiteOverride: "callsiteOverride"
            }
        }

        // Non-sensitive keys allowed in the launch summary
        let allowedKeys = [
            "WINEMSYNC", "MTL_HUD_ENABLED"
        ]
        let safeEntries = allowedKeys.compactMap { key -> String? in
            guard let value = environment[key] else { return nil }
            return "\(key)=\(value)"
        }

        let safeValues = safeEntries.isEmpty ? "defaults" : safeEntries.joined(separator: ", ")
        envLogger.info(
            "Launch: bottle=\(bottleName), layers=[\(layerNames.joined(separator: ","))], \(safeValues)"
        )
    }
}

// swiftlint:enable cyclomatic_complexity
// swiftlint:enable function_body_length
