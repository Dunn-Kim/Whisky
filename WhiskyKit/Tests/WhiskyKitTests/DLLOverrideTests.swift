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
                (entry: DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin), source: .launcher("Steam")),
                (entry: DLLOverrideEntry(dllName: "d3d11", mode: .nativeThenBuiltin), source: .launcher("Steam"))
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
                (entry: DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin), source: .launcher("Steam"))
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
                (entry: DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin), source: .launcher("Steam"))
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
                (entry: DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin), source: .launcher("Steam"))
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

    func testWarningWhenManagedOverridden() {
        let resolver = DLLOverrideResolver(
            managed: [
                (entry: DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin), source: .launcher("Steam"))
            ],
            bottleCustom: [
                DLLOverrideEntry(dllName: "dxgi", mode: .builtin)
            ],
            programCustom: []
        )
        let result = resolver.resolve()
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings.first?.dllName, "dxgi")
        XCTAssertEqual(result.warnings.first?.overriddenSource, .launcher("Steam"))
        XCTAssertTrue(result.warnings.first?.message.contains("Steam") == true)
    }

    func testNoWarningWhenNoConflict() {
        let resolver = DLLOverrideResolver(
            managed: [
                (entry: DLLOverrideEntry(dllName: "dxgi", mode: .nativeThenBuiltin), source: .launcher("Steam"))
            ],
            bottleCustom: [
                DLLOverrideEntry(dllName: "vcrun", mode: .native)
            ],
            programCustom: []
        )
        let result = resolver.resolve()
        XCTAssertTrue(result.warnings.isEmpty)
    }

    // MARK: - What a launch gets

    /// No preset reaches a launch: the runtime picks its graphics layer itself,
    /// so what a bottle writes is its own custom entries.
    @MainActor
    func testBackendsContributeNoDLLOverrides() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle.url) }

        for backend in GraphicsBackend.allCases {
            bottle.settings.graphicsBackend = backend
            let env = Wine.constructWineEnvironment(for: bottle)
            XCTAssertNil(env["WINEDLLOVERRIDES"], "\(backend)")
        }
    }

    /// Custom entries keep the precedence they had: the program's beats the bottle's.
    @MainActor
    func testCustomEntriesComposeAtLaunch() throws {
        let bottle = try makeBottle()
        defer { try? FileManager.default.removeItem(at: bottle.url) }

        bottle.settings.dllOverrides = [DLLOverrideEntry(dllName: "d3d12", mode: .builtin)]
        let direct = Wine.constructWineEnvironment(for: bottle)
        XCTAssertEqual(direct["WINEDLLOVERRIDES"], "d3d12=b")

        var program = ProgramOverrides()
        program.dllOverrides = [DLLOverrideEntry(dllName: "d3d12", mode: .disabled)]
        let overridden = Wine.constructWineEnvironment(for: bottle, programOverrides: program)
        XCTAssertEqual(overridden["WINEDLLOVERRIDES"], "d3d12=")
    }

    @MainActor
    private func makeBottle() throws -> Bottle {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return Bottle(bottleUrl: url, inFlight: false, isAvailable: true)
    }
}
