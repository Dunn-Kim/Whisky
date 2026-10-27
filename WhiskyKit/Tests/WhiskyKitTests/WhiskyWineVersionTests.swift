//
//  WhiskyWineVersionTests.swift
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

extension WhiskyWineVersion {
    /// Test fixture: builds the value the way the app gets it, by decoding a runtime plist.
    init(
        version: SemanticVersion, dxvkVersion: String? = nil, dxmtVersion: String? = nil,
        sha256: String? = nil, gptkCapable: Bool? = nil, msyncCapable: Bool? = nil
    ) {
        var plist: [String: Any] = ["version": ["major": version.major, "minor": version.minor, "patch": version.patch]]
        plist["dxvkVersion"] = dxvkVersion
        plist["dxmtVersion"] = dxmtVersion
        plist["sha256"] = sha256
        plist["gptkCapable"] = gptkCapable
        plist["msyncCapable"] = msyncCapable
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        self = try! PropertyListDecoder().decode(Self.self, from: data)
    }
}

// MARK: - Decoding Tests

final class WhiskyWineVersionDecodingTests: XCTestCase {
    func testDecodeValidPlist() throws {
        let plist: [String: Any] = [
            "version": ["major": 2, "minor": 5, "patch": 0]
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        XCTAssertEqual(versionInfo.version.major, 2)
        XCTAssertEqual(versionInfo.version.minor, 5)
        XCTAssertEqual(versionInfo.version.patch, 0)
        XCTAssertEqual(versionInfo.version, SemanticVersion(2, 5, 0))
    }

    func testDecodeWithDifferentVersions() throws {
        let testCases: [VersionComponents] = [
            VersionComponents(major: 1, minor: 0, patch: 0),
            VersionComponents(major: 2, minor: 5, patch: 0),
            VersionComponents(major: 10, minor: 20, patch: 30),
            VersionComponents(major: 0, minor: 0, patch: 1),
            VersionComponents(major: 99, minor: 99, patch: 99)
        ]

        for testCase in testCases {
            let plist: [String: Any] = [
                "version": [
                    "major": testCase.major,
                    "minor": testCase.minor,
                    "patch": testCase.patch
                ]
            ]

            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

            XCTAssertEqual(versionInfo.version.major, testCase.major)
            XCTAssertEqual(versionInfo.version.minor, testCase.minor)
            XCTAssertEqual(versionInfo.version.patch, testCase.patch)
            XCTAssertEqual(
                versionInfo.version,
                SemanticVersion(testCase.major, testCase.minor, testCase.patch)
            )
        }
    }
}

// MARK: - Error Handling Tests

final class WhiskyWineVersionErrorTests: XCTestCase {
    func testDecodeMissingVersionKey() {
        let plist: [String: Any] = [:]
        assertDecodingError(for: plist)
    }

    func testDecodeMissingMajorKey() {
        let plist: [String: Any] = ["version": ["minor": 5, "patch": 0]]
        assertDecodingError(for: plist)
    }

    func testDecodeMissingMinorKey() {
        let plist: [String: Any] = ["version": ["major": 2, "patch": 0]]
        assertDecodingError(for: plist)
    }

    func testDecodeMissingPatchKey() {
        let plist: [String: Any] = ["version": ["major": 2, "minor": 5]]
        assertDecodingError(for: plist)
    }

    func testDecodeInvalidVersionType() {
        let plist: [String: Any] = ["version": "invalid"]
        assertDecodingError(for: plist)
    }

    func testDecodeInvalidMajorType() {
        let plist: [String: Any] = ["version": ["major": "invalid", "minor": 5, "patch": 0]]
        assertDecodingError(for: plist)
    }

    func testDecodeInvalidMinorType() {
        let plist: [String: Any] = ["version": ["major": 2, "minor": "invalid", "patch": 0]]
        assertDecodingError(for: plist)
    }

    func testDecodeInvalidPatchType() {
        let plist: [String: Any] = ["version": ["major": 2, "minor": 5, "patch": "invalid"]]
        assertDecodingError(for: plist)
    }

    func testDecodeInvalidPlistData() {
        let invalidData = Data("invalid plist data".utf8)

        do {
            _ = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: invalidData)
            XCTFail("Should throw error when plist data is invalid")
        } catch {
            XCTAssertNotNil(error, "Should throw error for invalid plist data")
        }
    }

    private func assertDecodingError(for plist: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            _ = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)
            XCTFail("Should throw DecodingError", file: file, line: line)
        } catch {
            XCTAssertTrue(error is DecodingError, "Should throw DecodingError", file: file, line: line)
        }
    }
}

// MARK: - DXVK Version Tests

final class WhiskyWineVersionDXVKTests: XCTestCase {
    func testDecodeWithDXVKVersion() throws {
        let plist: [String: Any] = [
            "version": ["major": 3, "minor": 0, "patch": 0],
            "dxvkVersion": "1.10.3"
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        XCTAssertEqual(versionInfo.version, SemanticVersion(3, 0, 0))
        XCTAssertEqual(versionInfo.dxvkVersion, "1.10.3")
    }

    func testDecodeWithoutDXVKVersionIsNil() throws {
        // Older runtime plists predate the dxvkVersion key and must still decode.
        let plist: [String: Any] = [
            "version": ["major": 3, "minor": 0, "patch": 0]
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        XCTAssertNil(versionInfo.dxvkVersion)
    }
}

// MARK: - DXMT Version Tests

final class WhiskyWineVersionDXMTTests: XCTestCase {
    func testDecodeWithDXMTVersion() throws {
        let plist: [String: Any] = [
            "version": ["major": 3, "minor": 1, "patch": 0],
            "dxvkVersion": "1.10.3",
            "dxmtVersion": "0.80"
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        XCTAssertEqual(versionInfo.version, SemanticVersion(3, 1, 0))
        XCTAssertEqual(versionInfo.dxmtVersion, "0.80")
    }

    func testDecodeWithoutDXMTVersionIsNil() throws {
        // Runtime plists before v3.1.0 predate the dxmtVersion key and must still decode.
        let plist: [String: Any] = [
            "version": ["major": 3, "minor": 0, "patch": 0],
            "dxvkVersion": "1.10.3"
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        XCTAssertNil(versionInfo.dxmtVersion)
    }

    func testBlankDXMTVersionNormalizesToNil() throws {
        // "Absent" and "blank" must map to the same state, like dxvkVersion.
        let plist: [String: Any] = [
            "version": ["major": 3, "minor": 1, "patch": 0],
            "dxmtVersion": ""
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

        XCTAssertNil(versionInfo.dxmtVersion)
    }
}

// MARK: - Test Helper Types

private struct VersionComponents {
    let major: Int
    let minor: Int
    let patch: Int
}
