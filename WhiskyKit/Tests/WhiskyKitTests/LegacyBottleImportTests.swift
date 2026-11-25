// swiftlint:disable file_length
//
//  LegacyBottleImportTests.swift
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
import SemanticVersion
@testable import WhiskyKit
import XCTest

// swiftlint:disable:next type_body_length
final class LegacyBottleImportTests: XCTestCase {
    private var root: URL!
    private var rosetta: LegacyBottleImport.SourceApp!
    private var original: LegacyBottleImport.SourceApp!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "legacy_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        rosetta = LegacyBottleImport.SourceApp(
            bundleIdentifier: "test.rosetta", displayName: "Rosetta", container: root.appending(path: "rosetta")
        )
        original = LegacyBottleImport.SourceApp(
            bundleIdentifier: "test.original", displayName: "Original", container: root.appending(path: "original")
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Creates a bottle folder named `name` in `app`'s container with the `Metadata.plist` marker.
    @discardableResult
    private func makeBottle(
        _ name: String, in app: LegacyBottleImport.SourceApp, valid: Bool = true, settings: BottleSettings? = nil
    ) throws -> URL {
        let dir = app.container.appending(path: "Bottles").appending(path: name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if valid {
            let metadata = dir.appending(path: "Metadata").appendingPathExtension("plist")
            if let settings {
                try settings.encode(to: metadata)
            } else {
                try Data("<plist></plist>".utf8).write(to: metadata)
            }
        }
        return dir.standardizedFileURL
    }

    // MARK: - Discovery

    func testDiscoversBothAppsInOrderWithLabels() throws {
        let originalBottle = try makeBottle("a", in: original)
        let rosettaB = try makeBottle("b", in: rosetta)
        let rosettaA = try makeBottle("a", in: rosetta)
        try makeBottle("not-a-bottle", in: rosetta, valid: false)

        let found = LegacyBottleImport.importableBottles(apps: [rosetta, original], existingPaths: [])
        XCTAssertEqual(found.map(\.url), [rosettaA, rosettaB, originalBottle])
        XCTAssertEqual(found.map(\.app), [rosetta, rosetta, original])
    }

    func testIncludesRegistryOnlyBottlesAndDeduplicates() throws {
        let shared = try makeBottle("a", in: rosetta)
        let custom = rosetta.container.appending(path: "elsewhere").standardizedFileURL
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        try Data("<plist></plist>".utf8)
            .write(to: custom.appending(path: "Metadata").appendingPathExtension("plist"))
        let gone = rosetta.container.appending(path: "gone").standardizedFileURL

        struct Registry: Encodable { var paths: [URL] }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(Registry(paths: [shared, custom, gone]))
            .write(to: rosetta.container.appending(path: "BottleVM").appendingPathExtension("plist"))

        let found = LegacyBottleImport.importableBottles(apps: [rosetta], existingPaths: [])
        XCTAssertEqual(Set(found.map(\.url)), [shared, custom])
        XCTAssertEqual(found.count, 2)
    }

    func testRecognisesAnotherAppsBottleInsideOrOutsideItsContainer() throws {
        let inside = try makeBottle("a", in: rosetta)
        let custom = root.appending(path: "custom").standardizedFileURL
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        try Data("<plist></plist>".utf8)
            .write(to: custom.appending(path: "Metadata").appendingPathExtension("plist"))
        struct Registry: Encodable { var paths: [URL] }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(Registry(paths: [custom]))
            .write(to: rosetta.container.appending(path: "BottleVM").appendingPathExtension("plist"))
        let own = root.appending(path: "own").standardizedFileURL

        XCTAssertTrue(LegacyBottleImport.isSourceAppBottle(inside, apps: [rosetta, original]))
        XCTAssertTrue(LegacyBottleImport.isSourceAppBottle(custom, apps: [rosetta, original]))
        XCTAssertFalse(LegacyBottleImport.isSourceAppBottle(own, apps: [rosetta, original]))
    }

    /// `BottleVM.plist` stores paths without a trailing slash; the directory scan returns them with one.
    func testRegistryPathWithoutTrailingSlashIsListedOnceAndNotAfterMigration() throws {
        let bottle = try makeBottle("a", in: rosetta)
        let bare =
            try XCTUnwrap(URL(string: "file:///" + bottle.path(percentEncoded: false).trimmingCharacters(in: ["/"])))
        let withSlash = try XCTUnwrap(URL(string: bare.absoluteString + "/"))
        struct Registry: Encodable { var paths: [URL] }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(Registry(paths: [bare]))
            .write(to: rosetta.container.appending(path: "BottleVM").appendingPathExtension("plist"))

        XCTAssertEqual(LegacyBottleImport.importableBottles(apps: [rosetta], existingPaths: []).count, 1)

        for source in [bare, withSlash] {
            var settings = BottleSettings()
            settings.migratedFrom = source
            let mine = root.appending(path: "mine-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
            try settings.encode(to: mine.appending(path: "Metadata").appendingPathExtension("plist"))
            XCTAssertTrue(LegacyBottleImport.importableBottles(apps: [rosetta], existingPaths: [mine]).isEmpty)
        }
    }

    func testCopySizeIsZeroOnTheSameVolume() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let driveC = root.appending(path: "src/drive_c")
        try FileManager.default.createDirectory(at: driveC, withIntermediateDirectories: true)
        try Data(count: 8_192).write(to: driveC.appending(path: "file"))

        XCTAssertEqual(LegacyBottleImport.copySize(of: root.appending(path: "src"), to: root.appending(path: "new")), 0)
    }

    func testAlreadyMigratedSourceIsFilteredOut() throws {
        let migrated = try makeBottle("a", in: rosetta)
        let fresh = try makeBottle("b", in: rosetta)

        var settings = BottleSettings()
        settings.migratedFrom = migrated
        let mine = root.appending(path: "mine")
        try FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
        try settings.encode(to: mine.appending(path: "Metadata").appendingPathExtension("plist"))

        let found = LegacyBottleImport.importableBottles(apps: [rosetta], existingPaths: [mine])
        XCTAssertEqual(found.map(\.url), [fresh])
    }

    func testNamesAreReadWithoutRewritingMetadata() throws {
        var settings = BottleSettings()
        settings.name = "My Real Bottle"
        let named = try makeBottle("named", in: rosetta, settings: settings)
        let plain = try makeBottle("plain", in: rosetta)
        let metadata = named.appending(path: "Metadata").appendingPathExtension("plist")
        let before = try Data(contentsOf: metadata)

        let found = LegacyBottleImport.importableBottles(apps: [rosetta], existingPaths: [])
        XCTAssertEqual(found.first { $0.url == named }?.name, "My Real Bottle")
        XCTAssertEqual(found.first { $0.url == plain }?.name, "plain")
        XCTAssertEqual(try Data(contentsOf: metadata), before)
    }

    func testContainerExists() {
        XCTAssertTrue(LegacyBottleImport.containerExists(apps: [rosetta, original]) == false)
        try? FileManager.default.createDirectory(at: original.container, withIntermediateDirectories: true)
        XCTAssertTrue(LegacyBottleImport.containerExists(apps: [rosetta, original]))
    }

    // MARK: - Settings

    func testCopySettingsCarriesOnlyTheSettingsFiles() throws {
        let source = try makeBottle("src", in: rosetta)
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: source.appending(path: "Program Settings"),
            withIntermediateDirectories: true
        )
        for name in [
            "Program Settings/Game-1234.plist",
            "HandledShortcuts.plist",
            "dependency-history.plist",
            "WinetricksCache.plist",
            "winetricks.log",
            "windata",
            "user.reg"
        ] {
            try Data("x".utf8).write(to: source.appending(path: name))
        }
        let destination = root.appending(path: "dst")
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        try LegacyBottleImport.copySettings(from: source, to: destination)

        let copied = try Set(fileManager.contentsOfDirectory(atPath: destination.path))
        XCTAssertEqual(copied, ["Metadata.plist", "Program Settings", "HandledShortcuts.plist"])
        XCTAssertTrue(fileManager
            .fileExists(atPath: destination.appending(path: "Program Settings/Game-1234.plist").path))
    }

    func testRewriteSettingsMovesPinsAndRecordsSource() throws {
        let source = root.appending(path: "src")
        let destination = root.appending(path: "dst")
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: source.appending(path: "drive_c/Game"), withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: destination.appending(path: "Program Settings"), withIntermediateDirectories: true
        )
        let exe = source.appending(path: "drive_c/Game/game.exe")
        let outside = URL(fileURLWithPath: "/Volumes/Other/tool.exe")
        var settings = BottleSettings()
        settings.name = "Old"
        settings.pins = [PinnedProgram(name: "Game", url: exe), PinnedProgram(name: "Tool", url: outside)]
        settings.blocklist = [source.appending(path: "drive_c/Game/setup.exe")]
        settings.unpinnedPrograms = [source.appending(path: "drive_c/Game/old.exe")]
        try settings.encode(to: destination.appending(path: "Metadata").appendingPathExtension("plist"))

        // A program settings file whose log lives in the source bottle.
        var program = ProgramSettings()
        program.lastLogFileURL = source.appending(path: "drive_c/log.txt")
        let programFile = destination.appending(path: "Program Settings/game-aaaa.plist")
        try program.encode(to: programFile)

        let rewritten = try LegacyBottleImport.rewriteSettings(in: destination, from: source)

        XCTAssertEqual(rewritten.pins.map(\.url), [destination.appending(path: "drive_c/Game/game.exe"), outside])
        XCTAssertEqual(rewritten.blocklist, [destination.appending(path: "drive_c/Game/setup.exe")])
        XCTAssertEqual(rewritten.unpinnedPrograms, [destination.appending(path: "drive_c/Game/old.exe")])
        XCTAssertEqual(rewritten.migratedFrom, source.standardizedFileURL)
        XCTAssertEqual(rewritten.name, "Old")
        let onDisk = try PropertyListDecoder().decode(
            BottleSettings.self,
            from: Data(contentsOf: destination.appending(path: "Metadata").appendingPathExtension("plist"))
        )
        XCTAssertEqual(onDisk, rewritten)
        XCTAssertEqual(
            try ProgramSettings.decodeIfPresent(from: programFile)?.lastLogFileURL,
            destination.appending(path: "drive_c/log.txt")
        )
    }

    func testRebasedKeepsLookalikeSiblings() {
        let source = URL(fileURLWithPath: "/a/bottle")
        let destination = URL(fileURLWithPath: "/b/new")
        let sibling = URL(fileURLWithPath: "/a/bottle2/x.exe")
        XCTAssertEqual(LegacyBottleImport.rebased(sibling, from: source, to: destination), sibling)
    }

    func testProgramSettingsNamesDoNotDependOnTheBottleLocation() {
        let oldBottle = URL(fileURLWithPath: "/a/old")
        let newBottle = URL(fileURLWithPath: "/b/new")
        let exe = oldBottle.appending(path: "drive_c/Game/Launch.exe")
        XCTAssertEqual(
            Program.settingsIdentity(for: exe, bottleURL: oldBottle),
            Program.settingsIdentity(
                for: LegacyBottleImport.rebased(exe, from: oldBottle, to: newBottle), bottleURL: newBottle
            )
        )
    }

    // MARK: - drive_c

    func testMergeDriveC() throws {
        let fileManager = FileManager.default
        let source = root.appending(path: "src_c")
        let destination = root.appending(path: "dst_c")
        func write(_ base: URL, _ path: String, _ text: String) throws {
            let url = base.appending(path: path)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        try write(source, "Mecharashi/data.bin", "source")
        try write(source, "Program Files/App/new.dll", "source")
        try write(source, "Program Files/App/shared.dll", "source")
        try write(source, "windows/system32/x86.dll", "source")
        try write(source, "windows/Fonts/Custom.ttf", "source")
        try write(source, "windows/Fonts/arial.ttf", "source")
        try fileManager.createSymbolicLink(
            atPath: source.appending(path: "Program Files/App/link").path, withDestinationPath: "new.dll"
        )
        try write(destination, "Program Files/App/shared.dll", "destination")
        try write(destination, "windows/system32/arm64.dll", "destination")
        try write(destination, "windows/Fonts/arial.ttf", "destination")

        try LegacyBottleImport.mergeDriveC(from: source, to: destination)

        func text(_ path: String) -> String? {
            try? String(contentsOf: destination.appending(path: path), encoding: .utf8)
        }
        XCTAssertEqual(text("Mecharashi/data.bin"), "source")
        XCTAssertEqual(text("Program Files/App/new.dll"), "source")
        XCTAssertEqual(text("Program Files/App/shared.dll"), "destination")
        XCTAssertNil(text("windows/system32/x86.dll"))
        XCTAssertEqual(text("windows/system32/arm64.dll"), "destination")
        XCTAssertEqual(text("windows/Fonts/Custom.ttf"), "source")
        XCTAssertEqual(text("windows/Fonts/arial.ttf"), "destination")
        let link = destination.appending(path: "Program Files/App/link").path
        XCTAssertEqual(try fileManager.destinationOfSymbolicLink(atPath: link), "new.dll")
    }

    func testMergeDriveCReplacesAProfileLinkWithTheSourceFolder() throws {
        let fileManager = FileManager.default
        let source = root.appending(path: "src_c")
        let destination = root.appending(path: "dst_c")
        let macDesktop = root.appending(path: "MacDesktop")
        let sourceDesktop = source.appending(path: "users/me/Desktop")
        try fileManager.createDirectory(at: sourceDesktop, withIntermediateDirectories: true)
        try Data("game".utf8).write(to: sourceDesktop.appending(path: "Game.lnk"))
        try fileManager.createDirectory(at: macDesktop, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: destination.appending(path: "users/me"), withIntermediateDirectories: true
        )
        try fileManager.createSymbolicLink(
            atPath: destination.appending(path: "users/me/Desktop").path, withDestinationPath: macDesktop.path
        )

        try LegacyBottleImport.mergeDriveC(from: source, to: destination)

        let desktop = destination.appending(path: "users/me/Desktop")
        let type = try fileManager.attributesOfItem(atPath: desktop.path)[.type] as? FileAttributeType
        XCTAssertEqual(type, .typeDirectory)
        XCTAssertTrue(fileManager.fileExists(atPath: desktop.appending(path: "Game.lnk").path))
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: macDesktop.path), [])
    }

    func testMergeDriveCCreatesFontsWhenDestinationHasNoWindows() throws {
        let fileManager = FileManager.default
        let source = root.appending(path: "src_c")
        let destination = root.appending(path: "dst_c")
        try fileManager.createDirectory(at: source.appending(path: "windows/Fonts"), withIntermediateDirectories: true)
        try Data("f".utf8).write(to: source.appending(path: "windows/Fonts/a.ttf"))
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        try LegacyBottleImport.mergeDriveC(from: source, to: destination)

        XCTAssertTrue(fileManager.fileExists(atPath: destination.appending(path: "windows/Fonts/a.ttf").path))
    }

    // MARK: - Registry

    private let userReg = """
    WINE REGISTRY Version 2
    ;; All keys relative to \\\\User\\\\S-1-5-21

    #arch=win64

    [Software\\\\tentree] 1700000000
    #time=1d
    "Setting"=dword:00000001

    [Software\\\\Microsoft\\\\Windows] 1700000001
    "A"="b"

    [Software\\\\Classes\\\\.foo] 1700000002
    @="foo"

    [Software\\\\Wine\\\\Drivers] 1700000003
    "Audio"="coreaudio"

    [Software\\\\Wine\\\\Fonts\\\\Replacements] 1700000004
    "Arial"="Noto Sans"

    [Software\\\\Existing] 1700000005
    "new"="value"

    [Software\\\\Vendor\\\\Sub] 1700000006
    "k"="v"

    [Control Panel\\\\Desktop] 1700000007
    "x"="y"

    """

    func testUserRegistrySplice() {
        let destination = """
        WINE REGISTRY Version 2
        #arch=aarch64

        [software\\\\EXISTING] 1800000000
        "old"="value"

        """
        let result = LegacyBottleImport.spliceRegistry(
            source: userReg, into: destination, keeping: LegacyBottleImport.keepsUserKey
        )
        let keys = result.split(separator: "\n").filter { $0.hasPrefix("[") }.map { $0.prefix { $0 != "]" } }
        XCTAssertEqual(keys, [
            "[software\\\\EXISTING",
            "[Software\\\\tentree",
            "[Software\\\\Wine\\\\Fonts\\\\Replacements",
            "[Software\\\\Vendor\\\\Sub"
        ])
        XCTAssertTrue(result.hasPrefix(destination))
        XCTAssertTrue(result.contains("[Software\\\\tentree] 1700000000\n#time=1d\n\"Setting\"=dword:00000001\n\n"))
        XCTAssertFalse(result.contains("\"new\"=\"value\""))
    }

    func testSystemRegistryFilter() {
        let keep = [
            "Software\\\\Tentree", "Software\\\\Wow6432Node\\\\Tentree\\\\Game", "software\\\\vendor"
        ]
        let drop = [
            "Software\\\\Microsoft\\\\Windows", "Software\\\\Wow6432Node\\\\Microsoft", "Software\\\\Wine",
            "Software\\\\Classes", "Software\\\\Clients\\\\Mail", "Software\\\\Policies", "Software\\\\ODBC",
            "Software\\\\RegisteredApplications", "Software\\\\Wow6432Node", "Software", "System\\\\Foo"
        ]
        for key in keep {
            XCTAssertTrue(LegacyBottleImport.keepsSystemKey(key), key)
        }
        for key in drop {
            XCTAssertFalse(LegacyBottleImport.keepsSystemKey(key), key)
        }
    }

    func testSpliceRegistriesReadsLatin1Source() throws {
        let source = root.appending(path: "src_reg")
        let destination = root.appending(path: "dst_reg")
        for dir in [source, destination] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // 0xE9 is not valid UTF-8, so the source reads as ISO Latin-1.
        let latin1 = "WINE REGISTRY Version 2\n\n[Software\\\\Caf\u{E9}] 1\n\"a\"=\"b\"\n\n"
        try XCTUnwrap(latin1.data(using: .isoLatin1)).write(to: source.appending(path: "user.reg"))
        try Data("WINE REGISTRY Version 2\n".utf8).write(to: destination.appending(path: "user.reg"))
        try Data("WINE REGISTRY Version 2\n".utf8).write(to: destination.appending(path: "system.reg"))

        try LegacyBottleImport.spliceRegistries(from: source, to: destination)

        let spliced = try Data(contentsOf: destination.appending(path: "user.reg"))
        XCTAssertEqual(
            String(data: spliced, encoding: .utf8),
            "WINE REGISTRY Version 2\n[Software\\\\Caf\u{E9}] 1\n\"a\"=\"b\"\n\n"
        )
        XCTAssertEqual(
            try Data(contentsOf: destination.appending(path: "system.reg")),
            Data("WINE REGISTRY Version 2\n".utf8)
        )
    }

    /// A new prefix without its registry means the migration would carry no settings.
    func testSpliceRegistriesThrowsWithoutTheNewPrefixsRegistry() throws {
        let source = root.appending(path: "src_missing")
        let destination = root.appending(path: "dst_missing")
        for dir in [source, destination] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try Data("WINE REGISTRY Version 2\n".utf8).write(to: source.appending(path: "user.reg"))

        XCTAssertThrowsError(try LegacyBottleImport.spliceRegistries(from: source, to: destination))
    }
}
