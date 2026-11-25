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
    /// The scan must only ever report Wine processes: the test runner is not one,
    /// and PID 0 (kernel) can never satisfy an executable-path prefix match.
    func testResultContainsNoForeignProcesses() throws {
        let pids = try XCTUnwrap(WineProcessScanner.runningWinePIDs())
        XCTAssertFalse(pids.contains(ProcessInfo.processInfo.processIdentifier))
        XCTAssertFalse(pids.contains(0))
    }

    /// A root matches the processes whose executable lies under it, and nothing
    /// else, so a scan that found nothing at all would fail here.
    func testRootScopesTheScan() throws {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(getpid(), &buffer, UInt32(buffer.count))
        XCTAssertGreaterThan(length, 0)
        let ownFolder = URL(fileURLWithPath: String(cString: buffer)).deletingLastPathComponent().path + "/"

        let own = try XCTUnwrap(WineProcessScanner.runningPIDs(under: ownFolder))
        XCTAssertTrue(own.contains(getpid()))
        let none = try XCTUnwrap(WineProcessScanner.runningPIDs(under: "/no-such-\(UUID())/"))
        XCTAssertTrue(none.isEmpty)
    }
}
