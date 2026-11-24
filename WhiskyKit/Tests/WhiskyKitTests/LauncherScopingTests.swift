//
//  LauncherScopingTests.swift
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

/// Captures the scopes a launch writes, in place of the `reg import` that needs Wine.
@MainActor
final class ScopeRecorder {
    private(set) var writes: [[(scope: Wine.DLLOverrideScope, overrides: String)]] = []
    private(set) var imports: [String] = []

    var writer: Wine.DLLOverrideWriter {
        { _, scopes in self.writes.append(scopes) }
    }

    var importer: Wine.RegistryImporter {
        { document, _ in self.imports.append(document) }
    }

    /// The overrides the only write gave `scope`, parsed; `nil` when there was
    /// no single write or it left `scope` out.
    func overrides(for scope: Wine.DLLOverrideScope) -> [String: String]? {
        guard writes.count == 1, let entry = writes[0].first(where: { $0.scope == scope }) else {
            return nil
        }
        return Wine.parseDLLOverrides(entry.overrides)
    }

    /// The program scopes the only write named, in order.
    var programScopes: [String] {
        guard writes.count == 1 else { return [] }
        return writes[0].compactMap { entry in
            guard case let .program(executable) = entry.scope else { return nil }
            return executable
        }
    }
}

/// The DLL override layout of a Steam launch: the bottle's own set in the prefix
/// default, and the launcher's processes in entries of their own (#276). The
/// runtime is pinned in every case, so the suite answers the same on any machine.
@Suite("Launcher DLL override scoping")
@MainActor
final class LauncherScopingTests {
    private let tempRoot: URL

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "launcher_scoping_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeBottle(_ backend: GraphicsBackend) throws -> Bottle {
        let bottleURL = tempRoot.appending(path: "Bottle")
        try FileManager.default.createDirectory(
            at: bottleURL.appending(path: "drive_c/windows/system32"), withIntermediateDirectories: true
        )
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.graphicsBackend = backend
        return bottle
    }

    private func makeExecutable(_ relativePath: String, in bottle: Bottle) throws -> URL {
        let url = bottle.url.appending(path: "drive_c").appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("MZ".utf8).write(to: url)
        return url
    }

    private func steam(in bottle: Bottle) throws -> URL {
        try makeExecutable("Program Files (x86)/Steam/steam.exe", in: bottle)
    }

    /// Prepares a Steam launch, `-silent` or `-applaunch`, against a pinned runtime.
    private func prepareSteam(
        _ bottle: Bottle, applaunch: Bool, plan: ProgramOverrides? = nil, recorder: ScopeRecorder
    ) async throws -> Wine.PreparedLaunch {
        try await Wine.prepareProgramLaunch(
            at: steam(in: bottle), args: applaunch ? ["-applaunch", "1174180"] : ["-silent"], bottle: bottle,
            programOverrides: plan, overridesApplyToDescendants: applaunch,
            recommendedBackend: .dxmt,
            overrideWriter: recorder.writer, importer: recorder.importer
        )
    }

    /// No translation layer anywhere: the runtime picks its graphics layer itself.
    private func expectNoTranslationLayer(_ overrides: [String: String]?, _ label: String) {
        for dll in ["dxgi", "d3d9", "d3d10core", "d3d11", "winemetal"] {
            #expect(overrides?[dll] == nil, "\(label) must not mention \(dll)")
        }
    }

    // MARK: - steam.exe -silent

    @Test("Starting Steam writes the client's and its helpers' entries, none of them a translation layer")
    func silentLaunchWritesTheClientEntries() async throws {
        let bottle = try makeBottle(.recommended)
        let recorder = ScopeRecorder()

        let launch = try await prepareSteam(bottle, applaunch: false, recorder: recorder)

        expectNoTranslationLayer(recorder.overrides(for: .bottle), "bottle")
        expectNoTranslationLayer(recorder.overrides(for: .program("steam.exe")), "steam.exe")
        expectNoTranslationLayer(recorder.overrides(for: .program("steamwebhelper.exe")), "steamwebhelper.exe")
        #expect(recorder.overrides(for: .program("steamwebhelper.exe"))?["nvapi64"] == "")
        #expect(launch.environment["WINEDLLOVERRIDES"] == nil)
    }

    // MARK: - steam.exe -applaunch

    @Test("A game launch keeps the helpers' entries and the environment free of overrides")
    func applaunchKeepsHelperEntries() async throws {
        let bottle = try makeBottle(.recommended)
        let recorder = ScopeRecorder()

        let launch = try await prepareSteam(bottle, applaunch: true, recorder: recorder)

        // A helper restarting after this launch reads the entry written here.
        #expect(recorder.overrides(for: .program("steamwebhelper.exe"))?["nvapi64"] == "")
        #expect(recorder.overrides(for: .program("steamservice.exe")) != nil)
        #expect(recorder.overrides(for: .program("steam.exe")) != nil)
        #expect(launch.environment["WINEDLLOVERRIDES"] == nil)
    }

    @Test("A game's own DLL overrides stay out of the environment and the prefix default")
    func applaunchKeepsTheGamePlanScoped() async throws {
        let bottle = try makeBottle(.recommended)
        let recorder = ScopeRecorder()
        var plan = ProgramOverrides()
        plan.dllOverrides = [DLLOverrideEntry(dllName: "xaudio2_7", mode: .native)]

        let launch = try await prepareSteam(bottle, applaunch: true, plan: plan, recorder: recorder)

        #expect(recorder.overrides(for: .bottle)?["xaudio2_7"] == nil)
        // The plan goes to the game's own entries (SteamGameLaunchScopingTests).
        #expect(launch.environment["WINEDLLOVERRIDES"] == nil)
    }

    @Test("The helpers get their entries whatever the bottle's own backend", arguments: GraphicsBackend.allCases)
    func helpersKeepEntriesOnAnyBackend(_ backend: GraphicsBackend) async throws {
        let bottle = try makeBottle(backend)
        bottle.settings.launcherMode = .manual
        bottle.settings.detectedLauncher = .steam
        let recorder = ScopeRecorder()

        _ = try await prepareSteam(bottle, applaunch: true, recorder: recorder)

        #expect(recorder.overrides(for: .program("steamwebhelper.exe")) != nil, "steamwebhelper.exe on \(backend)")
        #expect(recorder.overrides(for: .program("steam.exe")) != nil, "steam.exe on \(backend)")
    }

    // MARK: - Rockstar's chain inside a Steam session

    @Test(
        "A Steam launch writes Rockstar's launcher and Social Club entries once Rockstar is installed",
        arguments: [false, true]
    )
    func steamLaunchWritesRockstarChain(_ applaunch: Bool) async throws {
        let bottle = try makeBottle(.recommended)
        _ = try makeExecutable("Program Files/Rockstar Games/Launcher/Launcher.exe", in: bottle)
        let recorder = ScopeRecorder()

        _ = try await prepareSteam(bottle, applaunch: applaunch, recorder: recorder)

        for executable in ["Launcher.exe", "SocialClubHelper.exe"] {
            let entry = recorder.overrides(for: .program(executable))
            #expect(entry?["d3d12"] == "", "\(executable) must not reach d3d12")
        }
        expectNoTranslationLayer(recorder.overrides(for: .bottle), "bottle")
    }

    @Test("No Rockstar entries in a bottle without Rockstar's launcher")
    func noRockstarChainWithoutRockstar() async throws {
        let bottle = try makeBottle(.recommended)
        let recorder = ScopeRecorder()

        _ = try await prepareSteam(bottle, applaunch: false, recorder: recorder)

        #expect(!recorder.programScopes.contains("Launcher.exe"))
        #expect(!recorder.programScopes.contains("SocialClubHelper.exe"))
    }

    @Test("Launching Rockstar's launcher itself writes its entry once, from its own launch")
    func rockstarLaunchDoesNotDuplicateItsOwnEntry() async throws {
        let bottle = try makeBottle(.recommended)
        let launcher = try makeExecutable("Program Files/Rockstar Games/Launcher/Launcher.exe", in: bottle)
        let recorder = ScopeRecorder()

        _ = try await Wine.prepareProgramLaunch(
            at: launcher, bottle: bottle, recommendedBackend: .dxmt,
            overrideWriter: recorder.writer, importer: recorder.importer
        )

        #expect(recorder.programScopes.filter { $0.lowercased() == "launcher.exe" }.count == 1)
        #expect(recorder.programScopes.contains("SocialClubHelper.exe"))
    }
}
