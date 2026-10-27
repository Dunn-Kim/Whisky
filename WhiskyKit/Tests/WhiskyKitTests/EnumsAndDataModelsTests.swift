//
//  EnumsAndDataModelsTests.swift
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

// MARK: - Locales Enum Tests

final class LocalesEnumTests: XCTestCase {
    func testLocalesRawValues() {
        XCTAssertEqual(Locales.auto.rawValue, "")
        XCTAssertEqual(Locales.german.rawValue, "de_DE.UTF-8")
        XCTAssertEqual(Locales.english.rawValue, "en_US.UTF-8")
        XCTAssertEqual(Locales.spanish.rawValue, "es_ES.UTF-8")
        XCTAssertEqual(Locales.french.rawValue, "fr_FR.UTF-8")
        XCTAssertEqual(Locales.italian.rawValue, "it_IT.UTF-8")
        XCTAssertEqual(Locales.japanese.rawValue, "ja_JP.UTF-8")
        XCTAssertEqual(Locales.korean.rawValue, "ko_KR.UTF-8")
        XCTAssertEqual(Locales.russian.rawValue, "ru_RU.UTF-8")
        XCTAssertEqual(Locales.ukranian.rawValue, "uk_UA.UTF-8")
        XCTAssertEqual(Locales.thai.rawValue, "th_TH.UTF-8")
        XCTAssertEqual(Locales.chineseSimplified.rawValue, "zh_CN.UTF-8")
        XCTAssertEqual(Locales.chineseTraditional.rawValue, "zh_TW.UTF-8")
    }

    func testLocalesPrettyDisplayNames() {
        XCTAssertEqual(Locales.german.pretty(), "Deutsch")
        XCTAssertEqual(Locales.english.pretty(), "English")
        XCTAssertEqual(Locales.spanish.pretty(), "Español")
        XCTAssertEqual(Locales.french.pretty(), "Français")
        XCTAssertEqual(Locales.italian.pretty(), "Italiano")
        XCTAssertEqual(Locales.japanese.pretty(), "日本語")
        XCTAssertEqual(Locales.korean.pretty(), "한국어")
        XCTAssertEqual(Locales.russian.pretty(), "Русский")
        XCTAssertEqual(Locales.ukranian.pretty(), "Українська")
        XCTAssertEqual(Locales.thai.pretty(), "ไทย")
        XCTAssertEqual(Locales.chineseSimplified.pretty(), "简体中文")
        XCTAssertEqual(Locales.chineseTraditional.pretty(), "繁體中文")
    }
}

// MARK: - ProgramSettings Tests

final class ProgramSettingsTests: XCTestCase {
    func testDefaultInitialization() {
        let settings = ProgramSettings()

        XCTAssertEqual(settings.locale, .auto)
        XCTAssertEqual(settings.environment, [:])
        XCTAssertEqual(settings.arguments, "")
    }

    func testSettingsEncodeDecodeWithTempFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let settingsURL = tempDir.appending(path: "test_settings_\(UUID().uuidString).plist")

        defer {
            try? FileManager.default.removeItem(at: settingsURL)
        }

        var original = ProgramSettings()
        original.locale = .french
        original.arguments = "-fullscreen"
        original.environment["DEBUG"] = "1"

        try original.encode(to: settingsURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path(percentEncoded: false)))

        let decoded = try ProgramSettings.decode(from: settingsURL)

        XCTAssertEqual(decoded.locale, original.locale)
        XCTAssertEqual(decoded.arguments, original.arguments)
        XCTAssertEqual(decoded.environment, original.environment)
    }

    func testSettingsDecodeCreatesDefaultIfMissing() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let nonExistentURL = tempDir.appending(path: "non_existent_\(UUID().uuidString).plist")

        defer {
            try? FileManager.default.removeItem(at: nonExistentURL)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: nonExistentURL.path(percentEncoded: false)))

        let settings = try ProgramSettings.decode(from: nonExistentURL)

        XCTAssertEqual(settings.locale, .auto)
        XCTAssertEqual(settings.environment, [:])
        XCTAssertEqual(settings.arguments, "")

        XCTAssertTrue(FileManager.default.fileExists(atPath: nonExistentURL.path(percentEncoded: false)))
    }
}

// MARK: - PEError Tests

final class PEErrorTests: XCTestCase {
    func testInvalidPEFileError() {
        let error = PEError.invalidPEFile
        XCTAssertEqual(error.message, "Invalid PE file")
    }
}
