//
//  ClickOnceManager.swift
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

/// ClickOnce application detection.
///
/// ClickOnce is a Microsoft deployment technology that uses `.appref-ms` files as
/// application references. This finds those files inside a Wine bottle and reads
/// the deployment URL from them.
public enum ClickOnceManager {
    private static let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "ClickOnceManager")

    /// Resolves the Wine username for a bottle, preferring the actual user
    /// directory found in `drive_c/users/` and falling back to "crossover".
    private static func resolveWineUsername(for bottle: Bottle) -> String {
        let usersDir = bottle.url.appending(path: "drive_c").appending(path: "users")
        return WinePrefixValidation.detectWineUsername(in: usersDir) ?? WineUserProfile.crossOverName
    }

    // MARK: - Detection

    /// Detects ClickOnce application reference files in a bottle.
    ///
    /// This method scans the standard ClickOnce installation directory within
    /// the Wine bottle for `.appref-ms` files.
    ///
    /// - Parameters:
    ///   - bottle: The bottle to scan for ClickOnce apps
    ///   - wineUsername: The Wine username for path construction. When `nil`
    ///     the username is auto-detected from the bottle's `drive_c/users`
    ///     directory (falling back to "crossover").
    /// - Returns: Array of URLs to detected `.appref-ms` files
    public static func detectAppRefFile(in bottle: Bottle, wineUsername: String? = nil) -> [URL] {
        let resolvedUsername = wineUsername ?? resolveWineUsername(for: bottle)
        let clickOnceDir = bottle.url
            .appending(path: "drive_c")
            .appending(path: "users")
            .appending(path: resolvedUsername)
            .appending(path: "AppData")
            .appending(path: "Roaming")
            .appending(path: "Microsoft")
            .appending(path: "ClickOnce")

        guard FileManager.default.fileExists(atPath: clickOnceDir.path) else {
            logger.debug("ClickOnce directory not found: \(clickOnceDir.path)")
            return []
        }

        var appRefFiles: [URL] = []

        // Recursively scan for .appref-ms files
        if let enumerator = FileManager.default.enumerator(at: clickOnceDir, includingPropertiesForKeys: nil) {
            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.pathExtension == "appref-ms" {
                    appRefFiles.append(fileURL)
                    logger.debug("Found ClickOnce appref: \(fileURL.lastPathComponent)")
                }
            }
        }

        logger
            .info("Detected \(appRefFiles.count) ClickOnce application(s) in bottle '\(bottle.url.lastPathComponent)'")
        return appRefFiles
    }

    // MARK: - Parsing

    /// Returns the deployment URL from a ClickOnce application reference file.
    ///
    /// The `.appref-ms` file is a small text file (similar to a Windows Internet Shortcut)
    /// that typically contains a `URL=` line pointing at a ClickOnce deployment URL:
    ///
    ///     [InternetShortcut]
    ///     URL=<url or percent-encoded url>
    ///
    /// - Parameter appRefURL: URL to the `.appref-ms` file
    /// - Returns: The deployment URL, or nil if the file is missing or has no valid URL
    public static func deploymentURL(for appRefURL: URL) -> URL? {
        guard let content = try? String(contentsOf: appRefURL, encoding: .utf8) else {
            logger.debug("Could not read \(appRefURL.lastPathComponent)")
            return nil
        }
        guard let rawURLString = urlString(in: content) else {
            logger.debug("No URL found in \(appRefURL.lastPathComponent)")
            return nil
        }
        let url = URL(string: normalizeURLString(rawURLString))
        if url == nil {
            logger.debug("Invalid URL in \(appRefURL.lastPathComponent)")
        }
        return url
    }

    private static func urlString(in content: String) -> String? {
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 4, trimmed.prefix(4).lowercased() == "url=" else { continue }

            let value = trimmed.dropFirst(4).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func normalizeURLString(_ rawURLString: String) -> String {
        // Many `.appref-ms` files contain a plain URL, but some include a percent-encoded URL
        // (and a few are doubly-encoded). Decode conservatively and only apply the second
        // decode when it results in a valid URL.
        let decodedOnce = rawURLString.removingPercentEncoding ?? rawURLString
        if URL(string: decodedOnce) != nil {
            return decodedOnce
        }

        let decodedTwice = decodedOnce.removingPercentEncoding ?? decodedOnce
        if URL(string: decodedTwice) != nil {
            return decodedTwice
        }

        return decodedOnce
    }

    // MARK: - Display Helpers

    /// Returns a user-friendly display name for a ClickOnce application reference file.
    ///
    /// Takes the deployment URL's last path component with any trailing
    /// `.application` suffix removed, falling back to the file name.
    ///
    /// - Parameter appRefURL: URL to the `.appref-ms` file
    /// - Returns: A friendly display name string
    public static func displayName(for appRefURL: URL) -> String {
        let fallbackName = appRefURL.deletingPathExtension().lastPathComponent
        guard var name = deploymentURL(for: appRefURL)?.lastPathComponent else { return fallbackName }
        if name.hasSuffix(".application") {
            name = String(name.dropLast(".application".count))
        }
        return name.isEmpty ? fallbackName : name
    }
}
