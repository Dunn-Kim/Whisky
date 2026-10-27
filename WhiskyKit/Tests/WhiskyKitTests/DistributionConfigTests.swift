//
//  DistributionConfigTests.swift
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

final class DistributionConfigTests: XCTestCase {
    func testBaseURL() {
        XCTAssertEqual(DistributionConfig.baseURL, "https://frankea.github.io/Whisky")
    }

    func testVersionPlistURL() {
        XCTAssertEqual(DistributionConfig.versionPlistURL, "https://frankea.github.io/Whisky/WhiskyWineVersion.plist")
    }

    func testReleasesBaseURL() {
        XCTAssertEqual(DistributionConfig.releasesBaseURL, "https://github.com/frankea/Whisky/releases/download")
    }

    func testLibrariesURL() {
        for version in ["0.0.0", "2.5.0", "10.20.30"] {
            XCTAssertEqual(
                DistributionConfig.librariesURL(version: version),
                "https://github.com/frankea/Whisky/releases/download/v\(version)/Libraries.tar.gz"
            )
        }
    }

    /// The version-to-URL workflow as used in WhiskyWineDownloadView.fetchVersionAndDownload()
    func testCompleteVersionFetchToDownloadURLWorkflow() throws {
        let plist: [String: Any] = ["version": ["major": 2, "minor": 5, "patch": 0]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let version = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data).version

        let downloadURL = DistributionConfig.librariesURL(version: "\(version.major).\(version.minor).\(version.patch)")

        XCTAssertEqual(downloadURL, "https://github.com/frankea/Whisky/releases/download/v2.5.0/Libraries.tar.gz")
    }
}
