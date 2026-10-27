//
//  GameDBEntry.swift
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

// MARK: - Supporting Types

/// Hardware and software constraints for a game configuration.
///
/// Used both for filtering applicable entries and for auto-selecting
/// the best variant for the current machine.
public struct GameConstraints: Codable, Sendable, Equatable {
    /// Supported CPU architectures (e.g., ["arm64", "x86_64"]).
    public var cpuArchitectures: [String]?
    /// Minimum macOS version required (e.g., "15.0.0").
    public var minMacOSVersion: String?
    /// Minimum Wine version required (e.g., "9.0").
    public var minWineVersion: String?
}

/// Information about the environment used to test a game configuration.
///
/// Enables staleness detection by comparing against the user's current setup.
public struct TestedWith: Codable, Sendable, Equatable {
    /// When the configuration was last tested.
    public let lastTestedAt: Date
    /// The macOS version used during testing.
    public let macOSVersion: String
    /// The Wine version used during testing.
    public let wineVersion: String
    /// The Whisky version used during testing, if known.
    public var whiskyVersion: String?
    /// The CPU architecture used during testing (e.g., "arm64").
    public var cpuArchitecture: String?
}

/// A known issue with a game, displayed in the detail view.
public struct KnownIssue: Codable, Sendable, Equatable {
    /// A description of the issue.
    public let description: String
    /// The severity level (e.g., "minor", "major", "critical").
    public var severity: String?
    /// A workaround for the issue, if known.
    public var workaround: String?
}

/// Metadata about who created and last updated a game database entry.
public struct Provenance: Codable, Sendable, Equatable {
    /// The source of the configuration (e.g., "maintainer-verified", "community").
    public let source: String
    /// The author of the configuration.
    public var author: String?
    /// When the entry was last updated.
    public var lastUpdated: Date?
    /// A URL to the source reference (e.g., GitHub issue, wiki page).
    public var referenceURL: URL?
}

// MARK: - Variant Settings

/// Settings values within a game configuration variant.
///
/// Each property maps directly to a ``BottleSettings`` property name,
/// allowing the applicator to set values without a translation layer.
/// All fields are optional; `nil` means "do not change this setting."
public struct GameConfigVariantSettings: Codable, Sendable, Equatable {
    /// The graphics backend to use.
    public let graphicsBackend: GraphicsBackend?
    /// Whether DXVK should be enabled.
    public let dxvk: Bool?
    /// Whether DXVK async shader compilation should be enabled.
    public let dxvkAsync: Bool?
    /// The enhanced sync mode.
    public let enhancedSync: EnhancedSync?
    /// Whether to force D3D11 mode.
    public let forceD3D11: Bool?
    /// Whether shader caching should be enabled.
    public let shaderCacheEnabled: Bool?
    /// Whether AVX instruction set support should be advertised.
    public let avxEnabled: Bool?
    /// The frame rate cap to apply.
    ///
    /// Uncapped rendering is the single biggest avoidable source of GPU power
    /// draw and heat, so an entry can pin a game to a sane cap. The cap only
    /// takes effect on backends that implement one — see
    /// ``GraphicsBackend/supportsFrameRateLimit``.
    public let frameRateLimit: FrameRateLimit?

    public init(
        graphicsBackend: GraphicsBackend? = nil,
        dxvk: Bool? = nil,
        dxvkAsync: Bool? = nil,
        enhancedSync: EnhancedSync? = nil,
        forceD3D11: Bool? = nil,
        shaderCacheEnabled: Bool? = nil,
        avxEnabled: Bool? = nil,
        frameRateLimit: FrameRateLimit? = nil
    ) {
        self.graphicsBackend = graphicsBackend
        self.dxvk = dxvk
        self.dxvkAsync = dxvkAsync
        self.enhancedSync = enhancedSync
        self.forceD3D11 = forceD3D11
        self.shaderCacheEnabled = shaderCacheEnabled
        self.avxEnabled = avxEnabled
        self.frameRateLimit = frameRateLimit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.graphicsBackend = container.decodeLenientIfPresent(GraphicsBackend.self, forKey: .graphicsBackend)
        self.dxvk = try container.decodeIfPresent(Bool.self, forKey: .dxvk)
        self.dxvkAsync = try container.decodeIfPresent(Bool.self, forKey: .dxvkAsync)
        // EnhancedSync uses Swift's auto-synthesized Codable (keyed enum, not String raw value).
        // The JSON database uses plain strings ("none", "esync", "msync") for readability,
        // so we try String first and fall back to the native Codable format.
        if let syncString = try container.decodeIfPresent(String.self, forKey: .enhancedSync) {
            switch syncString {
            // Spelled out: on this Optional, a bare `.none` is nil, not sync off.
            case "none": self.enhancedSync = EnhancedSync.none
            case "esync": self.enhancedSync = .esync
            case "msync": self.enhancedSync = .msync
            default: self.enhancedSync = nil
            }
        } else {
            self.enhancedSync = try container.decodeIfPresent(EnhancedSync.self, forKey: .enhancedSync)
        }
        self.forceD3D11 = try container.decodeIfPresent(Bool.self, forKey: .forceD3D11)
        self.shaderCacheEnabled = try container.decodeIfPresent(Bool.self, forKey: .shaderCacheEnabled)
        self.avxEnabled = try container.decodeIfPresent(Bool.self, forKey: .avxEnabled)
        // FrameRateLimit accepts either its integer raw value (60) or a readable
        // string ("60", "unlimited", "matchDisplay"), since the database is
        // hand-edited JSON. An unrecognised value decodes to nil — "do not
        // change this setting" — rather than failing the whole entry.
        if let raw = try? container.decodeIfPresent(Int.self, forKey: .frameRateLimit) {
            self.frameRateLimit = FrameRateLimit(rawValue: raw)
        } else if let name = try? container.decodeIfPresent(String.self, forKey: .frameRateLimit) {
            switch name {
            case "unlimited": self.frameRateLimit = .unlimited
            case "matchDisplay", "match-display": self.frameRateLimit = .matchDisplay
            default: self.frameRateLimit = Int(name).flatMap(FrameRateLimit.init(rawValue:))
            }
        } else {
            self.frameRateLimit = nil
        }
    }
}

