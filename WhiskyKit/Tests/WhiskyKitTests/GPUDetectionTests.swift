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
    func testNVIDIAVendorID() {
        XCTAssertEqual(GPUVendor.nvidia.vendorID, "0x10DE")
        XCTAssertEqual(GPUVendor.nvidia.modelName, "NVIDIA GeForce RTX 4090")
    }

    func testAMDVendorID() {
        XCTAssertEqual(GPUVendor.amd.vendorID, "0x1002")
        XCTAssertEqual(GPUVendor.amd.modelName, "AMD Radeon RX 6900 XT")
    }

    func testIntelVendorID() {
        XCTAssertEqual(GPUVendor.intel.vendorID, "0x8086")
    }

    func testGPUSpoofingIncludesOpenGLVersion() {
        let env = GPUDetection.spoofGPU(vendor: .nvidia)

        // Should report OpenGL 4.6
        XCTAssertEqual(env["MESA_GL_VERSION_OVERRIDE"], "4.6")
        XCTAssertEqual(env["MESA_GLSL_VERSION_OVERRIDE"], "460")
    }

    func testGPUSpoofingIncludesRayTracing() {
        let env = GPUDetection.spoofGPU(vendor: .nvidia)

        // Should report DXR support
        XCTAssertEqual(env["D3DM_SUPPORT_DXR"], "1")
    }

    func testSpoofingEnvironmentHasRequiredKeys() {
        let env = GPUDetection.spoofGPU(vendor: .nvidia)
        XCTAssertNotNil(env["MESA_GL_VERSION_OVERRIDE"])
        XCTAssertNotNil(env["MESA_GLSL_VERSION_OVERRIDE"])
    }

    func testAllVendorsHaveDeviceIDs() {
        for vendor in GPUVendor.allCases {
            XCTAssertFalse(vendor.vendorID.isEmpty)
            XCTAssertFalse(vendor.deviceID.isEmpty)
            XCTAssertFalse(vendor.modelName.isEmpty)
        }
    }

    func testNoHardcodedVulkanICDPath() {
        let env = GPUDetection.spoofGPU(vendor: .nvidia)

        // The old value pointed at /usr/local/share, which exists on no user
        // machine; the runtime carries its own MoltenVK configuration.
        XCTAssertNil(env["VK_ICD_FILENAMES"])
    }
}
