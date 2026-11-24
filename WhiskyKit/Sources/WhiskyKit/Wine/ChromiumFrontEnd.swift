//
//  ChromiumFrontEnd.swift
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

/// A program whose own window is drawn by Chromium, which stays black on
/// DXMT, while the programs it starts are games that should keep
/// them (#372).
///
/// Recommended runs the listed executables on WineD3D, one at a time, through
/// a compatdb rule each (``Wine/compatdbRules``).
/// The table is short and hand-verified: the rule is keyed on the file name
/// alone, so only distinctive names belong here, and a row is added only once
/// its layout was checked on a real install (``verifiedIn``).
///
/// An app goes into ``LauncherType`` instead when it needs anything more than
/// a per-executable WineD3D pin: environment, locale, launcher
/// diagnostics, or the bottle's detected launcher.
public struct ChromiumFrontEnd: Sendable, Equatable, Identifiable {
    /// A stable identifier for the row.
    public let id: String
    /// The product's name, as shown in the UI. Not localized.
    public let displayName: String
    /// The executables whose window Chromium draws. Same-executable Chromium
    /// children (its GPU process, say) share the entry.
    public let executables: [String]
    /// Separate helper executables that share the front end's set.
    public let helperExecutables: [String]
    /// The front end's Steam App ID, when it is sold on Steam.
    public let steamAppId: Int?
    /// The issue or pull request where the row's layout was verified.
    public let verifiedIn: String

    /// 3DMark: its menu is CEF and stays black on DXMT, while its
    /// benchmarks (Time Spy, Steel Nomad, the DLSS feature test) are D3D11 and
    /// D3D12 workloads that keep DXMT. Its Chromium GPU process runs as
    /// `3DMark.exe` itself, so the row lists no helper.
    public static let threeDMark = ChromiumFrontEnd(
        id: "3dmark",
        displayName: "3DMark",
        executables: ["3DMark.exe"],
        helperExecutables: [],
        steamAppId: 223_850,
        verifiedIn: "#372"
    )

    /// Every front end Recommended steers to WineD3D.
    public static let all: [ChromiumFrontEnd] = [.threeDMark]

    /// The front end an executable name belongs to, compared without case as
    /// Wine compares `AppDefaults` keys. Reads nothing from disk.
    public static func match(executableName: String) -> ChromiumFrontEnd? {
        let name = executableName.lowercased()
        guard !name.isEmpty else { return nil }
        return all.first { row in row.executables.contains { $0.lowercased() == name } }
    }

    /// The front end an executable belongs to, by its file name alone. A
    /// Windows-style path counts its last backslash-separated component.
    public static func match(url: URL) -> ChromiumFrontEnd? {
        let name = url.lastPathComponent.split(separator: "\\").last.map(String.init) ?? url.lastPathComponent
        return match(executableName: name)
    }

    /// Whether `libcef.dll` sits beside an executable: the program ships CEF,
    /// and its window may stay black off WineD3D. One `fileExists`. Never used
    /// to steer anything: a game can ship CEF for an overlay. It only feeds the
    /// diagnostics export.
    public static func shipsCEF(beside url: URL) -> Bool {
        let library = url.deletingLastPathComponent().appending(path: "libcef.dll")
        return FileManager.default.fileExists(atPath: library.path(percentEncoded: false))
    }
}
