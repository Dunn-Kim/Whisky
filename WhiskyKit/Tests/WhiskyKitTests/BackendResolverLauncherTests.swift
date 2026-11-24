//
//  BackendResolverLauncherTests.swift
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

final class BackendResolverLauncherTests: XCTestCase {
    /// A launcher does not get what a game does. Chromium cannot render on
    /// DXMT: the window comes up, the process tree looks healthy, nothing paints.
    func testLauncherGetsWineD3D() {
        for launcher in LauncherType.allCases {
            XCTAssertEqual(
                GraphicsBackendResolver.resolve(for: launcher),
                .wined3d,
                "\(launcher.displayName) resolved to a backend its client cannot render on"
            )
        }
    }

    /// Callers that pass nothing keep the game answer.
    func testDefaultArgumentMatchesTheGameCase() {
        XCTAssertEqual(GraphicsBackendResolver.resolve(), GraphicsBackendResolver.resolve(for: nil))
        XCTAssertEqual(GraphicsBackendResolver.resolve(), .dxmt)
    }

    /// A game inside a library is not the client, so it must not be steered onto WineD3D.
    func testLibraryGameResolvesAsAGame() {
        let url = URL(filePath: "/B/Steam/steamapps/common/Some Game/game.exe")
        XCTAssertNil(LauncherType.detect(from: url))
        XCTAssertEqual(GraphicsBackendResolver.resolve(for: LauncherType.detect(from: url)), .dxmt)
    }

    func testSteamClientResolvesAsALauncher() {
        let url = URL(filePath: "/B/Steam/steam.exe")
        XCTAssertEqual(LauncherType.detect(from: url), .steam)
        XCTAssertEqual(GraphicsBackendResolver.resolve(for: LauncherType.detect(from: url)), .wined3d)
    }
}
