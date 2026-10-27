//
//  Rosetta2Tests.swift
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

final class Rosetta2Tests: XCTestCase {
    // MARK: - isRosettaInstalled Property Tests

    func testIsRosettaInstalledChecksCorrectPath() {
        // The Rosetta runtime should be at the standard Apple location
        let rosettaPath = "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
        let fileExists = FileManager.default.fileExists(atPath: rosettaPath)

        // isRosettaInstalled should match whether the file exists
        XCTAssertEqual(Rosetta2.isRosettaInstalled, fileExists)
    }
}
