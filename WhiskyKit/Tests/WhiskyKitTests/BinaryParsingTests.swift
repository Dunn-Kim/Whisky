//
//  BinaryParsingTests.swift
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

// MARK: - LinkFlags Tests

final class LinkFlagsTests: XCTestCase {
    func testLinkFlagsHasLinkTargetIDList() {
        let flags = LinkFlags.hasLinkTargetIDList
        XCTAssertEqual(flags.rawValue, 1 << 0)
        XCTAssertTrue(flags.contains(.hasLinkTargetIDList))
    }

    func testLinkFlagsHasLinkInfo() {
        let flags = LinkFlags.hasLinkInfo
        XCTAssertEqual(flags.rawValue, 1 << 1)
        XCTAssertTrue(flags.contains(.hasLinkInfo))
    }
}

// MARK: - LinkInfoFlags Tests

final class LinkInfoFlagsTests: XCTestCase {
    func testLinkInfoFlagsVolumeIDAndLocalBasePath() {
        let flags = LinkInfoFlags.volumeIDAndLocalBasePath
        XCTAssertEqual(flags.rawValue, 1 << 0)
        XCTAssertTrue(flags.contains(.volumeIDAndLocalBasePath))
    }
}
