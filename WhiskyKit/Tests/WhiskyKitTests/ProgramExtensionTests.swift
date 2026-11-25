//
//  ProgramExtensionTests.swift
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

// MARK: - Program.generateEnvironment Tests

final class ProgramGenerateEnvironmentTests: XCTestCase {
    var tempDir: URL!
    var bottleURL: URL!
    var programURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "env_test_\(UUID().uuidString)")
        bottleURL = tempDir.appending(path: "TestBottle")

        let driveCURL = bottleURL.appending(path: "drive_c")
        try? FileManager.default.createDirectory(at: driveCURL, withIntermediateDirectories: true)

        programURL = driveCURL.appending(path: "test.exe")
        try? Data("fake exe".utf8).write(to: programURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    @MainActor
    func testGenerateEnvironmentWithAutoLocale() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)
        program.settings.locale = .auto

        let env = program.generateEnvironment()

        // Auto locale should not set LC_ALL
        XCTAssertNil(env["LC_ALL"], "LC_ALL should not be set with auto locale")
    }

    @MainActor
    func testGenerateEnvironmentWithSpecificLocale() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)
        program.settings.locale = .german

        let env = program.generateEnvironment()

        // Specific locale should set LC_ALL
        XCTAssertEqual(env["LC_ALL"], Locales.german.rawValue, "LC_ALL should be set to German locale")
    }

    @MainActor
    func testGenerateEnvironmentWithCustomVariables() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)
        program.settings.environment = ["CUSTOM_VAR": "custom_value"]

        let env = program.generateEnvironment()

        XCTAssertEqual(env["CUSTOM_VAR"], "custom_value", "Custom environment variable should be included")
    }

    @MainActor
    func testGenerateEnvironmentWithMultipleCustomVariables() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)
        program.settings.environment = [
            "VAR1": "value1",
            "VAR2": "value2",
            "VAR3": "value3"
        ]

        let env = program.generateEnvironment()

        XCTAssertEqual(env["VAR1"], "value1")
        XCTAssertEqual(env["VAR2"], "value2")
        XCTAssertEqual(env["VAR3"], "value3")
    }

    @MainActor
    func testGenerateEnvironmentCombinesLocaleAndCustomVars() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let program = Program(url: programURL, bottle: bottle)
        program.settings.locale = .japanese
        program.settings.environment = ["MY_VAR": "my_value"]

        let env = program.generateEnvironment()

        XCTAssertEqual(env["LC_ALL"], Locales.japanese.rawValue)
        XCTAssertEqual(env["MY_VAR"], "my_value")
    }
}

// MARK: - Program.launchWithUserMode in-flight guard

final class ProgramLaunchInFlightTests: XCTestCase {
    @MainActor
    private func makeProgram() throws -> Program {
        let bottleURL = try makeTempDir().appending(path: "TestBottle")
        let driveC = bottleURL.appending(path: "drive_c")
        try FileManager.default.createDirectory(at: driveC, withIntermediateDirectories: true)
        let exe = driveC.appending(path: "game.exe")
        try Data("fake exe".utf8).write(to: exe)
        return Program(url: exe, bottle: Bottle(bottleUrl: bottleURL))
    }

    /// With no Wine runtime a real launch fails, so `.launchedSuccessfully`
    /// can only come from the request being ignored.
    @MainActor
    func testRequestIsIgnoredWhileLaunchInFlight() async throws {
        let program = try makeProgram()
        Program.launchesInFlight.insert(program.url)
        defer { Program.launchesInFlight.remove(program.url) }

        let result = await program.launchWithUserMode(useTerminal: false)

        guard case .launchedSuccessfully = result else {
            return XCTFail("Expected the in-flight request to be ignored, got \(result)")
        }
    }

    @MainActor
    func testProgramCanLaunchAgainOnceLaunchReturns() async throws {
        try XCTSkipIf(
            FileManager.default.isExecutableFile(atPath: Wine.wineBinary.path(percentEncoded: false)),
            "A Wine runtime is installed for the test host"
        )
        let program = try makeProgram()

        let first = await program.launchWithUserMode(useTerminal: false)

        XCTAssertTrue(Program.launchesInFlight.isEmpty)
        guard case .launchFailed = first else { return XCTFail("Expected a failed launch, got \(first)") }
        let second = await program.launchWithUserMode(useTerminal: false)
        guard case .launchFailed = second else { return XCTFail("Expected a real launch, got \(second)") }
    }
}
