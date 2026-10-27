//
//  ClickOnceManagerTests.swift
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
import Testing
@testable import WhiskyKit

@Suite("ClickOnceManager Tests")
struct ClickOnceManagerTests {
    // MARK: - Detection Tests

    @Test("Detects ClickOnce directory when it doesn't exist")
    @MainActor func detectAppRefFileNoDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bottle = Bottle(bottleUrl: tempDir)
        let appRefs = ClickOnceManager.detectAppRefFile(in: bottle)

        #expect(appRefs.isEmpty, "Should return empty array when ClickOnce directory doesn't exist")
    }

    @Test("Detects ClickOnce appref-ms files")
    @MainActor func detectAppRefFileFindsFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let clickOnceDir = tempDir
            .appending(path: "drive_c")
            .appending(path: "users")
            .appending(path: "crossover")
            .appending(path: "AppData")
            .appending(path: "Roaming")
            .appending(path: "Microsoft")
            .appending(path: "ClickOnce")

        try FileManager.default.createDirectory(at: clickOnceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create test appref-ms files
        let appRef1 = clickOnceDir.appending(path: "TestApp1.appref-ms")
        let appRef2 = clickOnceDir.appending(path: "TestApp2.appref-ms")
        try "Test Content 1".write(to: appRef1, atomically: true, encoding: .utf8)
        try "Test Content 2".write(to: appRef2, atomically: true, encoding: .utf8)

        let bottle = Bottle(bottleUrl: tempDir)
        let appRefs = ClickOnceManager.detectAppRefFile(in: bottle)

        #expect(appRefs.count == 2, "Should detect 2 appref-ms files")
        #expect(appRefs.contains(where: { $0.lastPathComponent == "TestApp1.appref-ms" }))
        #expect(appRefs.contains(where: { $0.lastPathComponent == "TestApp2.appref-ms" }))
    }

    @Test("Ignores non-appref-ms files")
    @MainActor func detectAppRefFileIgnoresOtherFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let clickOnceDir = tempDir
            .appending(path: "drive_c")
            .appending(path: "users")
            .appending(path: "crossover")
            .appending(path: "AppData")
            .appending(path: "Roaming")
            .appending(path: "Microsoft")
            .appending(path: "ClickOnce")

        try FileManager.default.createDirectory(at: clickOnceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create various file types
        let appRef = clickOnceDir.appending(path: "TestApp.appref-ms")
        let textFile = clickOnceDir.appending(path: "readme.txt")
        let exeFile = clickOnceDir.appending(path: "setup.exe")

        try "Test Content".write(to: appRef, atomically: true, encoding: .utf8)
        try "Readme".write(to: textFile, atomically: true, encoding: .utf8)
        try "Fake exe".write(to: exeFile, atomically: true, encoding: .utf8)

        let bottle = Bottle(bottleUrl: tempDir)
        let appRefs = ClickOnceManager.detectAppRefFile(in: bottle)

        #expect(appRefs.count == 1, "Should only detect .appref-ms files")
        #expect(appRefs[0].lastPathComponent == "TestApp.appref-ms")
    }

    // MARK: - Parsing Tests

    private func writeAppRef(_ content: String) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).appref-ms")
        try content.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    @Test("Reads the deployment URL and display name from an appref-ms file")
    func deploymentURLAndDisplayName() throws {
        let file = try writeAppRef("""
        [InternetShortcut]
        URL=http://example.com/apps/TestApp/TestApp.application?version=1.2.3.4
        """)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(ClickOnceManager.deploymentURL(for: file)?.host == "example.com")
        #expect(ClickOnceManager.displayName(for: file) == "TestApp")
    }

    @Test("Decodes a percent-encoded deployment URL")
    func deploymentURLPercentEncoded() throws {
        let file = try writeAppRef("URL=http%3A%2F%2Fexample.com%2Fapp.application")
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(ClickOnceManager.deploymentURL(for: file)?.absoluteString == "http://example.com/app.application")
    }

    @Test("Returns nil and the file name when the file is missing or has no URL")
    func deploymentURLMissing() throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: "nonexistent.appref-ms")
        #expect(ClickOnceManager.deploymentURL(for: missing) == nil)
        #expect(ClickOnceManager.displayName(for: missing) == "nonexistent")

        let noURL = try writeAppRef("[InternetShortcut]\nSomeOtherField=value")
        defer { try? FileManager.default.removeItem(at: noURL) }
        #expect(ClickOnceManager.deploymentURL(for: noURL) == nil)
    }
}
