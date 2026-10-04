//
//  LauncherPresets.swift
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

/// Categorizes the type of fix an environment variable override addresses.
///
/// Used by ``LauncherFixDetail`` and ``MacOSFix`` to classify why a particular
/// environment variable is being set, enabling UI display of fix provenance.
public enum FixCategory: String, Codable, CaseIterable, Sendable {
    /// Locale or encoding fixes (LC_ALL, LANG, etc.)
    case locale
    /// Sandbox disablement or security boundary fixes
    case sandbox
    /// Graphics driver or rendering fixes (DXVK, D3D, Metal)
    case graphics
    /// Network timeout or connection pooling fixes
    case network
    /// Thread management, CPU topology, or synchronization fixes
    case threading
    /// General compatibility workarounds
    case compatibility
}

/// Structured metadata for a single launcher-specific environment variable fix.
///
/// Wraps the same key-value pair as ``LauncherType/environmentOverrides()`` but
/// adds a human-readable reason and category for provenance display.
///
/// ## Example
///
/// ```swift
/// let details = LauncherType.steam.fixDetails()
/// for detail in details {
///     print("\(detail.key)=\(detail.value) (\(detail.reason))")
/// }
/// ```
public struct LauncherFixDetail: Sendable {
    /// The environment variable name.
    public let key: String
    /// The environment variable value.
    public let value: String
    /// Human-readable explanation of why this fix is applied.
    public let reason: String
    /// The category of issue this fix addresses.
    public let category: FixCategory
}

/// Represents different game launcher platforms with optimized configurations.
///
/// This enum provides launcher-specific environment variable presets to address
/// compatibility issues documented in frankea/Whisky#41 and ~100 related upstream issues.
///
/// ## Overview
///
/// Game launchers (Steam, Rockstar, EA App, etc.) often have specific requirements
/// for locale settings, sandbox configuration, and graphics drivers. This system
/// applies optimized settings automatically based on launcher type.
///
/// ## Example
///
/// ```swift
/// let launcher = LauncherType.steam
/// let environment = launcher.environmentOverrides()
/// // Returns Steam-specific fixes for steamwebhelper and CEF sandbox
/// ```
///
/// ## Topics
///
/// ### Launcher Types
/// - ``steam``
/// - ``rockstar``
/// - ``eaApp``
/// - ``epicGames``
/// - ``ubisoft``
/// - ``battleNet``
/// - ``paradox``
/// - ``zfGame``
///
/// ### Configuration
/// - ``environmentOverrides()``
/// - ``requiresDXVK``
/// - ``recommendedLocale``
public enum LauncherType: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Valve Steam platform
    case steam = "Steam"
    /// Rockstar Games Launcher
    case rockstar = "Rockstar Games Launcher"
    /// Electronic Arts App (formerly Origin)
    case eaApp = "EA App"
    /// Epic Games Store launcher
    case epicGames = "Epic Games Store"
    /// Ubisoft Connect (formerly Uplay)
    case ubisoft = "Ubisoft Connect"
    /// Blizzard Battle.net launcher
    case battleNet = "Battle.net"
    /// Paradox Launcher
    case paradox = "Paradox Launcher"
    /// ZFGame Browser, the Chromium launcher shell several Chinese publishers ship
    case zfGame = "ZFGame Browser"

    public var id: String {
        rawValue
    }

    /// Display name for the launcher.
    public var displayName: String {
        rawValue
    }

    /// Whether this launcher is known to use the clipboard for multiplayer features.
    public var usesClipboard: Bool {
        switch self {
        case .steam, .epicGames, .battleNet:
            true
        default:
            false
        }
    }

    /// Returns optimized environment variables for this launcher.
    ///
    /// These overrides address specific compatibility issues:
    /// - **Steam**: Fixes steamwebhelper crashes (whisky-app/whisky#946, #1224, #1241) via locale and CEF sandbox
    /// - **Rockstar**: Requires DXVK for logo rendering (whisky-app/whisky#1335, #835)
    /// - **EA App/Epic**: Chromium-based, need sandbox and locale fixes
    /// - **Ubisoft**: Requires D3D11 mode for stability (whisky-app/whisky#1004)
    ///
    /// - Note: For richer metadata including human-readable reasons and categories,
    ///   use ``fixDetails()`` instead.
    ///
    /// - Returns: Dictionary of environment variable key-value pairs
    public func environmentOverrides() -> [String: String] {
        Dictionary(fixDetails().map { ($0.key, $0.value) }, uniquingKeysWith: { $1 })
    }

    /// Indicates whether this launcher requires DXVK to function.
    ///
    /// Some launchers (notably Rockstar) will not render their UI without DXVK enabled.
    public var requiresDXVK: Bool {
        switch self {
        case .rockstar, .zfGame:
            true
        default:
            false
        }
    }

    /// Executables this launcher spawns that must share its DLL overrides.
    ///
    /// `AppDefaults` is per executable with no inheritance, and Steam draws its
    /// client in `steamwebhelper.exe`, so an override on `steam.exe` alone
    /// leaves the window blank. Games a launcher starts are deliberately absent.
    public var helperExecutables: [String] {
        switch self {
        case .steam:
            ["steamwebhelper.exe", "steamservice.exe"]
        case .epicGames:
            ["EpicWebHelper.exe"]
        case .eaApp:
            ["EABackgroundService.exe"]
        case .battleNet:
            ["Battle.net Helper.exe"]
        case .rockstar, .ubisoft, .paradox, .zfGame:
            []
        }
    }

    /// The recommended locale for this launcher.
    ///
    /// Most launchers work best with US English locale to avoid
    /// date/time parsing issues in embedded web views.
    public var recommendedLocale: Locales {
        switch self {
        case .steam, .eaApp, .epicGames, .battleNet:
            .english
        default:
            .auto
        }
    }

    /// User-friendly description of common issues this preset fixes.
    public var fixesDescription: String {
        switch self {
        case .steam:
            "Fixes steamwebhelper crashes, download stalls, and connection issues"
        case .rockstar:
            "Fixes logo freeze and launcher initialization failures"
        case .eaApp:
            "Fixes black screen and GPU detection errors"
        case .epicGames:
            "Fixes launcher UI rendering and web view issues"
        case .ubisoft:
            "Improves launcher stability and game compatibility"
        case .battleNet:
            "Fixes launcher locale and rendering issues"
        case .paradox:
            "Forces D3D11 mode for launcher stability"
        case .zfGame:
            "Fixes the blank launcher window caused by D3DMetal"
        }
    }
}
