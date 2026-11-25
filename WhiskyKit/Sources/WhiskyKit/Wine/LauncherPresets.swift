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
    /// Graphics driver or rendering fixes (D3D, Metal)
    case graphics
    /// Network timeout or connection pooling fixes
    case network
    /// Thread management, CPU topology, or synchronization fixes
    case threading
    /// General compatibility workarounds
    case compatibility

    /// Localized name of the category for display in the UI.
    public var displayName: String {
        switch self {
        case .locale:
            String(localized: "locale.title")
        case .sandbox:
            String(localized: "launcher.fixCategory.sandbox")
        case .graphics:
            String(localized: "config.title.graphics")
        case .network:
            String(localized: "launcher.fixCategory.network")
        case .threading:
            String(localized: "launcher.fixCategory.threading")
        case .compatibility:
            String(localized: "launcher.fixCategory.compatibility")
        }
    }
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
/// - ``rsiLauncher``
///
/// ### Configuration
/// - ``environmentOverrides()``
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
    /// RSI Launcher (Cloud Imperium's Electron launcher for Star Citizen)
    case rsiLauncher = "RSI Launcher"

    public var id: String {
        rawValue
    }

    /// Display name for the launcher.
    public var displayName: String {
        switch self {
        case .steam:
            "Steam"
        case .rockstar:
            "Rockstar Games Launcher"
        case .eaApp:
            "EA App"
        case .epicGames:
            "Epic Games Store"
        case .ubisoft:
            "Ubisoft Connect"
        case .battleNet:
            "Battle.net"
        case .paradox:
            "Paradox Launcher"
        case .zfGame:
            "ZFGame Browser"
        case .rsiLauncher:
            "RSI Launcher"
        }
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
    /// - **Steam**: Fixes steamwebhelper crashes by disabling its CEF sandbox
    /// - **Rockstar**: Locale and address-space fixes (whisky-app/whisky#1335, #835)
    /// - **EA App/Epic**: Chromium-based, need sandbox and locale fixes
    ///
    /// - Note: For richer metadata including human-readable reasons and categories,
    ///   use ``fixDetails()`` instead.
    ///
    /// - Returns: Dictionary of environment variable key-value pairs
    public func environmentOverrides() -> [String: String] {
        var env: [String: String] = [:]

        switch self {
        case .steam:
            // No locale: steamwebhelper starts and signs in under German and
            // Japanese on both the stable and the beta engines, so Auto leaves
            // the locale of Steam and its games to the Mac (#330). Steam's own
            // interface language is its setting, picked from the locale on install.

            // Note: CEF_DISABLE_SANDBOX is set globally in MacOSCompatibility.swift
            // for all launchers. We only set Steam-specific variant here.
            env["STEAM_DISABLE_CEF_SANDBOX"] = "1"

            // Steam Runtime causes issues under Wine
            env["STEAM_RUNTIME"] = "0"

        case .rockstar:
            // Rockstar Launcher fixes (whisky-app/whisky#1335, #835, #1120)

            // Note: CEF_DISABLE_SANDBOX is set globally in MacOSCompatibility.swift.
            // No large-address-aware variable: no runtime reads one, and the
            // launcher is 64-bit anyway.

            // Locale for launcher UI
            env["LC_ALL"] = "en_US.UTF-8"

        case .eaApp:
            // EA App (formerly Origin) fixes (whisky-app/whisky#1195, #1322)
            // Note: CEF_DISABLE_SANDBOX is set globally in MacOSCompatibility.swift
            env["LC_ALL"] = "en_US.UTF-8"
            env["LANG"] = "en_US.UTF-8"

        case .epicGames:
            // Epic Games Store launcher fixes
            // Note: CEF_DISABLE_SANDBOX is set globally in MacOSCompatibility.swift
            env["LC_ALL"] = "en_US.UTF-8"

        case .ubisoft:
            // No environment fix: the Anno 1800 workaround (whisky-app/whisky#1004)
            // only set a variable no runtime reads any more.
            break

        case .battleNet:
            // Blizzard Battle.net launcher
            // Note: CEF_DISABLE_SANDBOX is set globally in MacOSCompatibility.swift
            env["LC_ALL"] = "en_US.UTF-8"

        case .paradox:
            // No environment fix: the old resource lookup workaround
            // (whisky-app/whisky#1091) set a variable no runtime reads.
            break

        case .zfGame:
            // ZFGame Browser is Chromium-based. No locale override on purpose:
            // these launchers render a CJK UI, and forcing en_US replaces their
            // text with boxes.
            break

        case .rsiLauncher:
            // No environment fix: anything set here would reach the bottle's
            // environment, and so Star Citizen as well.
            break
        }

        return env
    }

    /// Executables this launcher spawns that must share its DLL overrides.
    ///
    /// `AppDefaults` is per executable with no inheritance, and Steam draws its
    /// client in `steamwebhelper.exe`, so an override on `steam.exe` alone
    /// leaves the window blank. Games a launcher starts are deliberately absent.
    ///
    /// Steam's overlay process is on the list because it draws the in-game
    /// overlay with Direct3D in a process of its own, beside the game. Current clients
    /// ship it as `gameoverlayui64.exe` only; `GameOverlayUI.exe` is the name older
    /// ones used. Helpers that draw nothing (`steamerrorreporter.exe`,
    /// `steam_monitor.exe`) run on the bottle's backend unharmed.
    public var helperExecutables: [String] {
        switch self {
        case .steam:
            ["steamwebhelper.exe", "steamservice.exe", "gameoverlayui64.exe", "GameOverlayUI.exe"]
        case .epicGames:
            ["EpicWebHelper.exe"]
        case .eaApp:
            ["EABackgroundService.exe"]
        case .battleNet:
            ["Battle.net Helper.exe"]
        case .rockstar, .ubisoft, .paradox, .zfGame:
            []
        case .rsiLauncher:
            // Its Chromium processes (gpu-process, renderer, utility) run as
            // `RSI Launcher.exe` itself, so the launched executable's own entry
            // covers them. StarCitizen.exe is a game, and stays off the list.
            []
        }
    }

    /// The recommended locale for this launcher.
    ///
    /// EA App, Epic Games, and Battle.net keep US English for their embedded
    /// web views. Steam needs none: its web helper runs under other locales
    /// (#330).
    public var recommendedLocale: Locales {
        switch self {
        case .eaApp, .epicGames, .battleNet:
            .english
        default:
            .auto
        }
    }

    /// Localized description of common issues this preset fixes, for display in the UI.
    public var fixesDescription: String {
        switch self {
        case .steam:
            String(localized: "launcher.fixes.description.steam")
        case .rockstar:
            String(localized: "launcher.fixes.description.rockstar")
        case .eaApp:
            String(localized: "launcher.fixes.description.eaApp")
        case .epicGames:
            String(localized: "launcher.fixes.description.epicGames")
        case .ubisoft:
            String(localized: "launcher.fixes.description.ubisoft")
        case .battleNet:
            String(localized: "launcher.fixes.description.battleNet")
        case .paradox:
            String(localized: "launcher.fixes.description.paradox")
        case .zfGame:
            String(localized: "launcher.fixes.description.zfGame")
        case .rsiLauncher:
            String(localized: "launcher.fixes.description.rsiLauncher")
        }
    }
}
