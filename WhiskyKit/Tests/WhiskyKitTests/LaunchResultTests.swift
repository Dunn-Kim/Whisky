//
//  LaunchResultTests.swift
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

final class LaunchResultTests: XCTestCase {
    // MARK: - Enum Case Creation Tests

    func testLaunchedSuccessfullyCreation() {
        let result = LaunchResult.launchedSuccessfully(programName: "TestApp.exe")

        if case let .launchedSuccessfully(name) = result {
            XCTAssertEqual(name, "TestApp.exe")
        } else {
            XCTFail("Expected launchedSuccessfully case")
        }
    }

    func testLaunchedInTerminalCreation() {
        let result = LaunchResult.launchedInTerminal(programName: "Steam.exe")

        if case let .launchedInTerminal(name) = result {
            XCTAssertEqual(name, "Steam.exe")
        } else {
            XCTFail("Expected launchedInTerminal case")
        }
    }

    func testLaunchFailedCreation() {
        let result = LaunchResult.launchFailed(programName: "Broken.exe", errorDescription: "File not found")

        if case let .launchFailed(name, error) = result {
            XCTAssertEqual(name, "Broken.exe")
            XCTAssertEqual(error, "File not found")
        } else {
            XCTFail("Expected launchFailed case")
        }
    }

    // MARK: - Sendable Conformance Tests

    func testSendableConformanceWithSuccessfulLaunch() async {
        let result = LaunchResult.launchedSuccessfully(programName: "App.exe")

        // Verify we can safely pass across actor boundaries
        let capturedResult = await Task.detached {
            result
        }.value

        guard case let .launchedSuccessfully(name) = capturedResult else {
            return XCTFail("Expected launchedSuccessfully case")
        }
        XCTAssertEqual(name, "App.exe")
    }

    func testSendableConformanceWithTerminalLaunch() async {
        let result = LaunchResult.launchedInTerminal(programName: "App.exe")

        let capturedResult = await Task.detached {
            result
        }.value

        guard case let .launchedInTerminal(name) = capturedResult else {
            return XCTFail("Expected launchedInTerminal case")
        }
        XCTAssertEqual(name, "App.exe")
    }

    func testSendableConformanceWithFailedLaunch() async {
        let result = LaunchResult.launchFailed(programName: "App.exe", errorDescription: "Error")

        let capturedResult = await Task.detached {
            result
        }.value

        guard case let .launchFailed(name, error) = capturedResult else {
            return XCTFail("Expected launchFailed case")
        }
        XCTAssertEqual(name, "App.exe")
        XCTAssertEqual(error, "Error")
    }

    // MARK: - Equality Tests (via switch matching)

    func testDistinctCasesAreDifferent() {
        let success = LaunchResult.launchedSuccessfully(programName: "App.exe")
        let terminal = LaunchResult.launchedInTerminal(programName: "App.exe")
        let failed = LaunchResult.launchFailed(programName: "App.exe", errorDescription: "Error")

        // Each case should match only itself
        if case .launchedSuccessfully = success {
            // Expected
        } else {
            XCTFail("success should match launchedSuccessfully")
        }

        if case .launchedInTerminal = terminal {
            // Expected
        } else {
            XCTFail("terminal should match launchedInTerminal")
        }

        if case .launchFailed = failed {
            // Expected
        } else {
            XCTFail("failed should match launchFailed")
        }
    }
}
