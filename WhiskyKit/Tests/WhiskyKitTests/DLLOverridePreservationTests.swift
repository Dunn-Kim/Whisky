//
//  DLLOverridePreservationTests.swift
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

/// A prefix registry that applies the `.reg` documents the DLL override sync
/// writes the way `reg import` does: section headers, `[-Key]`, and the
/// `"name"="value"` and `"name"=-` value lines.
@MainActor
final class SimulatedRegistry {
    /// Lowercased key to lowercased value name to data.
    private(set) var keys: [String: [String: String]] = [:]

    var importer: Wine.RegistryImporter {
        { document, _ in self.apply(document) }
    }

    func set(_ key: String, _ values: [String: String]) {
        keys[key.lowercased(), default: [:]].merge(values) { _, new in new }
    }

    func values(_ key: String) -> [String: String] {
        keys[key.lowercased()] ?? [:]
    }

    func apply(_ document: String) {
        var current: String?
        for line in document.components(separatedBy: "\r\n") {
            if line.hasPrefix("[-"), line.hasSuffix("]") {
                keys[String(line.dropFirst(2).dropLast()).lowercased()] = nil
                current = nil
            } else if line.hasPrefix("["), line.hasSuffix("]") {
                let key = String(line.dropFirst().dropLast()).lowercased()
                keys[key] = keys[key] ?? [:]
                current = key
            } else if let key = current, line.hasPrefix("\"") {
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let name = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\"")).lowercased()
                if parts[1] == "-" {
                    keys[key]?[name] = nil
                } else {
                    keys[key]?[name] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
        }
    }
}

/// What a launch leaves in the prefix registry's DLL override keys, now that
/// it removes only the values it could have written (adurham/Whisky).
@Suite("DLL overrides other tools wrote")
@MainActor
final class DLLOverridePreservationTests {
    private let tempRoot: URL
    private let registry = SimulatedRegistry()
    private let bottleKey = Wine.DLLOverrideScope.bottle.registryKey
    private let gameKey = Wine.DLLOverrideScope.program("Game.exe").registryKey

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "dll_override_preservation_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeBottle(_ backend: GraphicsBackend) throws -> (bottle: Bottle, game: URL) {
        let bottleURL = tempRoot.appending(path: "Bottle")
        let game = bottleURL.appending(path: "drive_c/Games/Game/Game.exe")
        try FileManager.default.createDirectory(
            at: game.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("MZ".utf8).write(to: game)
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.graphicsBackend = backend
        return (bottle, game)
    }

    /// Runs a launch's DLL override sync against the simulated registry.
    private func launch(_ url: URL, in bottle: Bottle) async throws {
        var environment = Wine.constructWineEnvironment(
            for: bottle
        )
        try await Wine.applyDLLOverrides(
            for: url, bottle: bottle, wineEnvironment: &environment, applyToDescendants: false,
            writer: { bottle, scopes in
                try await Wine.syncDLLOverrides(bottle: bottle, scopes: scopes, importer: self.registry.importer)
            }
        )
    }

    @Test("A winetricks override survives launches and a switch of backend")
    func winetricksOverrideSurvivesBackendSwitch() async throws {
        let (bottle, game) = try makeBottle(.dxmt)
        try await launch(game, in: bottle)
        // The backend writes nothing: the runtime picks its graphics layer itself.
        #expect(registry.values(bottleKey).isEmpty)

        // What `winetricks d3dx9 xact` and winecfg leave behind.
        registry.set(bottleKey, ["d3dx9_43": "native", "xaudio2_7": "native,builtin"])
        registry.set(gameKey, ["dinput8": "native"])

        bottle.settings.graphicsBackend = .wined3d
        try await launch(game, in: bottle)
        #expect(registry.values(bottleKey) == ["d3dx9_43": "native", "xaudio2_7": "native,builtin"])
        #expect(registry.values(gameKey) == ["dinput8": "native"])
    }

    func removedCustomOverrideIsTakenBack() async throws {
        let (bottle, game) = try makeBottle(.recommended)
        registry.set(bottleKey, ["d3dx9_43": "native"])
        bottle.settings.dllOverrides = [DLLOverrideEntry(dllName: "version", mode: .nativeThenBuiltin)]
        try await launch(game, in: bottle)
        #expect(registry.values(bottleKey) == ["d3dx9_43": "native", "version": "n,b"])

        bottle.settings.dllOverrides = []
        try await launch(game, in: bottle)
        #expect(registry.values(bottleKey) == ["d3dx9_43": "native"])
    }

