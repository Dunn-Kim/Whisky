//
//  LauncherDetectionTests.swift
//  WhiskyKitTests
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

@testable import WhiskyKit
import XCTest

/// Comprehensive tests for launcher detection heuristics.
///
/// These tests verify the critical detection logic that determines which
/// launcher-specific fixes to apply. Incorrect detection could result in:
/// - Applying wrong fixes (degraded performance)
/// - Missing required fixes (launcher won't work)
/// - False positives (non-launcher apps get launcher fixes)
final class LauncherDetectionTests: XCTestCase {
    private func detect(_ path: String) -> LauncherType? {
        LauncherType.detect(from: URL(fileURLWithPath: path))
    }

    func testDetectsLauncherFromPath() {
        let cases: [(path: String, launcher: LauncherType)] = [
            // Steam, including case-insensitivity, bare filename and Windows/Unix/mixed separators
            ("C:/Program Files (x86)/Steam/steam.exe", .steam),
            ("C:/SomeFolder/steam.exe", .steam),
            ("C:/Program Files/Steam/bin/steamwebhelper.exe", .steam),
            ("C:/Steam/steamservice.exe", .steam),
            ("C:/STEAM/STEAM.EXE", .steam),
            ("C:\\Program Files\\Steam\\steam.exe", .steam),
            ("/drive_c/Program Files/Steam/steam.exe", .steam),
            ("steam.exe", .steam),
            ("D:/SteamLibrary/steam.exe", .steam),
            // Rockstar needs "rockstar games" / "social club" / its own filenames
            ("C:/Program Files/Rockstar Games/Launcher/Launcher.exe", .rockstar),
            ("C:/Games/RockstarLauncher.exe", .rockstar),
            ("C:/Games/Rockstar/LauncherPatcher.exe", .rockstar),
            ("C:/Program Files/Rockstar Games/Social Club/Launcher.exe", .rockstar),
            ("C:/Rockstar Games/Social Club/Launcher.exe", .rockstar),
            ("C:/Program Files/Rockstar Games Launcher/Launcher.exe", .rockstar),
            ("C:/Program Files\\Rockstar Games/Launcher.exe", .rockstar),
            // EA App / Origin
            ("C:/Program Files/Electronic Arts/EA Desktop/EA App/EADesktop.exe", .eaApp),
            ("C:/Games/EADesktop.exe", .eaApp),
            ("C:/EAApp.exe", .eaApp),
            ("C:/Program Files (x86)/Origin/Origin.exe", .eaApp),
            // Epic
            ("C:/Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe", .epicGames),
            ("C:/Games/EpicGamesLauncher.exe", .epicGames),
            ("C:/Epic Games/Launcher/EpicWebHelper.exe", .epicGames),
            // Ubisoft
            ("C:/Program Files (x86)/Ubisoft/Ubisoft Game Launcher/UbisoftConnect.exe", .ubisoft),
            ("C:/Program Files/Ubisoft/Uplay/upc.exe", .ubisoft),
            ("C:/Games/uplay.exe", .ubisoft),
            // Battle.net (dots in the name)
            ("C:/Program Files (x86)/Battle.net/Battle.net.exe", .battleNet),
            ("C:/BattleNet/battlenet.exe", .battleNet),
            ("C:/Games/Battle.net Launcher.exe", .battleNet),
            // Paradox
            ("C:/Users/User/AppData/Local/Programs/Paradox Launcher/Paradox Launcher.exe", .paradox),
            ("C:/Paradox Launcher/Launcher.exe", .paradox),
            ("C:/Program Files/Paradox Interactive/Launcher/Launcher.exe", .paradox),
            // ZFGame Browser
            ("C:/Program Files/Mecharashi/ZFGameBrowser.exe", .zfGame),
            ("C:/Games/ZFGame/launcher.exe", .zfGame),
            // A launcher-shipping title inside a Steam library still detects its own launcher
            ("C:/Program Files (x86)/Steam/steamapps/common/Grand Theft Auto V/LauncherPatcher.exe", .rockstar)
        ]
        for (path, launcher) in cases {
            XCTAssertEqual(detect(path), launcher, "Path '\(path)'")
        }
    }

    func testDoesNotDetectLauncherFromUnrelatedPath() {
        let paths = [
            // Generic launcher.exe needs a Rockstar path to count
            "C:/Program Files/SomeGame/Launcher.exe",
            "C:/Program Files/MyLauncher/Launcher.exe",
            "C:/Games/CustomLauncher/Launcher.exe",
            "C:/Launcher.exe",
            "C:/rock/Launcher.exe",
            // Games, not clients
            "C:/Games/Paradox Interactive/Europa Universalis/game.exe",
            "C:/Program Files/MyGame/game.exe",
            "C:/Windows/System32/notepad.exe",
            "C:/Program Files/Firefox/firefox.exe",
            "C:/Games/CustomLauncher/app.exe",
            "C:/Users/User/Desktop/installer.exe",
            "C:/Games/Steamworld/game.exe",
            // Exes under steamapps/common are games bought on Steam, not the client
            "C:/Program Files (x86)/Steam/steamapps/common/Casualties Unknown Demo/CasualtiesUnknown.exe",
            "C:/Steam/steamapps/common/game/steam_api.dll",
            "D:/SteamLibrary/steamapps/common/ELDEN RING/eldenring.exe",
            "",
            "/"
        ]
        for path in paths {
            XCTAssertNil(detect(path), "Path '\(path)'")
        }
    }

    /// The point of detecting it at all: the resolver only steers a client away
    /// from D3DMetal when it knows the client is a launcher.
    func testZFGameBrowserResolvesToDXVK() {
        let backend = GraphicsBackendResolver.resolve(for: .zfGame, d3dMetalInstalled: true)
        XCTAssertEqual(backend, .dxvk, "ZFGame Browser is Chromium and never paints on D3DMetal")
    }
}
