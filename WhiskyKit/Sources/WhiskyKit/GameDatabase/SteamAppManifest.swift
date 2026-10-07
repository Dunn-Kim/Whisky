//
//  SteamAppManifest.swift
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

/// A parsed Steam application manifest (`appmanifest_<appid>.acf`).
///
/// Steam stores application metadata in ACF/VDF format files alongside
/// installed games. This type parses those files fully via ``VDFParser``,
/// and also finds App IDs in `steam_appid.txt` files next to executables.
///
/// ## ACF Format
///
/// Valve's ACF (App Cache File) format uses `"key"\t\t"value"` pairs:
/// ```
/// "AppState"
/// {
///     "appid"     "1245620"
///     "name"      "Elden Ring"
/// }
/// ```
public struct SteamAppManifest: Equatable, Sendable {
    /// The Steam App ID.
    public let appId: Int
    /// The display name of the app.
    public let name: String
    /// The install directory name, relative to `<library>/steamapps/common/`.
    public let installDir: String
    /// Steam's install-state bitmask. Bit 4 means fully installed.
    public let stateFlags: Int
    /// When Steam last recorded the app exiting, absent if it never has.
    ///
    /// Steam's own record, so it covers sessions started from inside the client
    /// as well as ones Whisky started, and it is already there for everything
    /// installed before Whisky began recording launches itself. It is written on
    /// exit, so a game that is running still reads as its previous session.
    public let lastPlayed: Date?

    /// Whether Steam considers the app fully installed (not downloading,
    /// updating, or partially removed).
    public var isFullyInstalled: Bool {
        stateFlags & 4 != 0
    }

    /// Parses a manifest file.
    ///
    /// - Parameter url: The URL to an `appmanifest_*.acf` file.
    /// - Returns: `nil` if the file can't be read, isn't valid VDF, or lacks
    ///   the required `appid`, `name`, or `installdir` fields.
    public init?(contentsOf url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let root = try? VDFParser.parse(text),
              let appState = root["appstate"]?.objectValue,
              let appId = appState["appid"]?.intValue,
              let name = appState["name"]?.stringValue,
              let installDir = appState["installdir"]?.stringValue
        else { return nil }

        self.appId = appId
        self.name = name
        self.installDir = installDir
        self.stateFlags = appState["stateflags"]?.intValue ?? 0
        // Unix seconds, and zero for an app that has never been played rather
        // than an absent key.
        self.lastPlayed = appState["lastplayed"]?.intValue
            .flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
    }

    /// Searches for a Steam App ID near a specific executable.
    ///
    /// Checks for `steam_appid.txt` in the executable's directory and
    /// up to three parent directories. The file should contain a plain
    /// integer App ID.
    ///
    /// - Parameter exeURL: The URL to the game executable.
    /// - Returns: The parsed App ID, or `nil` if not found.
    public static func findAppIdForProgram(at exeURL: URL) -> Int? {
        let fileManager = FileManager.default
        var directory = exeURL.deletingLastPathComponent()

        // Check exe directory and up to 3 parent directories
        for _ in 0 ..< 4 {
            let appIdFile = directory.appending(path: "steam_appid.txt")
            let filePath = appIdFile.path(percentEncoded: false)

            if fileManager.fileExists(atPath: filePath),
               let text = try? String(contentsOf: appIdFile, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let appId = Int(trimmed) {
                    return appId
                }
            }

            directory = directory.deletingLastPathComponent()
        }

        return nil
    }
}