// MARK: - Game Config Variant

/// A specific configuration variant for a game.
///
/// A single game entry can have multiple variants (e.g., "Apple Silicon",
/// "Intel", "DXVK mode"). Each variant contains the full set of settings
/// to apply, along with metadata about when and why to use it.
public struct GameConfigVariant: Codable, Sendable, Equatable {
    /// Stable identifier for this variant.
    public let id: String
    /// A human-readable label (e.g., "Recommended (Apple Silicon)").
    public let label: String
    /// Whether this is the default variant. The first variant with
    /// `isDefault == true` is auto-selected; if none, the first variant is used.
    public var isDefault: Bool?
    /// A description of when this variant should be used.
    public var whenToUse: String?
    /// Explanation of why these settings are recommended.
    public var rationale: [String]?
    /// The settings to apply for this variant.
    public let settings: GameConfigVariantSettings
    /// Additional environment variables to set (not covered by named settings).
    public var environmentVariables: [String: String]?
    /// DLL overrides to add when applying this variant.
    public var dllOverrides: [DLLOverrideEntry]?
    /// Winetricks verbs required by this variant.
    public var winetricksVerbs: [String]?
    /// Information about when and how this variant was tested.
    public var testedWith: TestedWith?
}

// MARK: - Game Database Entry

/// A single entry in the game compatibility database.
///
/// Each entry describes a game, its compatibility rating, matching
/// identifiers (Steam App ID, exe names, fingerprints), and one or
/// more configuration variants with recommended settings.
///
/// ## Example JSON
///
/// ```json
/// {
///   "id": "elden-ring",
///   "title": "Elden Ring",
///   "rating": "playable",
///   "variants": [{ "id": "recommended", "label": "Recommended", "settings": {} }]
/// }
/// ```
public struct GameDBEntry: Codable, Sendable, Equatable {
    /// Stable identifier for this entry.
    public let id: String
    /// The display title of the game.
    public let title: String
    /// Alternative names for search matching.
    public var aliases: [String]?
    /// A subtitle (e.g., edition or publisher).
    public var subtitle: String?
    /// The store this game is associated with (e.g., "steam", "gog").
    public var store: String?
    /// The Steam App ID, if the game is on Steam.
    public var steamAppId: Int?
    /// The compatibility rating for this game.
    public let rating: CompatibilityRating
    /// Known executable filenames for matching.
    public var exeNames: [String]?
    /// Path patterns for heuristic matching (e.g., "elden ring/game").
    public var pathPatterns: [String]?
    /// Anti-cheat system name, if applicable.
    public var antiCheat: String?
    /// Hardware and software constraints.
    public var constraints: GameConstraints?
    /// Configuration variants (at least one required).
    public let variants: [GameConfigVariant]
    /// General notes displayed in the detail view.
    public var notes: [String]?
    /// Known issues with workarounds.
    public var knownIssues: [KnownIssue]?
    /// Provenance metadata (source, author, last updated).
    public var provenance: Provenance?

    /// The default configuration variant for this entry.
    ///
    /// Returns the first variant where ``GameConfigVariant/isDefault`` is `true`.
    /// If no variant is marked as default, returns the first variant.
    /// Returns `nil` only if the variants array is empty.
    public var defaultVariant: GameConfigVariant? {
        variants.first { $0.isDefault == true } ?? variants.first
    }
}
