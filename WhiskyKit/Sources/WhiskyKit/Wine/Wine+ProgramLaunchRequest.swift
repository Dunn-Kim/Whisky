//
//  Wine+ProgramLaunchRequest.swift
//  WhiskyKit
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

import AppKit
import CryptoKit
import Foundation

extension Wine {
    /// What a launch asks of `prepareProgramLaunch` besides the program and its
    /// bottle: the launch parameters of `runProgram`, carried as one value so a
    /// caller's request reaches the preparation whole.
    ///
    /// Every field is required, so a parameter cannot be left behind on the way.
    struct ProgramLaunchRequest {
        /// Command-line arguments to pass to the program.
        let args: [String]
        /// Additional environment variables for this execution.
        let environment: [String: String]
        /// Per-program setting overrides. `nil` fields inherit from the bottle.
        let programOverrides: ProgramOverrides?
        /// The program's settings, which carry its diagnostic `WINEDEBUG` preset.
        let programSettings: ProgramSettings?
        /// Environment variables from the game's GameDB profile.
        let gameProfileEnvironment: [String: String]
        /// Whether the DLL overrides belong to a process this one spawns.
        let overridesApplyToDescendants: Bool
        /// The executable names of what this launch starts.
        let descendantExecutables: [String]
        /// Executables among what this launch starts that keep their own settings.
        let ownSettingsExecutables: [URL]
        /// Launchers what this launch starts brings up on its own.
        let descendantLaunchers: [LauncherType]
    }

    /// Runs a program the way the public `runProgram` does, from a request.
    ///
    /// - Parameters:
    ///   - url: The URL to the Windows executable (.exe) file.
    ///   - bottle: The ``Bottle`` in which to run the program.
    ///   - request: What the launch asks for.
    ///   - onOutput: Receives the launch's output events as they arrive.
    /// - Returns: The exit code and log file of the run.
    /// - Throws: An error if the program cannot be started or Wine encounters an error.
    @MainActor
    static func runProgram(
        at url: URL, bottle: Bottle, request: ProgramLaunchRequest,
        onOutput: (@MainActor (ProcessOutput) -> Void)?
    ) async throws -> ProgramRunResult {
        try await runProgram(at: url, bottle: bottle, programSettings: request.programSettings, onOutput: onOutput) {
            // Run... and opening a file with Whisky launch through here, so the
            // audio settings (the pinned output device among them) reach the
            // registry on these launches too.
            await syncAudioRegistry(bottle: bottle)
            return try await prepareProgramLaunch(at: url, bottle: bottle, request: request)
        }
    }

    /// Prepares a bottle for a request, as `runProgram` does before it starts the program.
    ///
    /// - Parameters:
    ///   - url: The URL to the Windows executable (.exe) file.
    ///   - bottle: The ``Bottle`` in which to run the program.
    ///   - request: What the launch asks for.
    ///   - recommendedBackend: What `.recommended` resolves to for the bottle's games.
    ///   - overrideWriter: What writes the DLL overrides into the prefix registry.
    ///   - importer: What imports the CJK font aliases the prefix is missing.
    /// - Returns: The environment and `wine` arguments the launch runs with.
    /// - Throws: An error if the DLL override import cannot be started.
    @MainActor
    static func prepareProgramLaunch(
        at url: URL, bottle: Bottle, request: ProgramLaunchRequest,
        recommendedBackend: GraphicsBackend = GraphicsBackendResolver.resolve(),
        overrideWriter: DLLOverrideWriter = { try await syncDLLOverrides(bottle: $0, scopes: $1) },
        importer: RegistryImporter = { try await importRegistry(document: $0, bottle: $1) }
    ) async throws -> PreparedLaunch {
        try await prepareProgramLaunch(
            at: url, args: request.args, bottle: bottle, environment: request.environment,
            programOverrides: request.programOverrides, programSettings: request.programSettings,
            gameProfileEnvironment: request.gameProfileEnvironment,
            overridesApplyToDescendants: request.overridesApplyToDescendants,
            descendantExecutables: request.descendantExecutables,
            ownSettingsExecutables: request.ownSettingsExecutables,
            descendantLaunchers: request.descendantLaunchers,
            recommendedBackend: recommendedBackend,
            overrideWriter: overrideWriter, importer: importer
        )
    }

    /// The program's icon as a file, for runtimes that take the Dock icon from the host.
    ///
    /// The 4.8 runtimes read `WINE_APP_ICON_PATH`. Without it some programs
    /// stay on macOS's generic executable icon although their `.exe` carries
    /// one (Mecharashi, a Unity game, does). `WINE_APP_IDENTITY_EXE` keeps the
    /// icon off the other programs the launch starts. Older runtimes ignore both.
    ///
    /// - Parameters:
    ///   - icon: The program's icon, or `nil` when it has none.
    ///   - url: The program's executable.
    ///   - folder: Where the icon file is written. The system clears the
    ///     default, and every launch writes the file again.
    /// - Returns: The variables to add, or none without an icon.
    static func dockIconEnvironment(
        icon: NSImage?, for url: URL,
        folder: URL = FileManager.default.temporaryDirectory.appending(path: "WhiskyDockIcons")
    ) -> [String: String] {
        guard let icon else { return [:] }
        let name = SHA256.hash(data: Data(url.path(percentEncoded: false).utf8))
            .prefix(8).map { String(format: "%02x", $0) }.joined()
        let file = folder.appending(path: name).appendingPathExtension("icns")
        guard ShortcutIcon.write(icon, to: file) else { return [:] }
        return [
            "WINE_APP_ICON_PATH": file.path(percentEncoded: false),
            "WINE_APP_IDENTITY_EXE": url.lastPathComponent
        ]
    }
}
