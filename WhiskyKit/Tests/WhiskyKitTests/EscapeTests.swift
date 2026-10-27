//
//  EscapeTests.swift
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

/// Tests for String.esc and URL.esc shell escaping extensions
final class EscapeTests: XCTestCase {
    // MARK: - Array Argument Escaping Tests

    func testArrayArgumentsEscapedIndividually() {
        // When escaping an array of arguments, each should be escaped individually
        // This preserves argument boundaries for the shell
        let args = ["--name", "Player Name"]
        let escapedArgs = args.map(\.esc).joined(separator: " ")

        // The result should have TWO shell words: "--name" and "Player\ Name"
        // NOT one shell word: "--name\ Player\ Name"
        XCTAssertEqual(escapedArgs, "--name Player\\ Name")

        // Verify "--name" is NOT escaped (no metacharacters)
        XCTAssertTrue(escapedArgs.hasPrefix("--name "))

        // Verify "Player Name" has its space escaped
        XCTAssertTrue(escapedArgs.hasSuffix("Player\\ Name"))
    }

    func testArrayArgumentsWithMultipleSpacedArgs() {
        let args = ["--player", "John Doe", "--server", "My Server"]
        let escapedArgs = args.map(\.esc).joined(separator: " ")

        // Should be 4 separate shell arguments
        XCTAssertEqual(escapedArgs, "--player John\\ Doe --server My\\ Server")
    }

    func testArrayArgumentsPreservesEmptyArray() {
        let args: [String] = []
        let escapedArgs = args.map(\.esc).joined(separator: " ")

        XCTAssertEqual(escapedArgs, "")
    }

    func testArrayArgumentsWithSpecialCharacters() {
        let args = ["--path", "/Program Files (x86)/Game"]
        let escapedArgs = args.map(\.esc).joined(separator: " ")

        // Path should have spaces and parentheses escaped
        XCTAssertTrue(escapedArgs.contains("Program\\ Files"))
        XCTAssertTrue(escapedArgs.contains("\\(x86\\)"))
    }

    func testSingleStringEscapingVsArrayEscaping() {
        // Demonstrates the difference between escaping a joined string vs array elements

        // Method 1: Join then escape (WRONG for preserving argument boundaries)
        let args = ["--name", "Player Name"]
        let joinedThenEscaped = args.joined(separator: " ").esc
        // This escapes ALL spaces, making it one argument
        XCTAssertEqual(joinedThenEscaped, "--name\\ Player\\ Name")

        // Method 2: Escape then join (CORRECT for preserving argument boundaries)
        let escapedThenJoined = args.map(\.esc).joined(separator: " ")
        // This only escapes spaces within arguments, preserving argument boundaries
        XCTAssertEqual(escapedThenJoined, "--name Player\\ Name")

        // The two methods produce different results
        XCTAssertNotEqual(joinedThenEscaped, escapedThenJoined)
    }
}
