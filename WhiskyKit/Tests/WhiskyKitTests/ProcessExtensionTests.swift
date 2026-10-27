//
//  ProcessExtensionTests.swift
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

// MARK: - FileHandle.nextOutput Tests

final class FileHandleNextOutputTests: XCTestCase {
    var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory.appending(path: "nextoutput_\(UUID().uuidString).txt")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testReturnsTextForContent() throws {
        try Data("Hello, World!".utf8).write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        XCTAssertEqual(handle.nextOutput(), .text("Hello, World!"))
    }

    /// The crux of the fix: an empty read is EOF, reported distinctly so the
    /// readability handler can remove itself instead of spinning on it.
    func testReturnsEndOfFileForEmptyRead() throws {
        try Data().write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        XCTAssertEqual(handle.nextOutput(), .endOfFile)
    }

    func testReturnsTextForMultipleLines() throws {
        try Data("Line 1\nLine 2\nLine 3".utf8).write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        // A single read returns all currently-available data as one chunk.
        XCTAssertEqual(handle.nextOutput(), .text("Line 1\nLine 2\nLine 3"))
    }

    func testReturnsTextForUnicodeContent() throws {
        try Data("日本語テスト 🍷".utf8).write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        XCTAssertEqual(handle.nextOutput(), .text("日本語テスト 🍷"))
    }

    /// A non-empty but not-yet-decodable chunk (e.g. a split multi-byte sequence)
    /// is `.pending`, NOT `.endOfFile` — the handler must keep reading, not stop.
    func testReturnsPendingForUndecodableData() throws {
        try Data([0xFF, 0xFE]).write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        XCTAssertEqual(handle.nextOutput(), .pending)
    }
}

// MARK: - Process.runStream Integration Tests

final class ProcessRunStreamTests: XCTestCase {
    /// Collects every `ProcessOutput` a short-lived `/bin/sh -c <script>` emits.
    private func collectOutput(script: String) async throws -> [ProcessOutput] {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", script]

        var outputs: [ProcessOutput] = []
        let stream = try process.runStream(name: "runStreamTest", fileHandle: nil)
        for await output in stream {
            outputs.append(output)
        }
        return outputs
    }

    func testHappyPathYieldsOutputAndTermination() async throws {
        let outputs = try await collectOutput(script: "printf 'hello\\n'")

        XCTAssertEqual(outputs.first, .started)
        XCTAssertEqual(outputs.last, .terminated(0))
        XCTAssertTrue(
            outputs.contains { if case let .message(line) = $0 { line.contains("hello") } else { false } },
            "expected a stdout message containing 'hello', got \(outputs)"
        )
    }

    /// The regression case: the child closes stdout/stderr while still running,
    /// so the pipe reaches EOF before termination. Output must still arrive and
    /// the stream must finish cleanly (and promptly — no hang from the spin path).
    func testEOFBeforeExitStillDeliversOutputAndTerminates() async throws {
        let outputs = try await collectOutput(
            script: "printf 'early\\n'; exec 1>&-; exec 2>&-; sleep 0.3"
        )

        XCTAssertEqual(outputs.last, .terminated(0))
        XCTAssertTrue(
            outputs.contains { if case let .message(line) = $0 { line.contains("early") } else { false } },
            "output written before the pipe closed must not be lost, got \(outputs)"
        )
    }

    func testSilentProcessTerminatesWithoutSpuriousOutput() async throws {
        let outputs = try await collectOutput(script: "sleep 0.2")

        XCTAssertEqual(outputs.first, .started)
        XCTAssertEqual(outputs.last, .terminated(0))
        XCTAssertFalse(
            outputs.contains { if case .message = $0 { true } else if case .error = $0 { true } else { false } },
            "a silent process should produce no message/error output, got \(outputs)"
        )
    }
}
