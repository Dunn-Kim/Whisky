//
//  StabilityDiagnosticsTests.swift
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

@MainActor
final class StabilityDiagnosticsTests: XCTestCase {
    func testReportGenerationWithMissingLogsFolder() async throws {
        let bottleURL = try makeTempDir()

        let bottle = Bottle(bottleUrl: bottleURL, inFlight: false, isAvailable: true)

        let missingLogsFolder = bottleURL.appendingPathComponent("does-not-exist")
        let report = await StabilityDiagnostics.generateDiagnosticReport(for: bottle, logsFolder: missingLogsFolder)
        XCTAssertTrue(report.contains("Whisky Stability Diagnostics Report"))
        XCTAssertTrue(report.contains("[LOGS]"))
        XCTAssertTrue(report.contains("Logs Folder Status: Not found"))
    }

    func testReportGenerationWithEmptyLogsFolder() async throws {
        let bottleURL = try makeTempDir()

        let bottle = Bottle(bottleUrl: bottleURL, inFlight: false, isAvailable: true)

        let logsFolder = bottleURL.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logsFolder, withIntermediateDirectories: true)

        let report = await StabilityDiagnostics.generateDiagnosticReport(for: bottle, logsFolder: logsFolder)
        XCTAssertTrue(report.contains("Log Files: None found"))
    }

    func testTailHandlesInvalidUTF8() throws {
        let tempURL = try makeTempDir()

        let logURL = tempURL.appendingPathComponent("invalid.log")

        // Write bytes that are not valid UTF-8
        let bytes: [UInt8] = [0xFF, 0xFE, 0xFF, 0x00, 0xC3, 0x28]
        try Data(bytes).write(to: logURL)

        let tail = StabilityDiagnostics.tailOfLogFile(logURL)
        XCTAssertTrue(tail.contains("not UTF-8"))
    }

    func testTailKeepsLastLinesBounded() throws {
        let tempURL = try makeTempDir()

        let logURL = tempURL.appendingPathComponent("many-lines.log")

        // 250 lines: tail should return <= 200 lines.
        let content = (0 ..< 250).map { "line-\($0)" }.joined(separator: "\n")
        try content.write(to: logURL, atomically: true, encoding: .utf8)

        let tail = StabilityDiagnostics.tailOfLogFile(logURL)
        let lineCount = tail.split(separator: "\n", omittingEmptySubsequences: false).count
        XCTAssertLessThanOrEqual(lineCount, 200)
        XCTAssertTrue(tail.contains("line-249"))
        XCTAssertFalse(tail.contains("line-0"))
    }

    func testReportIncludesArchitectureLine() async throws {
        let bottleURL = try makeTempDir()

        let bottle = Bottle(bottleUrl: bottleURL, inFlight: false, isAvailable: true)
        let report = await StabilityDiagnostics.generateDiagnosticReport(for: bottle, logsFolder: bottleURL.appendingPathComponent("does-not-exist"))

        #if arch(arm64)
        XCTAssertTrue(report.contains("Architecture: Apple Silicon (arm64)"))
        #else
        XCTAssertTrue(report.contains("Architecture: Intel (x86_64)"))
        #endif
    }
}
