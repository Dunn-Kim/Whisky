//
//  EngineFeedTests.swift
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
import Testing
@testable import WhiskyKit

@Suite("Engine update feeds")
struct EngineFeedTests {
    /// This arm64 build must never read a feed naming an x86_64 engine, which
    /// it could download but not run.
    @Test("The app reads the arm64 feed for both feed URLs")
    func readsTheArm64Feed() {
        let arm64Feed = "https://raw.githubusercontent.com/Dunn-Kim/Whisky/arm64-native"
            + "/dist/pages/WhiskyWineVersion-arm64.plist"
        #expect(DistributionConfig.versionPlistURL == arm64Feed)
        #expect(DistributionConfig.legacyVersionPlistURL == arm64Feed)
    }

    /// The published feeds decode as the app reads them: the old one still on
    /// 3.1.1, the new one on a GPTK-capable 4.x engine with a digest.
    @Test("The published feeds name the engines each app line should get")
    func publishedFeedsDecode() throws {
        let pages = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "dist/pages")
        let decoder = PropertyListDecoder()
        let legacy = try decoder.decode(
            WhiskyWineVersion.self, from: Data(contentsOf: pages.appending(path: "WhiskyWineVersion.plist"))
        )
        let current = try decoder.decode(
            WhiskyWineVersion.self, from: Data(contentsOf: pages.appending(path: "WhiskyWineVersion-v4.plist"))
        )
        #expect(legacy.version == SemanticVersion(3, 1, 1))
        #expect(current.version.major == 4)
        #expect(current.gptkCapable == true)
        #expect(current.sha256?.count == 64)
    }
}
