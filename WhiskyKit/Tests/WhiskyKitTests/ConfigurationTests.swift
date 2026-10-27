//
//  ConfigurationTests.swift
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

import SemanticVersion
@testable import WhiskyKit
import XCTest

// MARK: - BottleWineConfig Decoding Tests

final class BottleWineConfigDecodingTests: XCTestCase {
    private func createVersionDict(major: Int, minor: Int, patch: Int) -> [String: Any] {
        ["major": major, "minor": minor, "patch": patch, "preRelease": "", "build": ""]
    }

    func testDecodeWithAllValues() throws {
        let plist: [String: Any] = [
            "wineVersion": createVersionDict(major: 8, minor: 0, patch: 1),
            "windowsVersion": "win11",
            "enhancedSync": ["esync": [:]],
            "avxEnabled": true
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let config = try PropertyListDecoder().decode(BottleWineConfig.self, from: data)

        XCTAssertEqual(config.wineVersion, SemanticVersion(8, 0, 1))
        XCTAssertEqual(config.windowsVersion, .win11)
        XCTAssertEqual(config.enhancedSync, .esync)
        XCTAssertTrue(config.avxEnabled)
    }

    func testDecodeEmptyPlistUsesAllDefaults() throws {
        let plist: [String: Any] = [:]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let config = try PropertyListDecoder().decode(BottleWineConfig.self, from: data)

        XCTAssertEqual(config.wineVersion, SemanticVersion(7, 7, 0))
        XCTAssertEqual(config.windowsVersion, .win10)
        XCTAssertEqual(config.enhancedSync, .msync)
        XCTAssertFalse(config.avxEnabled)
    }
}

// MARK: - BottleWineConfig Round-Trip Tests

final class BottleWineConfigRoundTripTests: XCTestCase {
    func testRoundTripWithCustomValues() throws {
        var original = BottleWineConfig()
        original.wineVersion = SemanticVersion(9, 0, 0)
        original.windowsVersion = .win11
        original.enhancedSync = .esync
        original.avxEnabled = true

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)

        let decoded = try PropertyListDecoder().decode(BottleWineConfig.self, from: data)

        XCTAssertEqual(decoded.wineVersion, SemanticVersion(9, 0, 0))
        XCTAssertEqual(decoded.windowsVersion, .win11)
        XCTAssertEqual(decoded.enhancedSync, .esync)
        XCTAssertTrue(decoded.avxEnabled)
    }
}

// MARK: - BottleWineConfig Static Properties Tests

final class BottleWineConfigStaticTests: XCTestCase {
    func testDefaultWineVersion() {
        XCTAssertEqual(BottleWineConfig.defaultWineVersion, SemanticVersion(7, 7, 0))
    }
}
