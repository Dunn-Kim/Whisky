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

extension Wine {
    /// The `WINE_COMPATDB` value that carries the graphics backend choice to the
    /// runtime: one rule per line, `exe=<name>;dxgi=...;d3d9=...`. The runtime lets
    /// a rule naming an executable beat `exe=*` whatever the line order.
    ///
    /// Lines, later replacing earlier ones for the same executable name: the
    /// bottle's explicit backend as `exe=*`; the Chromium front ends of the
    /// table and `steeredExecutables` on WineD3D; then each of `programBackends`.
    /// Recommended adds no rule, except for a program under an explicit bottle
    /// backend, where it means the recommended one.
    ///
    /// - Parameter userRules: Rules a user or a GameDB profile already set; kept after the app's.
    /// - Returns: The value, or `nil` when there are no rules at all.
    static func compatdbRules(
        bottleBackend: GraphicsBackend,
        steeredExecutables: [String],
        programBackends: [(executable: String, backend: GraphicsBackend)],
        recommendedBackend: GraphicsBackend = .dxmt,
        userRules: String? = nil
    ) -> String? {
        func fields(_ backend: GraphicsBackend) -> String? {
            switch backend {
            case .dxmt: "dxgi=dxmt"
            case .wined3d: "dxgi=wined3d;d3d9=wined3d"
            case .recommended: nil
            }
        }
        func escaped(_ name: String) -> String {
            var result = ""
            for character in name {
                switch character {
                case "%", ";", "=", "\n", "\r", "\r\n":
                    result += character.utf8.map { String(format: "%%%02X", $0) }.joined()
                default:
                    result.append(character)
                }
            }
            return result
        }

        var lines: [(key: String, line: String)] = []
        func add(_ executable: String, _ fields: String?) {
            guard let fields, !executable.isEmpty else { return }
            let key = executable.lowercased()
            let entry = (key: key, line: "exe=\(escaped(executable));\(fields)")
            if let index = lines.firstIndex(where: { $0.key == key }) {
                lines[index] = entry
            } else {
                lines.append(entry)
            }
        }

        add("*", fields(bottleBackend))
        let steered = ChromiumFrontEnd.all.flatMap { $0.executables + $0.helperExecutables } + steeredExecutables
        for executable in steered {
            add(executable, fields(.wined3d))
        }
        for (executable, backend) in programBackends {
            if backend == .recommended {
                guard bottleBackend != .recommended,
                      !steered.contains(where: { $0.lowercased() == executable.lowercased() })
                else { continue }
                add(executable, fields(recommendedBackend))
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
}
