//
//  FrameRateLimitTests.swift
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

@testable import WhiskyKit
import XCTest

final class FrameRateLimitTests: XCTestCase {
    // MARK: - Resolution

    func testFixedLimitIgnoresDisplayRefreshRate() {
        XCTAssertEqual(FrameRateLimit.fps60.resolved(displayRefreshRate: 144), 60)
        XCTAssertEqual(FrameRateLimit.fps120.resolved(displayRefreshRate: nil), 120)
    }

    func testLimitPacesEvenlyOnlyOnAMultipleOfIt() {
        XCTAssertTrue(FrameRateLimit.fps60.pacesEvenly(displayRefreshRate: 120))
        XCTAssertTrue(FrameRateLimit.fps30.pacesEvenly(displayRefreshRate: 60))
        XCTAssertTrue(FrameRateLimit.matchDisplay.pacesEvenly(displayRefreshRate: 75))
        XCTAssertFalse(FrameRateLimit.fps60.pacesEvenly(displayRefreshRate: 75))
        XCTAssertFalse(FrameRateLimit.fps90.pacesEvenly(displayRefreshRate: 120))
        XCTAssertFalse(FrameRateLimit.fps144.pacesEvenly(displayRefreshRate: 120))
    }

    func testNoCapOrUnknownRefreshRateCountsAsEven() {
        XCTAssertTrue(FrameRateLimit.unlimited.pacesEvenly(displayRefreshRate: 75))
        XCTAssertTrue(FrameRateLimit.fps60.pacesEvenly(displayRefreshRate: nil))
        XCTAssertTrue(FrameRateLimit.matchDisplay.pacesEvenly(displayRefreshRate: nil))
    }

    func testBackendsWithoutLimiterSetNothing() {
        for backend in [GraphicsBackend.wined3d, .recommended] {
            XCTAssertFalse(backend.supportsFrameRateLimit, "\(backend) should report no limiter")
            XCTAssertTrue(
                backend.frameRateLimitEnvironment(fps: 60).isEmpty,
                "\(backend) should set no frame rate variables"
            )
        }
    }

    // MARK: - Bottle managed layer

    private func bottleEnvironment(
        backend: GraphicsBackend,
        limit: FrameRateLimit,
        displayRefreshRate: Int? = 144
    ) -> [String: String] {
        var settings = BottleSettings()
        settings.graphicsBackend = backend
        settings.frameRateLimit = limit
        var builder = EnvironmentBuilder()
        settings.populateBottleManagedLayer(
            builder: &builder, displayRefreshRate: displayRefreshRate
        )
        return builder.resolve().0
    }

    func testBottleCapAppliesToDXMT() {
        let env = bottleEnvironment(backend: .dxmt, limit: .fps60)
        XCTAssertEqual(env["DXMT_CONFIG"], "d3d11.preferredMaxFrameRate=60")
    }

    func testBottleCapAppliesToRecommended() {
        // Recommended resolves to DXMT, which carries the limiter.
        let env = bottleEnvironment(backend: .recommended, limit: .matchDisplay)
        XCTAssertEqual(env["DXMT_CONFIG"], "d3d11.preferredMaxFrameRate=144")
    }

    func testBottleCapIsNotSetUnderWineD3D() {
        let env = bottleEnvironment(backend: .wined3d, limit: .fps60)
        XCTAssertNil(env["DXMT_CONFIG"])
    }

    func testUnlimitedBottleSetsNoCap() {
        let env = bottleEnvironment(backend: .dxmt, limit: .unlimited)
        XCTAssertNil(env["DXMT_CONFIG"])
    }

    /// An unknown refresh rate must not be guessed at: capping a 144 Hz panel to a
    /// made-up 60 would be a visible regression, so no cap is applied instead.
    func testMatchDisplayWithUnknownRefreshRateSetsNoCap() {
        let env = bottleEnvironment(backend: .dxmt, limit: .matchDisplay, displayRefreshRate: nil)
        XCTAssertNil(env["DXMT_CONFIG"])
    }

    // MARK: - Program overrides

