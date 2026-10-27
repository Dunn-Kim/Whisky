//
//  WineConfigTests.swift
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

// MARK: - LauncherType Tests

final class LauncherTypeTests: XCTestCase {
    func testLauncherTypeRawValues() {
        XCTAssertEqual(LauncherType.steam.rawValue, "Steam")
        XCTAssertEqual(LauncherType.rockstar.rawValue, "Rockstar Games Launcher")
        XCTAssertEqual(LauncherType.eaApp.rawValue, "EA App")
        XCTAssertEqual(LauncherType.epicGames.rawValue, "Epic Games Store")
        XCTAssertEqual(LauncherType.ubisoft.rawValue, "Ubisoft Connect")
        XCTAssertEqual(LauncherType.battleNet.rawValue, "Battle.net")
        XCTAssertEqual(LauncherType.paradox.rawValue, "Paradox Launcher")
    }
}

// MARK: - WhiskyWineInstaller Path Tests

final class WhiskyWineInstallerPathTests: XCTestCase {
    func testLibraryFolderPath() {
        let path = WhiskyWineInstaller.libraryFolder.path

        XCTAssertTrue(path.contains("Library"))
        XCTAssertTrue(path.contains("Application Support"))
    }

    func testBinFolderPath() {
        let path = WhiskyWineInstaller.binFolder.path

        XCTAssertTrue(path.contains("bin"))
    }
}
