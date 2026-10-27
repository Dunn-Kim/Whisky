//
//  LauncherDiagnosticsTests.swift
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

/// Launcher-compatibility environment and persistence through the bottle layer.
/// Config defaults, Codable and the base env-var mapping live in BottleLauncherConfigTests.
@MainActor
final class LauncherDiagnosticsTests: XCTestCase {
    private func makeBottle() throws -> Bottle {
        Bottle(bottleUrl: try makeTempDir(), inFlight: false, isAvailable: true)
    }

    func testEveryLauncherTypeHasAFixDescription() {
        for launcher in LauncherType.allCases {
            XCTAssertFalse(launcher.fixesDescription.isEmpty, "\(launcher)")
        }
    }

    func testExtremeTimeouts() {
        var settings = BottleSettings()
        settings.launcherCompatibilityMode = true

        settings.networkTimeout = 30_000 // Minimum
        XCTAssertEqual(settings.env["WINHTTP_CONNECT_TIMEOUT"], "30000")

        settings.networkTimeout = 180_000 // Maximum
        XCTAssertEqual(settings.env["WINHTTP_CONNECT_TIMEOUT"], "180000")

        settings.networkTimeout = 60_000 // Default (should not set)
        XCTAssertNil(settings.env["WINHTTP_CONNECT_TIMEOUT"], "Default timeout should not set environment variable")
    }

    func testGPUSpoofingPerVendor() {
        var settings = BottleSettings()
        settings.launcherCompatibilityMode = true
        settings.gpuSpoofing = true

        for vendor in GPUVendor.allCases {
            settings.gpuVendor = vendor
            let env = settings.env
            XCTAssertEqual(env["GPU_VENDOR_ID"], vendor.vendorID, "Vendor ID should match for \(vendor.rawValue)")
            XCTAssertNotNil(env["GPU_DEVICE_ID"])
            XCTAssertNotNil(env["D3DM_FEATURE_LEVEL_12_1"])
        }
    }

    func testGPUSpoofingDisabled() {
        var settings = BottleSettings()
        settings.launcherCompatibilityMode = true
        settings.gpuSpoofing = false

        XCTAssertNil(settings.env["GPU_VENDOR_ID"], "GPU vendor should not be set when spoofing disabled")
    }

    func testLocaleOverrideConfiguration() {
        var settings = BottleSettings()
        settings.launcherCompatibilityMode = true
        settings.launcherLocale = .japanese

        let env = settings.env
        XCTAssertEqual(env["LC_ALL"], "ja_JP.UTF-8")
        XCTAssertEqual(env["LANG"], "ja_JP.UTF-8")
        XCTAssertEqual(env["LC_TIME"], "C")
        XCTAssertEqual(env["LC_NUMERIC"], "C")
    }

    /// `.auto` has an empty rawValue, which must never be written out as LC_ALL/LANG.
    func testAutoLocaleDoesNotSetEnvironment() {
        var settings = BottleSettings()
        settings.launcherCompatibilityMode = true
        settings.launcherLocale = .auto

        let env = settings.env
        XCTAssertNil(env["LC_ALL"], "Auto locale should not set LC_ALL")
        XCTAssertNil(env["LANG"], "Auto locale should not set LANG")
    }

    func testAutoEnableDXVKNotTriggeredForSteam() {
        var settings = BottleSettings()
        settings.launcherCompatibilityMode = true
        settings.detectedLauncher = .steam // Steam doesn't require DXVK
        settings.autoEnableDXVK = true
        settings.dxvk = false
        // Pin a builtin-backed backend: `.recommended` resolves via ambient
        // machine state and would add the DXVK preset through the bottle layer
        // on machines without a runtime. Auto-enable applies through the
        // launcher layer regardless of backend, so the assertion below still
        // catches Steam wrongly auto-enabling.
        settings.graphicsBackend = .d3dMetal

        XCTAssertNil(settings.env["WINEDLLOVERRIDES"])
    }

