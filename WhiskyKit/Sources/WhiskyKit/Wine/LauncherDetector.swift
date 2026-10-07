//
//  LauncherDetector.swift
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

public extension LauncherType {
    /// Detects a known launcher from an executable's filename and path.
    ///
    /// Detection is case-insensitive and purely string-based. Executables
    /// under `steamapps/common` are games bought on Steam, not the Steam
    /// client: they skip the Steam check and fall through to the other
    /// launcher heuristics (a Rockstar title in a Steam library still
    /// detects Rockstar), otherwise detecting as no launcher at all.
    ///
    /// - Parameter url: The URL to the Windows executable file.
    /// - Returns: The detected launcher type, or `nil` if no launcher detected.
    static func detect(from url: URL) -> LauncherType? {
        let filename = url.lastPathComponent.lowercased()
        let path = url.path.lowercased()

        // Steam detection: the client's own executables or anything else at
        // the Steam root — but never the games in its libraries.
        let isSteamLibraryGame = path.contains("steamapps/common") || path.contains("steamapps\\common")
        if !isSteamLibraryGame,
           filename.contains("steam") || path.contains("/steam/") || path.contains("\\steam\\") {
            return .steam
        }

        // Rockstar Games Launcher detection
        // Be specific about generic "launcher.exe" to avoid false positives
        if filename.contains("rockstar") ||
            filename.contains("launcherpatcher") ||
            path.contains("rockstar games") ||
            (filename == "launcher.exe" && path.contains("social club")) {
            return .rockstar
        }

        // EA App / Origin detection
        if filename.contains("eadesktop") ||
            filename.contains("eaapp") ||
            filename.contains("origin.exe") ||
            path.contains("/ea app/") ||
            path.contains("\\ea app\\") ||
            path.contains("/origin/") {
            return .eaApp
        }

        // Epic Games Store detection
        if filename.contains("epicgames") ||
            filename.contains("epiclauncher") ||
            filename.contains("epicwebhelper") ||
            path.contains("/epic games/") ||
            path.contains("\\epic games\\") {
            return .epicGames
        }

        // Ubisoft Connect detection
        if filename.contains("ubisoft") ||
            filename.contains("uplay") ||
            filename.contains("upc.exe") ||
            path.contains("/ubisoft") {
            return .ubisoft
        }

        // Battle.net detection
        if filename.contains("battle.net") ||
            filename.contains("battlenet") ||
            path.contains("/battle.net/") ||
            path.contains("\\battle.net\\") {
            return .battleNet
        }

        // Paradox Launcher detection
        // Be specific to avoid false positives
        if filename.contains("paradoxlauncher") ||
            path.contains("paradox launcher") ||
            ((filename == "launcher.exe" || filename == "launcher") &&
                path.contains("paradox interactive")) {
            return .paradox
        }

        // ZFGame Browser detection
        // Matters for more than presets: an undetected Chromium launcher
        // resolves to D3DMetal, where its window comes up and never paints.
        if filename.contains("zfgame") ||
            path.contains("/zfgame/") ||
            path.contains("\\zfgame\\") {
            return .zfGame
        }

        return nil
    }
}
