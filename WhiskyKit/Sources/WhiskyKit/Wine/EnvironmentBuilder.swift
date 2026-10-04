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
/// 6. ``bottleUser`` -- User-defined bottle-level environment variables
/// 7. ``programUser`` -- Program settings environment variables and locale
/// 8. ``featureRuntime`` -- Launch-time feature injectors (ClickOnce, one-off modes)
/// 9. ``callsiteOverride`` -- Explicit overrides passed to `Wine.runProgram(environment:)`
public enum EnvironmentLayer: Int, CaseIterable, Comparable, Sendable, Hashable {
    case base = 0
    case platform
    case bottleManaged
    case launcherManaged
    case gameProfile
    case bottleUser
    case programUser
    case featureRuntime
    case callsiteOverride

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

    /// Resolves all layers into a final environment dictionary.
    ///
    /// Layers are processed in order of their raw value (ascending). For each key,
    /// the last layer to set a value wins. Removals are treated as deletions that
    /// override earlier sets.
    ///
    /// - Returns: The resolved environment and every layer that supplied at least one winning value.
    public func resolve() -> (environment: [String: String], activeLayers: Set<EnvironmentLayer>) {
        var environment: [String: String] = [:]
        var winningLayer: [String: EnvironmentLayer] = [:]

        for layer in layers.keys.sorted() {
            for (key, value) in layers[layer] ?? [:] {
                environment[key] = value
                winningLayer[key] = value == nil ? nil : layer
            }
        }

        return (environment, Set(winningLayer.values))
    }
}
