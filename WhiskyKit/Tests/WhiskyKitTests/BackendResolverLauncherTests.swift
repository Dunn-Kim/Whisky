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

import SemanticVersion
@testable import WhiskyKit
import XCTest

final class BackendResolverLauncherTests: XCTestCase {
    /// A launcher does not get what a game does. Chromium cannot render on
    /// DXMT: the window comes up, the process tree looks healthy, nothing paints.
    func testLauncherGetsDXVK() {
        for launcher in LauncherType.allCases {
            XCTAssertEqual(
                GraphicsBackendResolver.resolve(for: launcher, runtimeInfo: nil, dxmtRuntimeNative: true),
                .dxvk,
                "\(launcher.displayName) resolved to a backend its client cannot render on"
            )
        }
    }

    /// DXMT is unrenderable for Chromium, so on a runtime that would recommend
    /// DXMT a launcher still gets DXVK. Without the steer, the first Steam
    /// launch deploys DXMT and the client never shows a window.
    func testLauncherGetsDXVKWhenDXMTWouldBeRecommended() {
        let runtime = WhiskyWineVersion(version: SemanticVersion(3, 1, 1), dxmtVersion: "0.80")
        XCTAssertEqual(
            GraphicsBackendResolver.resolve(for: nil, runtimeInfo: runtime, dxmtRuntimeNative: true),
            .dxmt
        )
        XCTAssertEqual(
            GraphicsBackendResolver.resolve(for: .steam, runtimeInfo: runtime, dxmtRuntimeNative: true),
            .dxvk
        )
    }

    /// Without DXMT the answer is DXVK for everyone, so the steer changes
    /// nothing there.
    func testLauncherAndGameAgreeWhenOnlyDXVKExists() {
        let runtime = WhiskyWineVersion(version: SemanticVersion(3, 0, 0))
        let game = GraphicsBackendResolver.resolve(for: nil, runtimeInfo: runtime, dxmtRuntimeNative: false)
        let launcher = GraphicsBackendResolver.resolve(for: .steam, runtimeInfo: runtime, dxmtRuntimeNative: false)
        XCTAssertEqual(game, .dxvk)
        XCTAssertEqual(game, launcher)
    }

    /// Callers that pass nothing keep the old behaviour, so every existing
    /// call site is unaffected.
    func testDefaultArgumentMatchesTheGameCase() {
        XCTAssertEqual(
            GraphicsBackendResolver.resolve(runtimeInfo: nil, dxmtRuntimeNative: true),
            GraphicsBackendResolver.resolve(for: nil, runtimeInfo: nil, dxmtRuntimeNative: true)
        )
    }

    /// A game inside a Steam library is not the Steam client, so it must not
    /// be steered onto DXVK.
    func testSteamLibraryGameResolvesAsAGame() {
        let url = URL(filePath: "/B/Steam/steamapps/common/Some Game/game.exe")
        XCTAssertNil(LauncherType.detect(from: url))
        XCTAssertEqual(
            GraphicsBackendResolver.resolve(
                for: LauncherType.detect(from: url), runtimeInfo: nil, dxmtRuntimeNative: false
            ),
            .dxvk
        )
        let runtime = WhiskyWineVersion(version: SemanticVersion(3, 1, 1), dxmtVersion: "0.80")
        XCTAssertEqual(
            GraphicsBackendResolver.resolve(
                for: LauncherType.detect(from: url), runtimeInfo: runtime, dxmtRuntimeNative: true
            ),
            .dxmt
        )
    }

    func testSteamClientResolvesAsALauncher() {
        let url = URL(filePath: "/B/Steam/steam.exe")
        XCTAssertEqual(LauncherType.detect(from: url), .steam)
        XCTAssertEqual(
            GraphicsBackendResolver.resolve(
                for: LauncherType.detect(from: url), runtimeInfo: nil, dxmtRuntimeNative: true
            ),
            .dxvk
        )
    }
}
