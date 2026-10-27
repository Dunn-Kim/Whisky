//
//  SettingsTests.swift
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
import SemanticVersion
@testable import WhiskyKit
import XCTest

// MARK: - PinnedProgram Decoding Tests

final class PinnedProgramDecodingTests: XCTestCase {
    func testDecodeEmptyPlistUsesDefaults() throws {
        let plist: [String: Any] = [:]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let pin = try PropertyListDecoder().decode(PinnedProgram.self, from: data)

        XCTAssertEqual(pin.name, "")
        XCTAssertNil(pin.url)
        XCTAssertFalse(pin.removable)
    }

    func testPinnedProgramRoundTrip() throws {
        let url = URL(fileURLWithPath: "/Applications/Game.exe")
        let original = PinnedProgram(name: "My Game", url: url)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)

        let decoded = try PropertyListDecoder().decode(PinnedProgram.self, from: data)

        XCTAssertEqual(decoded.name, "My Game")
        XCTAssertEqual(decoded.url, url)
    }
}

// MARK: - BottleInfo Decoding Tests

final class BottleInfoDecodingTests: XCTestCase {
    func testDecodeEmptyPlistUsesAllDefaults() throws {
        let plist: [String: Any] = [:]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let info = try PropertyListDecoder().decode(BottleInfo.self, from: data)

        XCTAssertEqual(info.name, "Bottle")
        XCTAssertTrue(info.pins.isEmpty)
        XCTAssertTrue(info.blocklist.isEmpty)
    }

    func testBottleInfoRoundTrip() throws {
        var original = BottleInfo()
        original.name = "Custom Bottle"
        original.blocklist = [URL(fileURLWithPath: "/blocked.exe")]

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)

        let decoded = try PropertyListDecoder().decode(BottleInfo.self, from: data)

        XCTAssertEqual(decoded.name, "Custom Bottle")
        XCTAssertEqual(decoded.blocklist.count, 1)
    }
}

// MARK: - BottleMetalConfig Tests

final class BottleMetalConfigTests: XCTestCase {
    func testDefaultValues() {
        let config = BottleMetalConfig()

        XCTAssertFalse(config.metalHud)
        XCTAssertFalse(config.metalTrace)
        XCTAssertFalse(config.dxrEnabled)
        XCTAssertFalse(config.metalValidation)
    }

    func testRoundTrip() throws {
        var original = BottleMetalConfig()
        original.metalHud = true
        original.metalTrace = true
        original.dxrEnabled = true
        original.metalValidation = true

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)

        let decoded = try PropertyListDecoder().decode(BottleMetalConfig.self, from: data)

        XCTAssertTrue(decoded.metalHud)
        XCTAssertTrue(decoded.metalTrace)
        XCTAssertTrue(decoded.dxrEnabled)
        XCTAssertTrue(decoded.metalValidation)
    }

    func testDecodeWithMissingValuesUsesDefaults() throws {
        let plist: [String: Any] = [:]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let config = try PropertyListDecoder().decode(BottleMetalConfig.self, from: data)

        XCTAssertFalse(config.metalHud)
        XCTAssertFalse(config.metalTrace)
        XCTAssertFalse(config.dxrEnabled)
        XCTAssertFalse(config.metalValidation)
    }
}

// MARK: - BottleDXVKConfig Tests

final class BottleDXVKConfigTests: XCTestCase {
    func testDefaultValues() {
        let config = BottleDXVKConfig()

        XCTAssertFalse(config.dxvk)
        XCTAssertTrue(config.dxvkAsync)
        XCTAssertEqual(config.dxvkHud, .off)
    }

    func testRoundTrip() throws {
        var original = BottleDXVKConfig()
        original.dxvk = true
        original.dxvkAsync = false
        original.dxvkHud = .full

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(original)

        let decoded = try PropertyListDecoder().decode(BottleDXVKConfig.self, from: data)

        XCTAssertTrue(decoded.dxvk)
        XCTAssertFalse(decoded.dxvkAsync)
        XCTAssertEqual(decoded.dxvkHud, .full)
    }

    func testDecodeWithMissingValuesUsesDefaults() throws {
        let plist: [String: Any] = [:]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let config = try PropertyListDecoder().decode(BottleDXVKConfig.self, from: data)

        XCTAssertFalse(config.dxvk)
        XCTAssertTrue(config.dxvkAsync)
        XCTAssertEqual(config.dxvkHud, .off)
    }
}
