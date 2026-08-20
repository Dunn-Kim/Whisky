//
//  WineProcessScannerTests.swift
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

final class WineProcessScannerTests: XCTestCase {
    /// The native proc APIs must be usable — a `nil` result would silently push the
    /// Processes page back to spawning a Wine process on every polling tick.
    func testNativeEnumerationIsAvailable() {
        XCTAssertNotNil(WineProcessScanner.runningWinePIDs())
    }

    /// The scan must only ever report Wine processes: the test runner is not one,
    /// and PID 0 (kernel) can never satisfy an executable-path prefix match.
    func testResultContainsNoForeignProcesses() throws {
        let pids = try XCTUnwrap(WineProcessScanner.runningWinePIDs())
        XCTAssertFalse(pids.contains(ProcessInfo.processInfo.processIdentifier))
        XCTAssertFalse(pids.contains(0))
    }
}
