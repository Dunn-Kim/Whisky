//
//  WineCompatdbRules.swift
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

import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "WineCompatdbRules")

extension Wine {
    /// The `WINE_COMPATDB` value that carries the graphics backend choice to the
    /// runtime: one rule per line, `exe=<name>;dxgi=...;d3d9=...`. The runtime lets
    /// a rule naming an executable beat `exe=*` whatever the line order.
    ///
    /// Lines, later replacing earlier ones for the same executable name: the
    /// bottle's explicit backend as `exe=*`; under a Recommended bottle, the
    /// Chromium front ends of the table and `steeredExecutables` on WineD3D;
    /// then each of `programBackends`. An explicit bottle backend applies to
    /// Chromium-drawn programs too, as the Graphics section tells the user.
    /// Recommended adds no rule, except for a program under an explicit bottle
    /// backend, where it means the recommended one: WineD3D when it is steered.
    ///
    /// - Parameter userRules: Rules a user or a GameDB profile already set; kept after the app's.
    /// - Returns: The value, or `nil` when there are no rules at all.
    static func compatdbRules(
        bottleBackend: GraphicsBackend,
        steeredExecutables: [String],
        programBackends: [(executable: String, backend: GraphicsBackend)],
        userRules: String? = nil
    ) -> String? {
        func fields(_ backend: GraphicsBackend) -> String? {
            switch backend {
            case .dxmt: "dxgi=dxmt"
            case .wined3d: "dxgi=wined3d;d3d9=wined3d"
            case .recommended: nil
            }
        }
        var lines: [(key: String, line: String)] = []
        func add(_ executable: String, _ fields: String?) {
            guard let fields, !executable.isEmpty else { return }
            let key = executable.lowercased()
            let entry = (key: key, line: "exe=\(compatdbEscaped(executable));\(fields)")
            if let index = lines.firstIndex(where: { $0.key == key }) {
                lines[index] = entry
            } else {
                lines.append(entry)
            }
        }

        add("*", fields(bottleBackend))
        let steered = ChromiumFrontEnd.all.flatMap { $0.executables + $0.helperExecutables } + steeredExecutables
        if bottleBackend == .recommended {
            steered.forEach { add($0, fields(.wined3d)) }
        }
        for (executable, backend) in programBackends {
            if backend == .recommended {
                guard bottleBackend != .recommended else { continue }
                let isSteered = steered.contains { $0.lowercased() == executable.lowercased() }
                add(executable, fields(isSteered ? .wined3d : GraphicsBackendResolver.resolve()))
            } else {
                add(executable, fields(backend))
            }
        }

        var output = lines.map(\.line)
        if let userRules, !userRules.isEmpty {
            output.append(userRules)
        }
        return output.isEmpty ? nil : output.joined(separator: "\n")
    }

    /// A rule field's value with what would end the field, the rule or the
    /// value's name written as `%XX`, which the runtime decodes.
    static func compatdbEscaped(_ value: String) -> String {
        // Scalars, not Characters: a combining mark after `;` would otherwise join it into one
        // Character that no case matches.
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "%", ";", "=", "\n", "\r":
                result += String(scalar).utf8.map { String(format: "%%%02X", $0) }.joined()
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// The `WINE_COMPATDB_FILE` every `steam.exe` launch of the bottle names:
    /// the rules of the game the last Steam launch from Whisky started.
    ///
    /// Only `steam.exe` is given it, so it reaches the client and what the
    /// client starts, never a program launched on its own.
    static func steamGameRulesURL(bottleURL: URL) -> URL {
        bottleURL.appending(path: "Steam Game Rules.compatdb")
    }

    /// Variables a Steam game's rule leaves to the client: the prefix and the
    /// sync mode belong to the bottle's one wineserver, the DLL overrides are
    /// in the game's `AppDefaults` entries, and the rules are this mechanism.
    static let steamGameRuleOmittedVariables: Set<String> = [
        "WINEPREFIX", "WINEMSYNC", "WINEDLLOVERRIDES", "WINE_COMPATDB", "WINE_COMPATDB_FILE"
    ]

    /// The rules a Steam launch leaves for the game the client starts.
    ///
    /// A running client starts the game with its own environment, not the
    /// `-applaunch` invocation's, so the plan's frame cap, HUD and GameDB
    /// variables reach the game only this way. The runtime reads the file at
    /// every process start, and a file rule beats a `WINE_COMPATDB` one.
    ///
    /// One rule gives every process with the game's `SteamAppId` the launch's
    /// environment, except ``steamGameRuleOmittedVariables``. Then come the
    /// launch's own `WINE_COMPATDB` lines for the game's executables, which
    /// carry their backend.
    ///
    /// shortcut: a variable the plan removes (a HUD turned off for the game)
    /// stays as the client has it, and the file holds one game, so a game
    /// launched while another runs drops the first one's rules for the processes
    /// it starts later. Keep a section per App ID if that matters.
    ///
    /// - Parameters:
    ///   - appID: The game's Steam App ID.
    ///   - environment: The `-applaunch` invocation's environment.
    ///   - executables: The names of the game's executables, and of those that keep their own settings.
    /// - Returns: The file's contents.
    static func steamGameRules(appID: Int, environment: [String: String], executables: [String]) -> String {
        let variables = environment.keys.sorted()
            .filter { !steamGameRuleOmittedVariables.contains($0) }
            .map { "env=\(compatdbEscaped($0))=\(compatdbEscaped(environment[$0] ?? ""))" }
        let names = Set(executables.map { "exe=\(compatdbEscaped($0))".lowercased() })
        let ownLines = (environment["WINE_COMPATDB"] ?? "").split(separator: "\n").filter { line in
            names.contains(line.prefix { $0 != ";" }.lowercased())
        }
        let gameLine = (["exe=steam:\(appID)"] + variables).joined(separator: ";")
        return ([gameLine] + ownLines.map(String.init)).joined(separator: "\n") + "\n"
    }

    /// Writes a bottle's ``steamGameRulesURL(bottleURL:)``. A failure is only
    /// logged: the game still starts, with the client's environment.
    static func writeSteamGameRules(_ rules: String, bottleURL: URL) {
        do {
            try Data(rules.utf8).write(to: steamGameRulesURL(bottleURL: bottleURL), options: .atomic)
        } catch {
            logger.error("Could not write the Steam game rules: \(error.localizedDescription)")
        }
    }
}
