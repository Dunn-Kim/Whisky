//
//  PathHandlingTests.swift
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

/// Tests for shortcut bundle creation, including paths with special characters.
final class PathHandlingTests: XCTestCase {
    func testShortcutCreatorCreatesBundleStructure() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "PathHandlingTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appURL = tempDir.appending(path: "Test Game.app")
        let launchScript = "echo hello"

        try ShortcutCreator.createShortcutBundle(at: appURL, launchScript: launchScript)

        // Verify bundle structure
        let contentsURL = appURL.appending(path: "Contents")
        let macosURL = contentsURL.appending(path: "MacOS")
        let launchURL = macosURL.appending(path: "launch")
        let infoPlistURL = contentsURL.appending(path: "Info.plist")

        XCTAssertTrue(FileManager.default.fileExists(atPath: launchURL.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: infoPlistURL.path(percentEncoded: false)))

        // Verify launch script content
        let scriptContent = try String(contentsOf: launchURL, encoding: .utf8)
        XCTAssertTrue(scriptContent.hasPrefix("#!/bin/bash\n"))
        XCTAssertTrue(scriptContent.contains("echo hello"))

        // Verify launch script is executable (0o755)
        let attributes = try FileManager.default.attributesOfItem(atPath: launchURL.path(percentEncoded: false))
        let permissions = attributes[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o755)
    }

    func testShortcutCreatorWithSpecialCharactersInPath() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "PathHandlingTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create an app bundle with special characters in the name
        let appURL = tempDir.appending(path: "John's Game (x86).app")
        let launchScript = "/path/to/wine start /unix /path/to/John\\'s\\ Game\\ \\(x86\\)/game.exe"

        try ShortcutCreator.createShortcutBundle(at: appURL, launchScript: launchScript)

        let launchURL = appURL.appending(path: "Contents").appending(path: "MacOS").appending(path: "launch")
        XCTAssertTrue(FileManager.default.fileExists(atPath: launchURL.path(percentEncoded: false)))

        let scriptContent = try String(contentsOf: launchURL, encoding: .utf8)
        XCTAssertTrue(scriptContent.contains("John\\'s\\ Game"))
    }
}
