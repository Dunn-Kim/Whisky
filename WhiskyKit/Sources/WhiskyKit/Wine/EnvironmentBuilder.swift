//
//  EnvironmentBuilder.swift
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

/// A layer in the environment variable cascade.
///
/// Layers are ordered by priority: later layers (higher raw value) override
/// earlier layers when they set the same key. This provides a deterministic
/// resolution order for environment variables from multiple sources.
///
/// ## Layer Order
///
/// 1. ``base`` -- WINEPREFIX, default WINEDEBUG, PATH-related defaults
/// 2. ``platform`` -- macOS compatibility fixes
/// 3. ``bottleManaged`` -- Toggles/presets Whisky owns (DXVK, Metal, sync, performance)
/// 4. ``launcherManaged`` -- Launcher compatibility mode and detected overrides
/// 5. ``gameProfile`` -- GameDB variant environment applied for a single launch
/// 6. ``programUser`` -- Program settings environment variables and locale
/// 7. ``featureRuntime`` -- Launch-time feature injectors (one-off diagnostic modes)
public enum EnvironmentLayer: Int, CaseIterable, Comparable, Sendable, Hashable {
    case base = 0
    case platform
    case bottleManaged
    case launcherManaged
    case gameProfile
    case programUser
    case featureRuntime

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Builds the Wine environment by collecting entries from ordered layers.
///
/// `EnvironmentBuilder` accumulates environment variable entries across multiple
/// layers. When resolved, later layers win per-key, producing the final
/// environment dictionary and the layers that contributed to it, for logging.
///
/// ## Example
///
/// ```swift
/// var builder = EnvironmentBuilder()
/// builder.set("WINEPREFIX", bottlePath, layer: .base)
/// builder.set("DXVK_ASYNC", "1", layer: .bottleManaged)
/// builder.set("DXVK_ASYNC", "0", layer: .programUser)
/// let result = builder.resolve()
/// // result.environment["DXVK_ASYNC"] == "0" (programUser wins)
/// ```
public struct EnvironmentBuilder: Sendable {
    /// Per-layer storage of key-value entries; a `nil` value marks a removal.
    private var layers: [EnvironmentLayer: [String: String?]] = [:]

    /// Creates a new empty environment builder.
    public init() {}

    /// Sets an environment variable in the specified layer.
    ///
    /// - Parameters:
    ///   - key: The environment variable name.
    ///   - value: The value to set.
    ///   - layer: The layer that owns this entry.
    public mutating func set(_ key: String, _ value: String, layer: EnvironmentLayer) {
        layers[layer, default: [:]][key] = value
    }

    /// Marks an environment variable for removal in the specified layer.
    ///
    /// When resolved, this removal takes effect at the layer's priority.
    /// A higher layer can still set the key after removal.
    ///
    /// - Parameters:
    ///   - key: The environment variable name to remove.
    ///   - layer: The layer that requests removal.
    public mutating func remove(_ key: String, layer: EnvironmentLayer) {
        layers[layer, default: [:]][key] = nil as String?
    }

    /// Variables whose value is a DXVK-style `name=value;name=value` list.
    ///
    /// Layers merge these per entry instead of replacing the whole value, so a
    /// program's own `DXMT_CONFIG` keeps the bottle's frame cap and the reverse.
    static let listKeys: Set<String> = ["DXMT_CONFIG"]

    /// Merges `entries` into the list `key` holds in `layer`; an entry whose
    /// name is already there replaces it.
    public mutating func merge(_ key: String, _ entries: String, layer: EnvironmentLayer) {
        let current = layers[layer]?[key] ?? nil
        layers[layer, default: [:]][key] = Self.mergeList(current, entries)
    }

    /// Joins two `name=value;...` lists, keeping first-seen order and letting
    /// `overlay` win for a name both contain.
    static func mergeList(_ base: String?, _ overlay: String) -> String {
        var names: [String] = []
        var entries: [String: String] = [:]
        for part in [base ?? "", overlay].joined(separator: ";").split(separator: ";") {
            let entry = part.trimmingCharacters(in: .whitespaces)
            guard !entry.isEmpty else { continue }
            let name = String(entry.prefix { $0 != "=" }).trimmingCharacters(in: .whitespaces)
            if entries[name] == nil {
                names.append(name)
            }
            entries[name] = entry
        }
        return names.compactMap { entries[$0] }.joined(separator: ";")
    }

    /// Resolves all layers into a final environment dictionary.
    ///
    /// Layers are processed in order of their raw value (ascending). For each key,
    /// the last layer to set a value wins, except that ``listKeys`` merge per
    /// entry. Removals are treated as deletions that override earlier sets.
    ///
    /// - Returns: The resolved environment and every layer that supplied at least one winning value.
    public func resolve() -> (environment: [String: String], activeLayers: Set<EnvironmentLayer>) {
        var environment: [String: String] = [:]
        var winningLayer: [String: EnvironmentLayer] = [:]

        for layer in layers.keys.sorted() {
            for (key, value) in layers[layer] ?? [:] {
                if let value, Self.listKeys.contains(key), let earlier = environment[key] {
                    environment[key] = Self.mergeList(earlier, value)
                } else {
                    environment[key] = value
                }
                winningLayer[key] = value == nil ? nil : layer
            }
        }

        return (environment, Set(winningLayer.values))
    }
}

// MARK: - Settings written identically by the bottle and program layers

extension EnvironmentBuilder {
    mutating func setEnhancedSync(_ mode: EnhancedSync, layer: EnvironmentLayer) {
        switch mode {
        case .none:
            // On macOS 15.4+, ESYNC is required for stability
            if MacOSVersion.current < .sequoia15_4 {
                remove("WINEESYNC", layer: layer)
            } else {
                set("WINEESYNC", "1", layer: layer)
            }
            remove("WINEMSYNC", layer: layer)
        case .esync:
            set("WINEESYNC", "1", layer: layer)
            remove("WINEMSYNC", layer: layer)
        case .msync:
            // D3DM detects ESYNC and changes behaviour accordingly, so lie to it
            // under MSYNC. Values hardcoded in lid3dshared.dylib
            set("WINEMSYNC", "1", layer: layer)
            set("WINEESYNC", "1", layer: layer)
        }
    }

    /// SDL controller hints. `buttonLabels` picks `1` (labels) or `0` (XInput mapping).
    mutating func setSDLInputHints(
        disableHIDAPI: Bool, allowBackgroundEvents: Bool, buttonLabels: Bool, layer: EnvironmentLayer
    ) {
        if disableHIDAPI {
            set("SDL_JOYSTICK_HIDAPI", "0", layer: layer)
        }
        if allowBackgroundEvents {
            set("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", "1", layer: layer)
        }
        set("SDL_GAMECONTROLLER_USE_BUTTON_LABELS", buttonLabels ? "1" : "0", layer: layer)
    }
}