    private func programEnvironment(
        bottleBackend: GraphicsBackend,
        bottleLimit: FrameRateLimit,
        overrides: ProgramOverrides,
        programDXMTConfig: String? = nil,
        displayRefreshRate: Int? = 144
    ) -> [String: String] {
        var settings = BottleSettings()
        settings.graphicsBackend = bottleBackend
        settings.frameRateLimit = bottleLimit
        var builder = EnvironmentBuilder()
        var dllResolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])
        settings.populateBottleManagedLayer(
            builder: &builder, displayRefreshRate: displayRefreshRate
        )
        // The program's own environment lands in programUser before its overrides,
        // as in constructWineEnvironment.
        if let programDXMTConfig {
            builder.set("DXMT_CONFIG", programDXMTConfig, layer: .programUser)
        }
        Wine.applyProgramOverrides(
            overrides, builder: &builder, dllResolver: &dllResolver,
            bottleBackend: bottleBackend,
            bottleFrameRateLimit: bottleLimit,
            displayRefreshRate: displayRefreshRate
        )
        return builder.resolve().0
    }

    func testProgramCapReplacesBottleCap() {
        var overrides = ProgramOverrides()
        overrides.frameRateLimit = .fps30
        let env = programEnvironment(bottleBackend: .dxmt, bottleLimit: .fps120, overrides: overrides)
        XCTAssertEqual(env["DXMT_CONFIG"], "d3d11.preferredMaxFrameRate=30")
    }

    func testProgramUnlimitedClearsBottleCap() {
        var overrides = ProgramOverrides()
        overrides.frameRateLimit = .unlimited
        let env = programEnvironment(bottleBackend: .dxmt, bottleLimit: .fps60, overrides: overrides)
        XCTAssertEqual(env["DXMT_CONFIG"], "d3d11.preferredMaxFrameRate=0")
    }

    /// Moving a program off DXMT has to take the bottle's cap with it, or it
    /// would sit on a variable nothing reads.
    func testProgramBackendSwitchDropsTheCap() {
        var overrides = ProgramOverrides()
        overrides.graphicsBackend = .wined3d
        let env = programEnvironment(bottleBackend: .dxmt, bottleLimit: .fps60, overrides: overrides)
        XCTAssertNil(env["DXMT_CONFIG"])
    }

    func testNoGraphicsOverrideLeavesBottleCapIntact() {
        var overrides = ProgramOverrides()
        overrides.disableHIDAPI = true
        let env = programEnvironment(bottleBackend: .dxmt, bottleLimit: .fps60, overrides: overrides)
        XCTAssertEqual(env["DXMT_CONFIG"], "d3d11.preferredMaxFrameRate=60")
    }

    /// A program's own DXMT_CONFIG used to replace the whole variable, which
    /// silently dropped the bottle's cap.
    func testProgramDXMTConfigKeepsBottleCap() {
        let env = programEnvironment(
            bottleBackend: .dxmt, bottleLimit: .fps60, overrides: ProgramOverrides(),
            programDXMTConfig: "dxgi.customDeviceId=03f1"
        )
        XCTAssertEqual(env["DXMT_CONFIG"], "d3d11.preferredMaxFrameRate=60;dxgi.customDeviceId=03f1")
    }

    func testProgramCapKeepsProgramDXMTConfig() {
        var overrides = ProgramOverrides()
        overrides.frameRateLimit = .fps30
        let env = programEnvironment(
            bottleBackend: .dxmt, bottleLimit: .fps60, overrides: overrides,
            programDXMTConfig: "dxgi.customDeviceId=03f1"
        )
        XCTAssertEqual(env["DXMT_CONFIG"], "d3d11.preferredMaxFrameRate=30;dxgi.customDeviceId=03f1")
    }

    func testProgramUnlimitedOnDXMTCancelsBottleCap() {
        var overrides = ProgramOverrides()
        overrides.frameRateLimit = .unlimited
        let env = programEnvironment(bottleBackend: .dxmt, bottleLimit: .fps60, overrides: overrides)
        XCTAssertEqual(env["DXMT_CONFIG"], "d3d11.preferredMaxFrameRate=0")
    }

    // MARK: - Persistence

    func testNewConfigDefaultsToMatchDisplay() {
        XCTAssertEqual(BottleGraphicsConfig().frameRateLimit, .matchDisplay)
    }

    /// Bottles written before this setting existed must keep behaving exactly as
    /// they did, so a missing key decodes to `.unlimited`, not to the new default.
    func testLegacyConfigWithoutKeyDecodesToUnlimited() throws {
        let json = Data(#"{"backend":"dxmt"}"#.utf8)
        let config = try JSONDecoder().decode(BottleGraphicsConfig.self, from: json)
        XCTAssertEqual(config.frameRateLimit, .unlimited)
        XCTAssertEqual(config.backend, .dxmt)
    }

    func testUnknownStoredValueDecodesToUnlimited() throws {
        let json = Data(#"{"backend":"dxmt","frameRateLimit":37}"#.utf8)
        let config = try JSONDecoder().decode(BottleGraphicsConfig.self, from: json)
        XCTAssertEqual(config.frameRateLimit, .unlimited)
    }

    func testStoredValueRoundTrips() throws {
        var config = BottleGraphicsConfig()
        config.frameRateLimit = .fps90
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(BottleGraphicsConfig.self, from: data)
        XCTAssertEqual(decoded.frameRateLimit, .fps90)
    }

    func testProgramOverrideRoundTripsAndCountsAsNonEmpty() throws {
        var overrides = ProgramOverrides()
        XCTAssertTrue(overrides.isEmpty)
        overrides.frameRateLimit = .fps60
        XCTAssertFalse(overrides.isEmpty)
        let data = try JSONEncoder().encode(overrides)
        let decoded = try JSONDecoder().decode(ProgramOverrides.self, from: data)
        XCTAssertEqual(decoded.frameRateLimit, .fps60)
    }
}
