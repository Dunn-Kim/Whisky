//
//  FileExtensionTests.swift
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

// MARK: - FileHandle.extract Tests

final class FileHandleExtractTests: XCTestCase {
    var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory.appending(path: "test_\(UUID().uuidString).bin")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testExtractUInt8() throws {
        let data = Data([0x42])
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let value = handle.extract(UInt8.self, offset: 0)
        XCTAssertEqual(value, 0x42)
    }

    func testExtractUInt16() throws {
        let data = Data([0x34, 0x12])
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let value = handle.extract(UInt16.self, offset: 0)
        XCTAssertEqual(value, 0x1234)
    }

    func testExtractUInt32() throws {
        let data = Data([0x78, 0x56, 0x34, 0x12])
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let value = handle.extract(UInt32.self, offset: 0)
        XCTAssertEqual(value, 0x1234_5678)
    }

    func testExtractUInt64() throws {
        let data = Data([0xEF, 0xCD, 0xAB, 0x90, 0x78, 0x56, 0x34, 0x12])
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let value = handle.extract(UInt64.self, offset: 0)
        XCTAssertEqual(value, 0x1234_5678_90AB_CDEF)
    }

    func testExtractWithOffset() throws {
        let data = Data([0x00, 0x00, 0x42, 0x00])
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let value = handle.extract(UInt8.self, offset: 2)
        XCTAssertEqual(value, 0x42)
    }

    func testExtractMultipleValues() throws {
        let data = Data([
            0x01, 0x00,
            0x02, 0x00,
            0x03, 0x00, 0x00, 0x00
        ])
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let value1 = handle.extract(UInt16.self, offset: 0)
        let value2 = handle.extract(UInt16.self, offset: 2)
        let value3 = handle.extract(UInt32.self, offset: 4)

        XCTAssertEqual(value1, 0x0001)
        XCTAssertEqual(value2, 0x0002)
        XCTAssertEqual(value3, 0x0000_0003)
    }

    func testExtractAtExactEndReturnsNil() throws {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let value = handle.extract(UInt8.self, offset: 4)
        XCTAssertNil(value)
    }

    func testExtractFromEmptyFile() throws {
        let data = Data()
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let value = handle.extract(UInt8.self, offset: 0)
        XCTAssertNil(value)
    }

    func testExtractAtOffsetBeyondFileSize() throws {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        let value = handle.extract(UInt32.self, offset: 100)
        XCTAssertNil(value)
    }

    func testExtractStraddlingEOFReturnsNil() throws {
        let data = Data([0x01, 0x02])
        try data.write(to: tempURL)

        let handle = try FileHandle(forReadingFrom: tempURL)
        defer { try? handle.close() }

        // A read that starts in bounds but ends past EOF returns fewer bytes than
        // the type needs; extract must return nil, not load past the short buffer.
        XCTAssertNil(handle.extract(UInt32.self, offset: 0))
        XCTAssertNil(handle.extract(UInt32.self, offset: 1))
        XCTAssertNil(handle.extract(UInt16.self, offset: 1))
        XCTAssertEqual(handle.extract(UInt16.self, offset: 0), 0x0201)
    }
}