    func testLauncherSettingsPersistence() throws {
        let bottle = try makeBottle()
        bottle.settings.launcherCompatibilityMode = true
        bottle.settings.launcherMode = .manual
        bottle.settings.detectedLauncher = .rockstar
        bottle.settings.launcherLocale = .english
        bottle.settings.gpuSpoofing = true
        bottle.settings.gpuVendor = .nvidia
        bottle.settings.networkTimeout = 90_000
        bottle.settings.autoEnableDXVK = true
        bottle.saveBottleSettings()

        // Load settings from disk into new bottle instance
        let bottle2 = Bottle(bottleUrl: bottle.url, inFlight: false, isAvailable: true)

        XCTAssertTrue(bottle2.settings.launcherCompatibilityMode)
        XCTAssertEqual(bottle2.settings.launcherMode, .manual)
        XCTAssertEqual(bottle2.settings.detectedLauncher, .rockstar)
        XCTAssertEqual(bottle2.settings.launcherLocale, .english)
        XCTAssertTrue(bottle2.settings.gpuSpoofing)
        XCTAssertEqual(bottle2.settings.gpuVendor, .nvidia)
        XCTAssertEqual(bottle2.settings.networkTimeout, 90_000)
        XCTAssertTrue(bottle2.settings.autoEnableDXVK)
    }

    func testLauncherEnvironmentMergePrecedence() throws {
        let bottle = try makeBottle()
        bottle.settings.launcherCompatibilityMode = true
        bottle.settings.detectedLauncher = .steam

        // Use constructWineEnvironment to get full environment including macOS compat fixes
        let env = Wine.constructWineEnvironment(for: bottle, environment: [:])

        XCTAssertEqual(env["STEAM_DISABLE_CEF_SANDBOX"], "1", "Steam-specific CEF disable from preset")
        XCTAssertEqual(env["CEF_DISABLE_SANDBOX"], "1", "Global CEF disable from MacOSCompatibility")
        XCTAssertEqual(env["STEAM_RUNTIME"], "0")
        XCTAssertEqual(env["DXVK_ASYNC"], "1")
    }

    func testMacOSCompatibilityEnvironmentApplied() throws {
        let bottle = try makeBottle()
        let env = Wine.constructWineEnvironment(for: bottle, environment: [:])

        // CEF sandbox should be disabled on all macOS versions
        XCTAssertEqual(env["STEAM_DISABLE_CEF_SANDBOX"], "1")
        XCTAssertEqual(env["CEF_DISABLE_SANDBOX"], "1")

        // Base Wine environment should be set
        XCTAssertEqual(env["WINEPREFIX"], bottle.url.path)
        XCTAssertEqual(env["WINEDEBUG"], "fixme-all")
    }

    /// CRITICAL: Steam's "en_US.UTF-8" must not be overwritten with "en_US"
    /// (missing .UTF-8 suffix), which would break steamwebhelper.
    func testSteamLocaleNotOverwritten() throws {
        let bottle = try makeBottle()
        bottle.settings.launcherCompatibilityMode = true
        bottle.settings.detectedLauncher = .steam
        bottle.settings.launcherLocale = .english // This is set by LauncherDetection

        // Full Wine environment (includes launcher preset + bottle settings)
        let env = Wine.constructWineEnvironment(for: bottle, environment: [:])

        XCTAssertEqual(env["LC_ALL"], "en_US.UTF-8", "Steam's LC_ALL must have .UTF-8 suffix")
        XCTAssertEqual(env["LANG"], "en_US.UTF-8", "Steam's LANG must have .UTF-8 suffix")
    }

    func testEveryNonAutoLocaleHasUTF8Suffix() {
        for locale in Locales.allCases where locale != .auto {
            XCTAssertTrue(locale.rawValue.hasSuffix(".UTF-8"), "\(locale.rawValue) should have .UTF-8 suffix")
        }
    }
}
