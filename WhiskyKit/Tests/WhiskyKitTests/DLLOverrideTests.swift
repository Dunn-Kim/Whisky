//
//  DLLOverrideTests.swift
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

final class DLLOverrideTests: XCTestCase {
    // MARK: - DLL Override Mode

    func testDLLOverrideModeRawValues() {
        XCTAssertEqual(DLLOverrideMode.builtin.rawValue, "b")
        XCTAssertEqual(DLLOverrideMode.native.rawValue, "n")
        XCTAssertEqual(DLLOverrideMode.nativeThenBuiltin.rawValue, "n,b")
        XCTAssertEqual(DLLOverrideMode.builtinThenNative.rawValue, "b,n")
        XCTAssertEqual(DLLOverrideMode.disabled.rawValue, "")
    }

    // MARK: - DLL Override Entry Codable

    func testDLLOverrideEntryCodableRoundTrip() throws {
        let entry = DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(entry)
        let decoded = try PropertyListDecoder().decode(DLLOverrideEntry.self, from: data)
        XCTAssertEqual(decoded, entry)
    }

    // MARK: - DLL Override Resolver

    func testManagedOnlyResolvesToCorrectString() {
        let resolver = DLLOverrideResolver(
            managed: [
                (entry: DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin), source: .dxvk),
                (entry: DLLOverrideEntry(dllName: "d3d11", mode: .nativeThenBuiltin), source: .dxvk)
            ],
            bottleCustom: [],
            programCustom: []
        )
        let result = resolver.resolve()
        XCTAssertEqual(result.overrides, "d3d11=n,b;dxgi=n,b")
    }

    func testBottleCustomOverridesManaged() {
        let resolver = DLLOverrideResolver(
            managed: [
                (entry: DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin), source: .dxvk)
            ],
            bottleCustom: [
                DLLOverrideEntry(dllName: "dxgi", mode: .builtin)
            ],
            programCustom: []
        )
        let result = resolver.resolve()
        XCTAssertEqual(result.overrides, "dxgi=b")
    }

    func testProgramCustomOverridesAll() {
        let resolver = DLLOverrideResolver(
            managed: [
                (entry: DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin), source: .dxvk)
            ],
            bottleCustom: [],
            programCustom: [
                DLLOverrideEntry(dllName: "dxgi", mode: .disabled)
            ]
        )
        let result = resolver.resolve()
        XCTAssertEqual(result.overrides, "dxgi=")
    }

    func testEmptyResolverProducesEmptyString() {
        let resolver = DLLOverrideResolver(managed: [], bottleCustom: [], programCustom: [])
        let result = resolver.resolve()
        XCTAssertEqual(result.overrides, "")
    }

    func testMixedSourcesCompose() {
        let resolver = DLLOverrideResolver(
            managed: [
                (entry: DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin), source: .dxvk)
            ],
            bottleCustom: [
                DLLOverrideEntry(dllName: "vcrun", mode: .native)
            ],
            programCustom: []
        )
        let result = resolver.resolve()
        XCTAssertEqual(result.overrides, "dxgi=n,b;vcrun=n")
    }

    // MARK: - DLL Override Warnings

    func testDXVKWarningWhenManagedOverridden() {
        let resolver = DLLOverrideResolver(
            managed: [
                (entry: DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin), source: .dxvk)
            ],
            bottleCustom: [
                DLLOverrideEntry(dllName: "dxgi", mode: .builtin)
            ],
            programCustom: []
        )
        let result = resolver.resolve()
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings.first?.dllName, "dxgi")
        XCTAssertEqual(result.warnings.first?.overriddenSource, .dxvk)
    }

    func testNoWarningWhenNoConflict() {
        let resolver = DLLOverrideResolver(
            managed: [
                (entry: DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin), source: .dxvk)
            ],
            bottleCustom: [
                DLLOverrideEntry(dllName: "vcrun", mode: .native)
            ],
            programCustom: []
        )
        let result = resolver.resolve()
        XCTAssertTrue(result.warnings.isEmpty)
    }

    // MARK: - DXVK Preset

    func testDXVKPresetReturnsCorrectEntries() {
        let expected: [String: DLLOverrideMode] = [
            "dxgi": .nativeThenBuiltin,
            "d3d9": .nativeThenBuiltin,
            "d3d10core": .nativeThenBuiltin,
            "d3d11": .nativeThenBuiltin
        ]
        let preset = DLLOverrideResolver.dxvkPreset()
        let modesByName = Dictionary(uniqueKeysWithValues: preset.map { ($0.dllName, $0.mode) })
        XCTAssertEqual(modesByName, expected)
    }

    // MARK: - DXMT Preset

    func testDXMTPresetReturnsCorrectEntries() {
        // The D3D translation trio loads native from the prefix; winemetal must
        // stay builtin because its unixlib half only binds for builtin loads.
        let expected: [String: DLLOverrideMode] = [
            "dxgi": .nativeThenBuiltin,
            "d3d10core": .nativeThenBuiltin,
            "d3d11": .nativeThenBuiltin,
            "winemetal": .builtin
        ]
        let preset = DLLOverrideResolver.dxmtPreset()
        let modesByName = Dictionary(uniqueKeysWithValues: preset.map { ($0.dllName, $0.mode) })
        XCTAssertEqual(modesByName, expected)
    }

    func testDXMTPresetResolvesToPinnedOverrideString() {
        let resolver = DLLOverrideResolver(
            managed: DLLOverrideResolver.dxmtPreset().map { (entry: $0, source: .dxmt) },
            bottleCustom: [],
            programCustom: []
        )
        XCTAssertEqual(resolver.resolve().overrides, "d3d10core=n,b;d3d11=n,b;dxgi=n,b;winemetal=b")
    }

    func testDXMTWarningWhenManagedOverridden() {
        let resolver = DLLOverrideResolver(
            managed: [
                (entry: DLLOverrideEntry(dllName: "d3d11", mode: .nativeThenBuiltin), source: .dxmt)
            ],
            bottleCustom: [
                DLLOverrideEntry(dllName: "d3d11", mode: .builtin)
            ],
            programCustom: []
        )
        let result = resolver.resolve()
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings.first?.overriddenSource, .dxmt)
        XCTAssertTrue(result.warnings.first?.message.contains("DXMT") == true)
    }

    // MARK: - d3d12 is left to Wine's own builtin

    func testTranslationPresetsLeaveWinesOwnD3D12Loadable() {
        // The builtin is Wine's own d3d12, which turns the foreign adapter away
        // and lets the game fall back to D3D11. Disabling it made the DLL
        // unloadable instead: Unity 6000.3 players delay-load d3d12.dll at
        // startup and die with 0xC06D007E (#255, #257, #258).
        for (name, preset) in [
            ("DXVK", DLLOverrideResolver.dxvkPreset()),
            ("DXMT", DLLOverrideResolver.dxmtPreset())
        ] {
            XCTAssertFalse(preset.contains { $0.dllName == "d3d12" }, "\(name) must leave Wine's d3d12 alone")
        }
    }

    func testTranslationResetLeavesD3D12Alone() {
        XCTAssertFalse(Wine.translationDLLResetEntries().contains { $0.dllName == "d3d12" })
    }

    func testDXVKBottleRendersNoD3D12Override() {
        let resolver = DLLOverrideResolver(
            managed: DLLOverrideResolver.dxvkPreset().map { ($0, DLLOverrideSource.dxvk) },
            bottleCustom: [],
            programCustom: []
        )
        let d3d12 = resolver.resolve().overrides.split(separator: ";").map(String.init)
            .filter { $0.hasPrefix("d3d12=") }
        XCTAssertEqual(d3d12, [])
    }

    func testCustomD3D12BuiltinStillWinsOverThePreset() {
        // A bottle-level d3d12=b beats the backend's preset and says so.
        for (source, preset) in [
            (DLLOverrideSource.dxvk, DLLOverrideResolver.dxvkPreset()),
            (DLLOverrideSource.dxmt, DLLOverrideResolver.dxmtPreset())
        ] {
            let resolver = DLLOverrideResolver(
                managed: preset.map { ($0, source) },
                bottleCustom: [DLLOverrideEntry(dllName: "d3d12", mode: .builtin)],
                programCustom: []
            )
            let result = resolver.resolve()
            XCTAssertTrue(result.overrides.split(separator: ";").contains("d3d12=b"), "\(source)")
            XCTAssertTrue(result.warnings.isEmpty, "\(source): the preset says nothing about d3d12")
        }
    }

    // MARK: - What a launch gets

    /// A game started straight from a DXMT bottle, which is where #255, #257
    /// and #258 crashed: Recommended resolves games to DXMT on the stock
    /// engine. Only the bottle's preset speaks about d3d12 here, and it says
    /// nothing.
    @MainActor
    func testDXMTBottleLeavesD3D12Alone() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle.url) }
        bottle.settings.graphicsBackend = .dxmt

        let env = Wine.constructWineEnvironment(for: bottle)
        XCTAssertEqual(env["WINEDLLOVERRIDES"], "d3d10core=n,b;d3d11=n,b;dxgi=n,b;winemetal=b")
    }

    /// The launch composition `runProgram` uses. A bottle on DXMT, which is what
    /// Recommended resolves to on the stock engine, launching steam.exe, which
    /// `runProgram` pins to DXVK. When `-applaunch` starts the client itself,
    /// every game in that session inherits this `WINEDLLOVERRIDES`, and Wine
    /// reads it before the registry.
    @MainActor
    func testSteamPinOnADXMTBottleLeavesD3D12Alone() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle.url) }
        bottle.settings.graphicsBackend = .dxmt
        var steamPin = ProgramOverrides()
        steamPin.graphicsBackend = .dxvk

        let env = Wine.constructWineEnvironment(for: bottle, programOverrides: steamPin)
        XCTAssertEqual(env["WINEDLLOVERRIDES"], "d3d10core=n,b;d3d11=n,b;d3d9=n,b;dxgi=n,b;winemetal=b")
    }

    /// Custom entries keep the precedence they had: the bottle's beats the
    /// bottle's backend preset, and the program's (a Steam game's own settings
    /// ride along with the steam.exe pin) beats every preset.
    @MainActor
    func testCustomD3D12BuiltinStillWinsAtLaunch() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle.url) }
        bottle.settings.graphicsBackend = .dxmt

        bottle.settings.dllOverrides = [DLLOverrideEntry(dllName: "d3d12", mode: .builtin)]
        let direct = Wine.constructWineEnvironment(for: bottle)
        XCTAssertEqual(direct["WINEDLLOVERRIDES"], "d3d10core=n,b;d3d11=n,b;d3d12=b;dxgi=n,b;winemetal=b")

        bottle.settings.dllOverrides = []
        var gameUnderSteam = ProgramOverrides()
        gameUnderSteam.graphicsBackend = .dxvk
        gameUnderSteam.dllOverrides = [DLLOverrideEntry(dllName: "d3d12", mode: .builtin)]
        let steam = Wine.constructWineEnvironment(for: bottle, programOverrides: gameUnderSteam)
        XCTAssertEqual(steam["WINEDLLOVERRIDES"], "d3d10core=n,b;d3d11=n,b;d3d12=b;d3d9=n,b;dxgi=n,b;winemetal=b")
    }

    @MainActor
    private func makeBottle() throws -> Bottle {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return Bottle(bottleUrl: url, inFlight: false, isAvailable: true)
    }
}
