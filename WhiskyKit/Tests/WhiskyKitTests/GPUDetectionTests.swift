//
//  GPUDetectionTests.swift
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

final class GPUDetectionTests: XCTestCase {
    func testGPUSpoofingOmitsUnreadVendorKeys() {
        let env = GPUDetection.spoofGPU()

        // No shipped runtime reads any of these, so the spoof doesn't set them.
        XCTAssertNil(env["GPU_VENDOR_ID"])
        XCTAssertNil(env["GPU_DEVICE_ID"])
        XCTAssertNil(env["GPU_DESCRIPTION"])
        XCTAssertNil(env["GPU_MEMORY_SIZE"])
        XCTAssertNil(env["D3DM_SHADER_MODEL"])
    }

    func testGPUSpoofingOmitsUnreadFeatureLevelKeys() {
        let env = GPUDetection.spoofGPU()

        // Wine and DXMT read none of these, so the spoof
        // doesn't set them.
        XCTAssertNil(env["D3DM_FEATURE_LEVEL_12_1"])
        XCTAssertNil(env["D3DM_FEATURE_LEVEL_12_0"])
        XCTAssertNil(env["D3DM_FEATURE_LEVEL_11_1"])
    }

    func testGPUSpoofingIncludesOpenGLVersion() {
        let env = GPUDetection.spoofGPU()

        // Should report OpenGL 4.6
        XCTAssertEqual(env["MESA_GL_VERSION_OVERRIDE"], "4.6")
        XCTAssertEqual(env["MESA_GLSL_VERSION_OVERRIDE"], "460")
    }

    func testNoHardcodedVulkanICDPath() {
        let env = GPUDetection.spoofGPU()

        // The old value pointed at /usr/local/share, which exists on no user
        // machine; the runtime carries its own MoltenVK configuration.
        XCTAssertNil(env["VK_ICD_FILENAMES"])
    }
}
