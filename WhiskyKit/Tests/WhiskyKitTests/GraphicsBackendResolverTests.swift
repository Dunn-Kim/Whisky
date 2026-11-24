//
//  GraphicsBackendResolverTests.swift
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

final class GraphicsBackendResolverTests: XCTestCase {
    func testResolvesDXMTWhenRuntimeBundlesIt() {
        let runtime = WhiskyWineVersion(version: SemanticVersion(3, 1, 1), dxmtVersion: "0.80")

        XCTAssertEqual(
            GraphicsBackendResolver.resolve(runtimeInfo: runtime, dxmtRuntimeNative: true),
            .dxmt
        )
    }

    /// The version record alone is not the gate the picker applies: a
    /// builtin-variant or missing DXMT payload fails at launch, so auto must
    /// not promise a backend the picker would refuse.
    func testResolvesDXVKWhenDXMTPayloadNotNative() {
        let runtime = WhiskyWineVersion(version: SemanticVersion(3, 1, 1), dxmtVersion: "0.80")

        XCTAssertEqual(
            GraphicsBackendResolver.resolve(runtimeInfo: runtime, dxmtRuntimeNative: false),
            .dxvk
        )
    }

    func testResolvesDXVKWhenNoDXMT() {
        // Pre-3.1.0 runtimes bundle DXVK but not DXMT.
        let runtime = WhiskyWineVersion(version: SemanticVersion(3, 0, 0))

        XCTAssertEqual(
            GraphicsBackendResolver.resolve(runtimeInfo: runtime, dxmtRuntimeNative: false),
            .dxvk
        )
    }

    func testResolvesDXVKWhenRuntimeRecordMissing() {
        XCTAssertEqual(
            GraphicsBackendResolver.resolve(runtimeInfo: nil, dxmtRuntimeNative: false),
            .dxvk
        )
    }

    func testNeverResolvesToRecommended() {
        XCTAssertNotEqual(
            GraphicsBackendResolver.resolve(runtimeInfo: nil, dxmtRuntimeNative: false),
            .recommended
        )
    }
}
