//
//  EnvironmentVariablesTests.swift
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

final class EnvironmentVariablesTests: XCTestCase {
    // MARK: - DXMT Environment Variables

    func testRecommendedBackendWritesNoDLLOverrides() {
        // The runtime carries its graphics layers and picks one per executable,
        // so no preset reaches WINEDLLOVERRIDES.
        let settings = BottleSettings()

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertNil(env["WINEDLLOVERRIDES"])
    }

    func testDXMTMetalFXUpscaleIsOptInAndDXMTOnly() {
        var settings = BottleSettings()
        settings.graphicsBackend = .dxmt
        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)
        XCTAssertNil(env["DXMT_METALFX_SPATIAL_SWAPCHAIN"], "off by default")

        settings.dxmtMetalFXUpscale = true
        env = [:]
        settings.environmentVariables(wineEnv: &env)
        XCTAssertEqual(env["DXMT_METALFX_SPATIAL_SWAPCHAIN"], "1")

        // Recommended resolves to DXMT, the runtime's default.
        settings.graphicsBackend = .recommended
        env = [:]
        settings.environmentVariables(wineEnv: &env)
        XCTAssertEqual(env["DXMT_METALFX_SPATIAL_SWAPCHAIN"], "1")

        settings.graphicsBackend = .wined3d
        env = [:]
        settings.environmentVariables(wineEnv: &env)
        XCTAssertNil(env["DXMT_METALFX_SPATIAL_SWAPCHAIN"], "inert under other backends")
    }

    // MARK: - Enhanced Sync Environment Variables

    func testEnvironmentVariablesWithMSync() {
        var settings = BottleSettings()
        settings.enhancedSync = .msync

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // The runtime has no esync, so only WINEMSYNC is written.
        XCTAssertEqual(env["WINEMSYNC"], "1")
        XCTAssertNil(env["WINEESYNC"])
    }

    func testEnvironmentVariablesWithNoEnhancedSync() {
        var settings = BottleSettings()
        settings.enhancedSync = .none

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["WINEMSYNC"], "0")
        XCTAssertNil(env["WINEESYNC"])
    }

    // MARK: - Metal Environment Variables

    func testEnvironmentVariablesWithMetalHUD() {
        var settings = BottleSettings()
        settings.metalHud = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["MTL_HUD_ENABLED"], "1")
    }

    func testEnvironmentVariablesWithMetalTrace() {
        var settings = BottleSettings()
        settings.metalTrace = true

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["METAL_CAPTURE_ENABLED"], "1")
    }

    func testEnvironmentVariablesWithMetalValidation() {
        var settings = BottleSettings()
        settings.metalValidation = true
        settings.sequoiaCompatMode = false

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["MTL_DEBUG_LAYER"], "1")
    }

    // MARK: - Other Environment Variables

    func testFEXKeepsItsTranslatedCodeInTheApplicationFolder() {
        var env: [String: String] = [:]
        BottleSettings().environmentVariables(wineEnv: &env)

        XCTAssertEqual(env["FEX_DISKCACHE"], "1")
        // The trailing slash matters: FEX appends its hash to the value as is.
        XCTAssertEqual(
            env["FEX_DISKCACHEPATH"],
            WhiskyWineInstaller.applicationFolder.path(percentEncoded: false) + "/FEXCache/"
        )
        XCTAssertNil(env["ROSETTA_ADVERTISE_AVX"])
    }

    // MARK: - Sequoia Compatibility Mode

    func testSequoiaToggleEmitsNothing() {
        var settings = BottleSettings()
        settings.sequoiaCompatMode = true
        settings.metalValidation = false

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // Of the three values the toggle used to set, two are platform-layer
        // fixes on every supported macOS, carried with provenance by
        // constructWineEnvironment, and D3DM_VALIDATION is read by no runtime;
        // the bottle-layer duplicates meant the toggle's off position changed
        // nothing.
        XCTAssertNil(env["MTL_DEBUG_LAYER"])
        XCTAssertNil(env["D3DM_VALIDATION"])
    }

    @MainActor
    func testPlatformLayerCarriesTheSequoiaFixes() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let bottle = Bottle(bottleUrl: tempDir, inFlight: false, isAvailable: true)

        let env = Wine.constructWineEnvironment(for: bottle)

        // Supported macOS is 15.4+ at minimum, so both fixes apply.
        // D3DM_VALIDATION is no longer one: no runtime reads it.
        XCTAssertEqual(env["MTL_DEBUG_LAYER"], "0")
        XCTAssertNil(env["D3DM_VALIDATION"])
        XCTAssertNil(env["WINEFSYNC"], "a Linux variable")
        XCTAssertNil(env["WINEESYNC"])
    }

    @MainActor
    func testMetalValidationOverridesThePlatformFix() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let bottle = Bottle(bottleUrl: tempDir, inFlight: false, isAvailable: true)
        bottle.settings.metalValidation = true

        let env = Wine.constructWineEnvironment(for: bottle)

        // The platform layer pins MTL_DEBUG_LAYER=0 on every supported macOS.
        // The toggle's bottle layer outranks it, and nothing may write 0 back
        // over the toggle the way the removed Performance preset did.
        XCTAssertEqual(env["MTL_DEBUG_LAYER"], "1")
    }

    // MARK: - Shader Cache

    func testEnvironmentVariablesWithDisabledShaderCache() {
        var settings = BottleSettings()
        settings.shaderCacheEnabled = false

        var env: [String: String] = [:]
        settings.environmentVariables(wineEnv: &env)

        // The variable DXMT reads, not the NVIDIA GL one the toggle used to set.
        XCTAssertEqual(env["DXMT_SHADER_CACHE"], "0")
        XCTAssertNil(env["__GL_SHADER_DISK_CACHE"])
    }

    // MARK: - EnvironmentBuilder Layer Populator Tests

    func testPopulateLauncherManagedLayerSetsNothingWhenDisabled() {
        var settings = BottleSettings()
        settings.launcherCompatibilityMode = false

        var builder = EnvironmentBuilder()
        settings.populateLauncherManagedLayer(builder: &builder)

        let (resolved, _) = builder.resolve()
        // No launcher-specific keys should be set
        XCTAssertNil(resolved["WINE_FORCE_HTTP11"])
        XCTAssertNil(resolved["STEAM_RUNTIME"])
    }

    // MARK: - Program Override Tests (applyProgramOverrides, direct)

    func testProgramBackendOverrideAddsNoDLLOverrides() {
        // A per-program backend choice is the runtime's to act on: nothing is
        // written to the program's DLL overrides for any backend.
        var builder = EnvironmentBuilder()
        var dllResolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])

        for backend in GraphicsBackend.allCases {
            var overrides = ProgramOverrides()
            overrides.graphicsBackend = backend
            Wine.applyProgramOverrides(
                overrides, builder: &builder, dllResolver: &dllResolver
            )
        }

        XCTAssertEqual(dllResolver.resolve().overrides, "")
    }

    func testProgramOverrideEnhancedSyncOverridesBottle() {
        // Bottle has msync, program overrides it off
        var builder = EnvironmentBuilder()
        var dllResolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])
        builder.set("WINEMSYNC", "1", layer: .bottleManaged)

        var overrides = ProgramOverrides()
        overrides.enhancedSync = EnhancedSync.none
        Wine.applyProgramOverrides(overrides, builder: &builder, dllResolver: &dllResolver)

        let (resolved, _) = builder.resolve()
        XCTAssertEqual(resolved["WINEMSYNC"], "0")
        XCTAssertNil(resolved["WINEESYNC"])
    }

    func testDLLOverridesComposeCorrectly() {
        // Bottle custom + program custom DLL overrides -> both present in WINEDLLOVERRIDES
        let dllResolver = DLLOverrideResolver(
            managed: [],
            bottleCustom: [DLLOverrideEntry(dllName: "d3dcompiler_47", mode: .native)],
            programCustom: [DLLOverrideEntry(dllName: "xaudio2_7", mode: .native)]
        )

        let (overrideString, _) = dllResolver.resolve()
        XCTAssertEqual(overrideString, "d3dcompiler_47=n;xaudio2_7=n")
    }

    func testProgramShaderCacheOverrideUsesTheDXMTVariable() {
        var builder = EnvironmentBuilder()
        var dllResolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])
        var overrides = ProgramOverrides()
        overrides.shaderCacheEnabled = false
        Wine.applyProgramOverrides(overrides, builder: &builder, dllResolver: &dllResolver)

        XCTAssertEqual(builder.resolve().environment["DXMT_SHADER_CACHE"], "0")
    }

    // MARK: - Old settings still decode

    func testOldBackendAndGraphicsKeysDecode() throws {
        // Settings written when DXVK and D3DMetal were choices carry keys this
        // build no longer has; they are ignored and the backend reads as Recommended.
        let json = Data(
            #"{"dxvk":true,"dxvkAsync":true,"dxvkHud":"full","metal4Enabled":true,"graphicsBackend":"dxvk"}"#.utf8
        )
        let decoded = try JSONDecoder().decode(ProgramOverrides.self, from: json)

        XCTAssertEqual(decoded.graphicsBackend, .recommended)
        XCTAssertNil(decoded.metalHud)
    }

    // MARK: - Metal HUD is per program, because the bottle value also covers launchers

    /// Resolves the environment a program gets from a bottle with the Metal HUD
    /// on, which is where `MTL_HUD_ENABLED` is set, with its own overrides on top.
    private func resolvedHUDEnvironment(
        bottleHUD: Bool,
        _ overrides: ProgramOverrides
    ) -> [String: String] {
        var settings = BottleSettings()
        settings.metalHud = bottleHUD
        var builder = EnvironmentBuilder()
        var dllResolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])

        settings.populateBottleManagedLayer(builder: &builder)
        Wine.applyProgramOverrides(overrides, builder: &builder, dllResolver: &dllResolver)

        return builder.resolve().environment
    }

    func testProgramCanTakeTheHUDWithoutTheBottleHavingIt() {
        // The point of the override: measure one title without the HUD sitting
        // over the launcher the player is still using.
        var overrides = ProgramOverrides()
        overrides.metalHud = true

        XCTAssertEqual(resolvedHUDEnvironment(bottleHUD: false, overrides)["MTL_HUD_ENABLED"], "1")
    }

    func testProgramCanDropTheHUDWithoutTheBottleLosingIt() {
        var overrides = ProgramOverrides()
        overrides.metalHud = false

        // Removed rather than set to "0": the removal shadows the bottle's value,
        // and an absent variable leaves Metal's HUD off.
        XCTAssertNil(resolvedHUDEnvironment(bottleHUD: true, overrides)["MTL_HUD_ENABLED"])
    }

    func testMetalHUDOverrideUnsetInheritsTheBottle() {
        XCTAssertEqual(resolvedHUDEnvironment(bottleHUD: true, ProgramOverrides())["MTL_HUD_ENABLED"], "1")
        XCTAssertNil(resolvedHUDEnvironment(bottleHUD: false, ProgramOverrides())["MTL_HUD_ENABLED"])
        XCTAssertNil(ProgramOverrides().metalHud)
    }

    func testMetalHUDOverrideCountsTowardsIsEmpty() {
        var overrides = ProgramOverrides()
        overrides.metalHud = true

        XCTAssertFalse(overrides.isEmpty)
    }

    func testOverridesWithoutAMetalHUDKeyDecodeToInherit() throws {
        // Overrides written before this key existed must keep inheriting.
        let json = Data(#"{"shaderCacheEnabled":true}"#.utf8)
        let decoded = try JSONDecoder().decode(ProgramOverrides.self, from: json)

        XCTAssertNil(decoded.metalHud)
        XCTAssertEqual(decoded.shaderCacheEnabled, true)
    }

    func testMetalHUDOverrideSurvivesASettingsRoundTrip() throws {
        var overrides = ProgramOverrides()
        overrides.metalHud = true

        let data = try PropertyListEncoder().encode(overrides)
        let decoded = try PropertyListDecoder().decode(ProgramOverrides.self, from: data)

        XCTAssertEqual(decoded.metalHud, true)
    }

    func testSettingsWithoutAMetalHUDKeyDecodeToInherit() throws {
        // Settings written before this override existed must keep inheriting.
        let json = Data(#"{"shaderCacheEnabled":false}"#.utf8)
        let decoded = try JSONDecoder().decode(ProgramOverrides.self, from: json)

        XCTAssertNil(decoded.metalHud)
        XCTAssertEqual(decoded.shaderCacheEnabled, false)
    }
}

extension BottleSettings {
    /// The bottle-managed, launcher and input layers resolved into `wineEnv`, with the
    /// bottle's DLL overrides composed. A test helper: launches go through
    /// `Wine.constructWineEnvironment`, and nothing in the app used it.
    func environmentVariables(wineEnv: inout [String: String]) {
        var builder = EnvironmentBuilder()
        populateBottleManagedLayer(builder: &builder)
        populateLauncherManagedLayer(builder: &builder)
        populateInputCompatibilityLayer(builder: &builder)
        wineEnv.merge(builder.resolve().0) { _, new in new }

        let resolver = DLLOverrideResolver(managed: [], bottleCustom: dllOverrides, programCustom: [])
        let (overrides, _) = resolver.resolve()
        if !overrides.isEmpty {
            wineEnv["WINEDLLOVERRIDES"] = overrides
        }
    }
}
