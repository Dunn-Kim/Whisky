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

    func testUnlimitedResolvesToNoCap() {
        XCTAssertNil(FrameRateLimit.unlimited.resolved(displayRefreshRate: 144))
    }

    func testFixedLimitIgnoresDisplayRefreshRate() {
        XCTAssertEqual(FrameRateLimit.fps60.resolved(displayRefreshRate: 144), 60)
        XCTAssertEqual(FrameRateLimit.fps120.resolved(displayRefreshRate: nil), 120)
    }

    func testMatchDisplayUsesRefreshRate() {
        XCTAssertEqual(FrameRateLimit.matchDisplay.resolved(displayRefreshRate: 144), 144)
    }

    /// An unknown refresh rate must not be guessed at: capping a 144 Hz panel to a
    /// made-up 60 would be a visible regression, so no cap is applied instead.
    func testMatchDisplayWithoutRefreshRateResolvesToNoCap() {
        XCTAssertNil(FrameRateLimit.matchDisplay.resolved(displayRefreshRate: nil))
    }

    // MARK: - Backend mapping

    func testDXVKUsesFrameRateVariable() {
        XCTAssertEqual(
            GraphicsBackend.dxvk.frameRateLimitEnvironment(fps: 60),
            ["DXVK_FRAME_RATE": "60"]
        )
    }

    func testDXMTUsesConfigVariable() {
        XCTAssertEqual(
            GraphicsBackend.dxmt.frameRateLimitEnvironment(fps: 90),
            ["DXMT_CONFIG": "d3d11.preferredMaxFrameRate=90"]
        )
    }

    func testBackendsWithoutLimiterSetNothing() {
        for backend in [GraphicsBackend.d3dMetal, .wined3d, .recommended] {
            XCTAssertFalse(backend.supportsFrameRateLimit, "\(backend) should report no limiter")
            XCTAssertTrue(
                backend.frameRateLimitEnvironment(fps: 60).isEmpty,
                "\(backend) should set no frame rate variables"
            )
        }
    }

    func testNonPositiveFPSSetsNothing() {
        XCTAssertTrue(GraphicsBackend.dxvk.frameRateLimitEnvironment(fps: 0).isEmpty)
        XCTAssertTrue(GraphicsBackend.dxmt.frameRateLimitEnvironment(fps: -1).isEmpty)
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
        _ = settings.populateBottleManagedLayer(
            builder: &builder, displayRefreshRate: displayRefreshRate
        )
        return builder.resolve().0
    }

    func testBottleCapAppliesToDXMT() {
        let env = bottleEnvironment(backend: .dxmt, limit: .fps60)
        XCTAssertEqual(env["DXMT_CONFIG"], "d3d11.preferredMaxFrameRate=60")
        XCTAssertNil(env["DXVK_FRAME_RATE"])
    }

    func testBottleCapAppliesToDXVK() {
        let env = bottleEnvironment(backend: .dxvk, limit: .matchDisplay)
        XCTAssertEqual(env["DXVK_FRAME_RATE"], "144")
        XCTAssertNil(env["DXMT_CONFIG"])
    }

    func testUnlimitedBottleSetsNoCap() {
        let env = bottleEnvironment(backend: .dxmt, limit: .unlimited)
        XCTAssertNil(env["DXMT_CONFIG"])
        XCTAssertNil(env["DXVK_FRAME_RATE"])
    }

    func testMatchDisplayWithUnknownRefreshRateSetsNoCap() {
        let env = bottleEnvironment(backend: .dxvk, limit: .matchDisplay, displayRefreshRate: nil)
        XCTAssertNil(env["DXVK_FRAME_RATE"])
    }

    // MARK: - Program overrides

    private func programEnvironment(
        bottleBackend: GraphicsBackend,
        bottleLimit: FrameRateLimit,
        overrides: ProgramOverrides,
        displayRefreshRate: Int? = 144
    ) -> [String: String] {
        var settings = BottleSettings()
        settings.graphicsBackend = bottleBackend
        settings.frameRateLimit = bottleLimit
        var builder = EnvironmentBuilder()
        var dllResolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])
        let managed = settings.populateBottleManagedLayer(
            builder: &builder, displayRefreshRate: displayRefreshRate
        )
        dllResolver.managed.append(contentsOf: managed)
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
        let env = programEnvironment(bottleBackend: .dxvk, bottleLimit: .fps60, overrides: overrides)
        XCTAssertNil(env["DXVK_FRAME_RATE"])
    }

    /// Switching backend per program has to move the cap onto that backend's own
    /// variable, or the bottle's cap would sit on a variable nothing reads.
    func testProgramBackendSwitchMovesCapToNewVariable() {
        var overrides = ProgramOverrides()
        overrides.graphicsBackend = .dxvk
        let env = programEnvironment(bottleBackend: .dxmt, bottleLimit: .fps60, overrides: overrides)
        XCTAssertEqual(env["DXVK_FRAME_RATE"], "60")
        XCTAssertNil(env["DXMT_CONFIG"])
    }

    func testNoGraphicsOverrideLeavesBottleCapIntact() {
        var overrides = ProgramOverrides()
        overrides.disableHIDAPI = true
        let env = programEnvironment(bottleBackend: .dxmt, bottleLimit: .fps60, overrides: overrides)
        XCTAssertEqual(env["DXMT_CONFIG"], "d3d11.preferredMaxFrameRate=60")
    }

    // MARK: - Persistence

    func testNewConfigDefaultsToMatchDisplay() {
        XCTAssertEqual(BottleGraphicsConfig().frameRateLimit, .matchDisplay)
    }

    /// Bottles written before this setting existed must keep behaving exactly as
    /// they did, so a missing key decodes to `.unlimited`, not to the new default.
    func testLegacyConfigWithoutKeyDecodesToUnlimited() throws {
        let json = Data(#"{"backend":"dxvk"}"#.utf8)
        let config = try JSONDecoder().decode(BottleGraphicsConfig.self, from: json)
        XCTAssertEqual(config.frameRateLimit, .unlimited)
        XCTAssertEqual(config.backend, .dxvk)
    }

    func testUnknownStoredValueDecodesToUnlimited() throws {
        let json = Data(#"{"backend":"dxvk","frameRateLimit":37}"#.utf8)
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
