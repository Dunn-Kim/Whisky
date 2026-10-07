//
//  BottleDependencyConfig.swift
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

// MARK: - Dependency Definition

/// Maps a user-facing dependency name to its underlying winetricks verbs.
///
/// Each definition represents a logical component that may require one or
/// more winetricks verbs to install. The ``standardDependencies`` list
/// provides the default set of dependencies shown in the bottle configuration.
///
/// ## Example
///
/// ```swift
/// let vcRuntime = DependencyDefinition.standardDependencies.first { $0.id == "vcruntime" }
/// // vcRuntime?.displayName == "Visual C++ Runtime"
/// // vcRuntime?.winetricksVerbs == ["vcrun2019"]
/// ```
public struct DependencyDefinition: Codable, Identifiable, Sendable {
    /// Stable identifier (e.g. "vcruntime", "dotnet48", "directx").
    public let id: String
    /// Human-readable name shown in the UI (e.g. "Visual C++ Runtime").
    public let displayName: String
    /// Brief explanation of what this dependency provides.
    public let description: String
    /// The winetricks verb names required to install this dependency.
    public let winetricksVerbs: [String]
    /// Rough time estimate for installation, shown in the UI.
    public let estimatedInstallMinutes: Int

    public init(
        id: String,
        displayName: String,
        description: String,
        winetricksVerbs: [String],
        estimatedInstallMinutes: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.winetricksVerbs = winetricksVerbs
        self.estimatedInstallMinutes = estimatedInstallMinutes
    }
}

extension DependencyDefinition {
    /// The default set of dependencies shown in the bottle configuration UI.
    ///
    /// Each entry maps a user-facing name to one or more winetricks verbs.
    /// The list covers the most commonly needed Windows components for
    /// games and applications running under Wine.
    public static let standardDependencies: [DependencyDefinition] = [
        DependencyDefinition(
            id: "vcruntime",
            displayName: "Visual C++ Runtime",
            description: "Required by most Windows games and applications",
            winetricksVerbs: ["vcrun2019"],
            estimatedInstallMinutes: 2
        ),
        DependencyDefinition(
            id: "dotnet48",
            displayName: ".NET Framework 4.8",
            description: "Required by .NET applications and some game launchers",
            winetricksVerbs: ["dotnet48"],
            estimatedInstallMinutes: 10
        ),
        DependencyDefinition(
            id: "directx",
            displayName: "DirectX Runtime",
            description: "DirectX 9/10/11 components for older games",
            winetricksVerbs: ["d3dx9", "d3dcompiler_47"],
            estimatedInstallMinutes: 3
        ),
        DependencyDefinition(
            id: "directx_audio",
            displayName: "DirectX Audio",
            description: "XACT audio framework for games using DirectX audio",
            winetricksVerbs: ["xact"],
            estimatedInstallMinutes: 2
        )
    ]
}

// MARK: - Dependency Confidence

/// Indicates how the installed status of a dependency was determined.
///
/// Higher confidence levels indicate more reliable detection methods.
/// The UI can use this to show appropriate caveats for lower-confidence results.
public enum DependencyConfidence: String, Codable, Sendable {
    /// Status determined by `winetricks list-installed` (most reliable).
    case authoritative
    /// Status read from the ``WinetricksVerbCache`` plist (reliable if fresh).
    case cached
    /// Status inferred from DLL presence or registry probes (best-effort).
    case heuristic
}

// MARK: - Install Status

/// The installation state of a dependency's winetricks verbs.
///
/// A dependency with multiple verbs can be partially installed if some
/// verbs are present and others are missing.
public enum DependencyInstallStatus: Codable, Sendable, Equatable {
    /// All required verbs are installed.
    case installed
    /// No required verbs are installed.
    case notInstalled
    /// Some verbs are installed and some are missing.
    case partiallyInstalled(installed: [String], missing: [String])
    /// Installation status could not be determined.
    case unknown
}

// MARK: - Dependency Status

/// The current status of a single dependency within a bottle.
///
/// Combines the static ``DependencyDefinition`` with runtime status
/// information including when the status was last checked and how
/// confident the detection result is.
public struct DependencyStatus: Identifiable, Sendable {
    /// Matches the ``DependencyDefinition/id`` of the associated definition.
    public let id: String
    /// The dependency definition this status describes.
    public let definition: DependencyDefinition
    /// The current installation state.
    public let status: DependencyInstallStatus
    /// When this status was last verified, if known.
    public let lastChecked: Date?
    /// How the status was determined.
    public let confidence: DependencyConfidence

    public init(
        id: String,
        definition: DependencyDefinition,
        status: DependencyInstallStatus,
        lastChecked: Date?,
        confidence: DependencyConfidence
    ) {
        self.id = id
        self.definition = definition
        self.status = status
        self.lastChecked = lastChecked
        self.confidence = confidence
    }
}