    @Test("Launching one program does not forget what another's launch wrote")
    func recordKeepsOtherProgramsNames() {
        let otherKey = Wine.DLLOverrideScope.program("Other.exe").registryKey
        var record = DLLOverrideRecord().updated(with: [(key: otherKey, overrides: ["version": "n,b"])])
        record = record.updated(with: [(key: gameKey, overrides: ["dinput8": "n", "nvapi64": ""])])

        #expect(record.names(for: otherKey) == ["version"])
        // Managed names are always removable, so they are not recorded.
        #expect(record.names(for: gameKey) == ["dinput8"])

        let document = Wine.registryDocument(for: [(key: otherKey, overrides: [:])], record: record)
        #expect(document.contains(#""version"=-"#))
        #expect(!document.contains("dinput8"))
    }

    @Test("A launch that finishes during another's import keeps its recorded names")
    func overlappingLaunchesKeepEachOthersNames() async throws {
        let (bottle, _) = try makeBottle(.recommended)
        let otherKey = Wine.DLLOverrideScope.program("Other.exe").registryKey
        // Launch B saves its names while launch A's import is still running.
        let importer: Wine.RegistryImporter = { document, bottle in
            self.registry.apply(document)
            try DLLOverrideRecord.load(from: bottle.url)
                .updated(with: [(key: otherKey, overrides: ["version": "n,b"])])
                .save(to: bottle.url)
        }
        try await Wine.syncDLLOverrides(
            bottle: bottle, scopes: [(scope: .program("Game.exe"), overrides: "dinput8=n")], importer: importer
        )

        let record = DLLOverrideRecord.load(from: bottle.url)
        #expect(record.names(for: gameKey) == ["dinput8"])
        #expect(record.names(for: otherKey) == ["version"])
    }

    @Test("A launch that starts during another's import takes back the name that import wrote")
    func overlappingLaunchesOfOneProgramTakeBackStaleNames() async throws {
        let (bottle, _) = try makeBottle(.recommended)
        var releaseFirst: CheckedContinuation<Void, Never>?
        var held = false
        let importer: Wine.RegistryImporter = { document, _ in
            if !held {
                held = true
                await withCheckedContinuation { releaseFirst = $0 }
            }
            self.registry.apply(document)
        }
        func sync(_ overrides: String) async throws {
            try await Wine.syncDLLOverrides(
                bottle: bottle, scopes: [(scope: .program("Game.exe"), overrides: overrides)], importer: importer
            )
        }

        // The first launch's import is still running when the user swaps the
        // custom override and launches again.
        let first = Task { try await sync("aaa=n") }
        while releaseFirst == nil {
            await Task.yield()
        }
        let second = Task { try await sync("bbb=n") }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        releaseFirst?.resume()
        try await first.value
        try await second.value

        #expect(registry.values(gameKey) == ["bbb": "n"])
        #expect(DLLOverrideRecord.load(from: bottle.url).names(for: gameKey) == ["bbb"])
    }

    @Test("A program name that would break the key header gets no entry")
    func unsafeExecutableNamesAreSkipped() {
        #expect(Wine.DLLOverrideScopes.isKeySegment("Game [v1.2].exe"))
        #expect(!Wine.DLLOverrideScopes.isKeySegment("New\nline.exe"))
        #expect(!Wine.DLLOverrideScopes.isKeySegment("Sub\\Key.exe"))
        #expect(!Wine.DLLOverrideScopes.isKeySegment(""))
        #expect(!Wine.DLLOverrideScopes.isKeySegment("Tab\tName.exe"))
        #expect(!Wine.DLLOverrideScopes.isKeySegment("C1\u{85}Line.exe"))
        // Format characters are not control codes: a ZWNJ is part of Persian words.
        let persian = "\u{0645}\u{06CC}\u{200C}\u{062E}\u{0648}\u{0627}\u{0647}\u{0645}.exe"
        #expect(Wine.DLLOverrideScopes.isKeySegment(persian))
        #expect(Wine.DLLOverrideScopes.isKeySegment("Game\u{200D}.exe"))

        var scopes = Wine.DLLOverrideScopes(bottle: "dxgi=n,b")
        scopes.add(["a\n[HKEY_CURRENT_USER\\Software\\Injected]\n.exe", "Game.exe"], "d3d11=n,b")
        let document = Wine.registryDocument(
            for: scopes.entries.map { (key: $0.scope.registryKey, overrides: Wine.parseDLLOverrides($0.overrides)) }
        )
        #expect(scopes.entries.count == 2)
        #expect(!document.contains("Injected"))
        #expect(document.contains("AppDefaults\\Game.exe\\DllOverrides"))
    }

    @Test("The record survives a save and load")
    func recordRoundTrips() throws {
        let (bottle, _) = try makeBottle(.recommended)
        let record = DLLOverrideRecord().updated(with: [(key: bottleKey, overrides: ["Version": "n,b"])])
        try record.save(to: bottle.url)
        #expect(DLLOverrideRecord.load(from: bottle.url) == record)
        #expect(DLLOverrideRecord.load(from: tempRoot.appending(path: "missing")) == DLLOverrideRecord())
    }
}
