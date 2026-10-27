//
//  ExtensionTests.swift
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

// MARK: - String.esc Tests

final class StringEscapeTests: XCTestCase {
    func testEsc() {
        let cases: [(input: String, expected: String)] = [
            // Metacharacters
            ("hello world", "hello\\ world"),
            ("hello\"world", "hello\\\"world"),
            ("hello'world", "hello\\'world"),
            ("hello\\world", "hello\\\\world"),
            ("func()", "func\\(\\)"),
            ("[test]{x}", "\\[test\\]\\{x\\}"),
            ("a & b | c ; d", "a\\ \\&\\ b\\ \\|\\ c\\ \\;\\ d"),
            ("in < f > o", "in\\ \\<\\ f\\ \\>\\ o"),
            ("`cmd`", "\\`cmd\\`"),
            ("${VAR}", "\\$\\{VAR\\}"),
            ("test!", "test\\!"),
            ("*.txt file?", "\\*.txt\\ file\\?"),
            ("#comment", "\\#comment"),
            ("~/Documents", "\\~/Documents"),
            ("KEY=VALUE", "KEY\\=VALUE"),
            ("Program Files (x86)/Game's Name", "Program\\ Files\\ \\(x86\\)/Game\\'s\\ Name"),
            ("/path/to/Game [Special]/Tom & Jerry", "/path/to/Game\\ \\[Special\\]/Tom\\ \\&\\ Jerry"),
            // Control characters are dropped before escaping (command-injection guard)
            ("a\nb\n\n\tc\rd\r\ne", "abcde"),
            ("a\0b\u{07}c\u{1B}d\u{7F}e", "abcde"),
            ("file\nwith spaces\t& special$chars\r", "filewith\\ spaces\\&\\ special\\$chars"),
            // Non-ASCII passes through
            ("日本語Ü", "日本語Ü"),
            ("émoji 🎉 файл", "émoji\\ 🎉\\ файл"),
            // Nothing to escape
            ("", ""),
            ("path/to/file.txt", "path/to/file.txt")
        ]
        for (input, expected) in cases {
            XCTAssertEqual(input.esc, expected, "esc of \(input.debugDescription)")
        }
    }
}

// MARK: - URL.esc Tests

final class URLEscapeTests: XCTestCase {
    func testURLEscUsesPathEsc() {
        let url = URL(filePath: "/path/with spaces/file.txt")
        XCTAssertEqual(url.esc, "/path/with\\ spaces/file.txt")
    }

    func testURLEscWithSpecialCharacters() {
        let url = URL(filePath: "/Users/test/Program Files (x86)")
        XCTAssertTrue(url.esc.contains("\\ "))
        XCTAssertTrue(url.esc.contains("\\("))
    }
}

// MARK: - URL.prettyPath Tests

final class URLPrettyPathTests: XCTestCase {
    func testPrettyPathReplacesHomeDirectory() {
        let username = NSUserName()
        let url = URL(filePath: "/Users/\(username)/Documents/test.txt")
        let pretty = url.prettyPath()

        XCTAssertTrue(pretty.hasPrefix("~"))
        XCTAssertFalse(pretty.contains("/Users/\(username)"))
    }

    func testPrettyPathPreservesOtherPaths() {
        let url = URL(filePath: "/var/log/system.log")
        let pretty = url.prettyPath()

        XCTAssertEqual(pretty, "/var/log/system.log")
    }
}

// MARK: - URL.prettyPath(bottle:) Tests

final class URLPrettyPathBottleTests: XCTestCase {
    var tempDir: URL!
    var bottleURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appending(path: "prettypath_\(UUID().uuidString)")
        bottleURL = tempDir.appending(path: "TestBottle")

        let driveCURL = bottleURL.appending(path: "drive_c")
        try? FileManager.default.createDirectory(at: driveCURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    @MainActor
    func testPrettyPathRemovesBottlePath() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let programURL = bottleURL.appending(path: "drive_c/Program Files/game.exe")

        let pretty = programURL.prettyPath(bottle)

        XCTAssertFalse(pretty.contains(bottleURL.path(percentEncoded: false)))
    }

