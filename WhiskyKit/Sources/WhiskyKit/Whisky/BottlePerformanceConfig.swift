//
//  BottlePerformanceConfig.swift
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

/// Performance optimization presets for games
public enum PerformancePreset: String, Codable, CaseIterable, Sendable {
    case balanced
    case performance
    case quality
    case unity // Optimized for Unity games

    public func description() -> String {
        switch self {
        case .balanced:
            "Balanced (Default)"
        case .performance:
            "Performance Mode"
        case .quality:
            "Quality Mode"
        case .unity:
            "Unity Games Optimized"
        }
    }
}

public struct BottlePerformanceConfig: Codable, Equatable {
    var performancePreset: PerformancePreset = .balanced
    var shaderCacheEnabled: Bool = true
    var forceD3D11: Bool = false // Force D3D11 instead of D3D12 for compatibility
    var vcRedistInstalled: Bool = false // Track if VC++ runtime is installed
    // Default on: App Nap demotes an occluded Wine process to the efficiency
    // cores and coalesces its timers — for a game that is frame pacing ruin.
    // Existing bottles keep whatever they have stored: the per-key decode
    // fallback stays false, and a bottle whose plist predates this struct
    // entirely decodes through `legacyDecodeDefault` below.
    var disableAppNap: Bool = true

    /// The value an existing bottle gets when its plist has no
    /// `performanceConfig` block at all. The memberwise default above is for
    /// new bottles; using it as the decode fallback would silently flip
    /// `disableAppNap` on for every pre-existing bottle from older builds.
    static var legacyDecodeDefault: BottlePerformanceConfig {
        var config = BottlePerformanceConfig()
        config.disableAppNap = false
        return config
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.performancePreset = container
            .decodeLenientIfPresent(PerformancePreset.self, forKey: .performancePreset) ?? .balanced
        self.shaderCacheEnabled = try container.decodeIfPresent(Bool.self, forKey: .shaderCacheEnabled) ?? true
        self.forceD3D11 = try container.decodeIfPresent(Bool.self, forKey: .forceD3D11) ?? false
        self.vcRedistInstalled = try container.decodeIfPresent(Bool.self, forKey: .vcRedistInstalled) ?? false
        self.disableAppNap = try container.decodeIfPresent(Bool.self, forKey: .disableAppNap) ?? false
    }
}
