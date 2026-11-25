//
//  LauncherFixesTests.swift
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

import Foundation
@testable import WhiskyKit
import XCTest

// MARK: - Fixtures

/// Shared temp-dir bottle fixture backed by a real `Metadata.plist`, so the
/// persistence behavior of the fix application (saves synchronously, or must
/// not save at all) is observable on disk.
class LauncherFixesTestCase: XCTestCase {
    /// A URL that ``LauncherType/detect(from:)`` resolves to Steam.
    let steamExe = URL(fileURLWithPath: "C:/Program Files (x86)/Steam/steam.exe")
    /// A URL that resolves to no launcher at all.
    let plainExe = URL(fileURLWithPath: "C:/Program Files/SomeGame/game.exe")

    var tempDir: URL!
    var bottleURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "launcher_fixes_\(UUID().uuidString)")
        bottleURL = tempDir.appending(path: "Bottle")
        try? FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Creates the bottle; the initializer writes the initial `Metadata.plist`.
    @MainActor
    func makeBottle() -> Bottle {
        Bottle(bottleUrl: bottleURL)
    }

    var metadataURL: URL {
        bottleURL.appending(path: "Metadata.plist")
    }

    /// Decodes the settings currently persisted for the bottle.
    func persistedSettings() throws -> BottleSettings {
        try BottleSettings.decode(from: metadataURL)
    }
}

// MARK: - detectAndApply gating

final class LauncherFixesGatingTests: LauncherFixesTestCase {
    @MainActor
    func testManualModeLeavesEverySettingUntouched() throws {
        let bottle = makeBottle()
        bottle.settings.launcherCompatibilityMode = true
        bottle.settings.launcherMode = .manual
        let snapshot = bottle.settings
        let persistedBefore = try persistedSettings()

        XCTAssertFalse(LauncherFixes.detectAndApply(from: steamExe, for: bottle))

        XCTAssertEqual(bottle.settings, snapshot)
        XCTAssertEqual(try persistedSettings(), persistedBefore)
        XCTAssertNil(bottle.settings.detectedLauncher)
    }

    @MainActor
    func testCompatibilityModeOffIsNotEnabledByDetection() throws {
        // detectAndApply only refines within an already-enabled compatibility
        // mode; it never flips the master switch (that is apply's caller's
        // decision, see the Steam orchestrator).
        let bottle = makeBottle()
        let snapshot = bottle.settings
        XCTAssertFalse(snapshot.launcherCompatibilityMode)

        XCTAssertFalse(LauncherFixes.detectAndApply(from: steamExe, for: bottle))

        XCTAssertEqual(bottle.settings, snapshot)
        XCTAssertFalse(try persistedSettings().launcherCompatibilityMode)
        XCTAssertNil(bottle.settings.detectedLauncher)
    }

    @MainActor
    func testNonLauncherExecutableAppliesNothing() throws {
        let bottle = makeBottle()
        bottle.settings.launcherCompatibilityMode = true
        let snapshot = bottle.settings

        XCTAssertFalse(LauncherFixes.detectAndApply(from: plainExe, for: bottle))

        XCTAssertEqual(bottle.settings, snapshot)
        XCTAssertNil(try persistedSettings().detectedLauncher)
    }

    @MainActor
    func testAutoModeReplacesDifferentDetectedLauncher() throws {
        let bottle = makeBottle()
        bottle.settings.launcherCompatibilityMode = true
        bottle.settings.detectedLauncher = .epicGames
        bottle.settings.gpuSpoofing = false

        XCTAssertTrue(LauncherFixes.detectAndApply(from: steamExe, for: bottle))

        XCTAssertEqual(bottle.settings.detectedLauncher, .steam)
        // Steam's fix set was applied along with the replacement.
        XCTAssertTrue(bottle.settings.gpuSpoofing)
        XCTAssertEqual(try persistedSettings().detectedLauncher, .steam)
    }

    @MainActor
    func testAlreadyConfiguredShortCircuitDoesNotRePersist() throws {
        let bottle = makeBottle()
        bottle.settings.launcherCompatibilityMode = true
        bottle.settings.detectedLauncher = .steam
        let snapshot = bottle.settings

        // Deleting the plist behind the bottle's back makes any settings write
        // observable: the short-circuit must not recreate the file.
        try FileManager.default.removeItem(at: metadataURL)

        XCTAssertFalse(LauncherFixes.detectAndApply(from: steamExe, for: bottle))

        XCTAssertFalse(FileManager.default.fileExists(atPath: metadataURL.path(percentEncoded: false)))
        XCTAssertEqual(bottle.settings, snapshot)
    }
}

// MARK: - apply profiles

final class LauncherFixesApplyTests: LauncherFixesTestCase {
    @MainActor
    func testApplyEnablesCompatModeAndAppliesSteamFixSet() throws {
        // The auto-mode Play path (#166): a fresh Steam bottle defaults to
        // compatibility mode off, and apply turns it on alongside the full
        // Steam profile, not just the flag.
        let bottle = makeBottle()
        XCTAssertFalse(bottle.settings.launcherCompatibilityMode)

        LauncherFixes.apply(to: bottle, launcher: .steam)

        XCTAssertTrue(bottle.settings.launcherCompatibilityMode)
        XCTAssertEqual(bottle.settings.detectedLauncher, .steam)
        // The locale stays the user's: Auto, which follows the Mac for Steam (#330).
        XCTAssertEqual(bottle.settings.launcherLocale, .auto)
        XCTAssertTrue(bottle.settings.gpuSpoofing)

        // Saved synchronously so Wine reads the new values.
        let persisted = try persistedSettings()
        XCTAssertTrue(persisted.launcherCompatibilityMode)
        XCTAssertEqual(persisted.detectedLauncher, .steam)
        XCTAssertEqual(persisted.launcherLocale, .auto)
        XCTAssertTrue(persisted.gpuSpoofing)
    }

    @MainActor
    func testSteamProfileLeavesTheBackendAlone() {
        // The runtime picks its graphics layer itself: no launcher profile
        // switches the bottle's backend.
        for backend in GraphicsBackend.allCases {
            let bottle = makeBottle()
            bottle.settings.graphicsBackend = backend

            LauncherFixes.apply(to: bottle, launcher: .steam)

            XCTAssertEqual(bottle.settings.graphicsBackend, backend, "\(backend)")
        }
    }

    @MainActor
    func testEveryLauncherProfileLeavesTheBackendAlone() {
        for launcher in LauncherType.allCases {
            let bottle = makeBottle()

            LauncherFixes.apply(to: bottle, launcher: launcher)

            XCTAssertEqual(bottle.settings.graphicsBackend, .recommended, "\(launcher)")
        }
    }
}