    @MainActor
    func testPrettyPathConvertsDriveCToWindowsStyle() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let programURL = bottleURL.appending(path: "drive_c/Program Files/game.exe")

        let pretty = programURL.prettyPath(bottle)

        XCTAssertTrue(pretty.hasPrefix("C:\\"))
        XCTAssertFalse(pretty.contains("/drive_c/"))
    }

    @MainActor
    func testPrettyPathConvertsSlashesToBackslashes() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let programURL = bottleURL.appending(path: "drive_c/Program Files/SubDir/game.exe")

        let pretty = programURL.prettyPath(bottle)

        XCTAssertFalse(pretty.contains("/"))
        XCTAssertTrue(pretty.contains("\\"))
    }

    @MainActor
    func testPrettyPathFullConversion() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let programURL = bottleURL.appending(path: "drive_c/Program Files/MyGame/game.exe")

        let pretty = programURL.prettyPath(bottle)

        XCTAssertEqual(pretty, "C:\\Program Files\\MyGame\\game.exe")
    }

    @MainActor
    func testPrettyPathWithSpacesInPath() {
        let bottle = Bottle(bottleUrl: bottleURL)
        let programURL = bottleURL.appending(path: "drive_c/Program Files (x86)/My Game Name/launcher.exe")

        let pretty = programURL.prettyPath(bottle)

        XCTAssertEqual(pretty, "C:\\Program Files (x86)\\My Game Name\\launcher.exe")
    }
}

// MARK: - URL.updateParentBottle Tests

final class URLUpdateParentBottleTests: XCTestCase {
    func testUpdateParentBottle() {
        let oldBottle = URL(filePath: "/Users/test/Bottles/OldBottle")
        let newBottle = URL(filePath: "/Users/test/Bottles/NewBottle")
        let programURL = URL(filePath: "/Users/test/Bottles/OldBottle/drive_c/Program Files/game.exe")

        let updated = programURL.updateParentBottle(old: oldBottle, new: newBottle)

        XCTAssertEqual(
            updated.path(percentEncoded: false),
            "/Users/test/Bottles/NewBottle/drive_c/Program Files/game.exe"
        )
    }

    func testUpdateParentBottleWithTrailingSlash() {
        let oldBottle = URL(filePath: "/Bottles/OldBottle/")
        let newBottle = URL(filePath: "/Bottles/NewBottle/")
        let programURL = URL(filePath: "/Bottles/OldBottle/drive_c/test.exe")

        let updated = programURL.updateParentBottle(old: oldBottle, new: newBottle)

        XCTAssertEqual(updated.path(percentEncoded: false), "/Bottles/NewBottle/drive_c/test.exe")
    }

    func testUpdateParentBottleNoMatch() {
        let oldBottle = URL(filePath: "/Bottles/OtherBottle")
        let newBottle = URL(filePath: "/Bottles/NewBottle")
        let programURL = URL(filePath: "/Bottles/DifferentBottle/drive_c/test.exe")

        let updated = programURL.updateParentBottle(old: oldBottle, new: newBottle)

        XCTAssertEqual(updated.path(percentEncoded: false), "/Bottles/DifferentBottle/drive_c/test.exe")
    }
}

// MARK: - Bundle Extension Tests

final class BundleExtensionTests: XCTestCase {
    func testWhiskyBundleIdentifierUsesMainBundleOrFallback() {
        let identifier = Bundle.whiskyBundleIdentifier
        // In tests, returns test bundle identifier; in production returns main bundle or fallback
        // Either way, should be a valid bundle identifier string
        XCTAssertTrue(identifier.contains("."), "Bundle identifier should contain at least one dot")
    }
}

// MARK: - URL Identifiable Tests

final class URLIdentifiableTests: XCTestCase {
    func testURLIdIsItself() {
        let url = URL(filePath: "/test/path")
        XCTAssertEqual(url.id, url)
    }
}
