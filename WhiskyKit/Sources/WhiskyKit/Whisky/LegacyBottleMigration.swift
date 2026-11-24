//
//  LegacyBottleMigration.swift
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

/// The file work of copying a bottle of another Whisky app into a new bottle of this one.
///
/// Every function only reads the source. The app runs them in this order: ``copySettings(from:to:)``,
/// ``rewriteSettings(in:from:)``, then (with the new prefix created and its wineserver stopped)
/// ``mergeDriveC(from:to:)`` and ``spliceRegistries(from:to:)``.
public extension LegacyBottleImport {
    /// The files of the source bottle that carry over verbatim. The dependency records
    /// (`dependency-history.plist`, `WinetricksCache.plist`, `winetricks.log`) are left behind
    /// because what they record lives in `drive_c/windows`, which is not carried over.
    private static let carriedFiles = ["Metadata.plist", "Program Settings", "HandledShortcuts.plist"]

    /// Copies the settings files of `source` into the new bottle folder `destination`.
    static func copySettings(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        for name in carriedFiles {
            let item = source.appending(path: name)
            guard fileManager.fileExists(atPath: item.path(percentEncoded: false)) else { continue }
            try fileManager.copyItem(at: item, to: destination.appending(path: name))
        }
    }

    /// Points every path the copied settings keep into `source` at `destination` instead, and
    /// records `source` as the migration source.
    ///
    /// Program settings files are keyed by the program's path relative to its bottle
    /// (``Program/settingsIdentity(for:bottleURL:)``), so none of them is renamed.
    ///
    /// - Returns: The rewritten bottle settings.
    @discardableResult
    static func rewriteSettings(in destination: URL, from source: URL) throws -> BottleSettings {
        let metadata = destination.appending(path: "Metadata").appendingPathExtension("plist")
        var settings = try PropertyListDecoder().decode(BottleSettings.self, from: Data(contentsOf: metadata))
        func rebase(_ url: URL) -> URL {
            rebased(url, from: source, to: destination)
        }
        settings.pins = settings.pins.map { pin in
            var pin = pin
            pin.url = pin.url.map(rebase)
            return pin
        }
        settings.blocklist = settings.blocklist.map(rebase)
        settings.unpinnedPrograms = settings.unpinnedPrograms.map(rebase)
        settings.migratedFrom = source.standardizedFileURL
        try settings.encode(to: metadata)

        let programSettings = destination.appending(path: "Program Settings")
        let files = (try? FileManager.default.contentsOfDirectory(at: programSettings, includingPropertiesForKeys: nil))
            ?? []
        for file in files where file.pathExtension == "plist" {
            guard var program = try? ProgramSettings.decodeIfPresent(from: file),
                  let log = program.lastLogFileURL, rebase(log) != log
            else { continue }
            program.lastLogFileURL = rebase(log)
            try program.encode(to: file)
        }
        return settings
    }

    /// `url` moved from under `source` to the same place under `destination`; any other URL
    /// comes back unchanged.
    static func rebased(_ url: URL, from source: URL, to destination: URL) -> URL {
        func trimmed(_ url: URL) -> String {
            var path = url.standardizedFileURL.path(percentEncoded: false)
            while path.count > 1, path.hasSuffix("/") {
                path.removeLast()
            }
            return path
        }
        let root = trimmed(source)
        let path = trimmed(url)
        guard path == root || path.hasPrefix(root + "/") else { return url }
        return URL(
            fileURLWithPath: trimmed(destination) + path.dropFirst(root.count),
            isDirectory: url.hasDirectoryPath
        )
    }

    // MARK: - drive_c

    /// Adds what the new `drive_c` lacks from the source's.
    ///
    /// An entry missing in `destination` is copied whole (APFS clones it); a directory in both is
    /// merged entry by entry; a file in both stays as the new prefix has it, so its arm64 Wine files
    /// are not overwritten by x86 ones. `windows` is skipped except `windows/Fonts`. Symlinks are
    /// copied as symlinks and never followed.
    static func mergeDriveC(from source: URL, to destination: URL) throws {
        for entry in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            let name = entry.lastPathComponent
            if name.lowercased() == "windows" {
                let fonts = entry.appending(path: "Fonts")
                if itemType(at: fonts) != nil {
                    try mergeEntry(fonts, into: destination.appending(path: name).appending(path: "Fonts"))
                }
            } else {
                try mergeEntry(entry, into: destination.appending(path: name))
            }
        }
    }

    private static func mergeEntry(_ source: URL, into destination: URL) throws {
        let fileManager = FileManager.default
        var existing = itemType(at: destination)
        // A fresh prefix links the profile's Desktop, Documents and the like to the Mac's
        // own folders, where the source bottle has real ones. Replace the link (removeItem
        // never follows it), so the source's files land in the bottle, not in the Mac's folders.
        if existing == .typeSymbolicLink, itemType(at: source) == .typeDirectory {
            try fileManager.removeItem(at: destination)
            existing = nil
        }
        guard let existing else {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: destination)
            return
        }
        guard existing == .typeDirectory, itemType(at: source) == .typeDirectory else { return }
        for child in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            try mergeEntry(child, into: destination.appending(path: child.lastPathComponent))
        }
    }

    /// The type of the item at `url` without following a symlink, or `nil` when nothing is there.
    private static func itemType(at url: URL) -> FileAttributeType? {
        try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.type] as? FileAttributeType
    }

    // MARK: - Registry

    /// Adds the vendor settings of the source's `user.reg` and `system.reg` to the new prefix's.
    ///
    /// Run it with the new prefix's wineserver stopped, since the server rewrites both files.
    static func spliceRegistries(from source: URL, to destination: URL) throws {
        for (file, filter) in [("user.reg", keepsUserKey), ("system.reg", keepsSystemKey)] {
            let sourceFile = source.appending(path: file)
            let destinationFile = destination.appending(path: file)
            guard let (sourceText, _) = readRegistry(sourceFile),
                  let (destinationText, encoding) = readRegistry(destinationFile)
            else { continue }
            let spliced = spliceRegistry(source: sourceText, into: destinationText, keeping: filter)
            guard let data = spliced.data(using: encoding) else { continue }
            try data.write(to: destinationFile, options: .atomic)
        }
    }

    /// The text of a registry file and the encoding it was read in: UTF-8, else ISO Latin-1.
    private static func readRegistry(_ url: URL) -> (String, String.Encoding)? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let text = String(data: data, encoding: .utf8) {
            return (text, .utf8)
        }
        return String(data: data, encoding: .isoLatin1).map { ($0, .isoLatin1) }
    }

    /// `destination` with every section of `source` appended whose key path `keep` accepts and
    /// that `destination` lacks (keys compare case-insensitively). Section text stays verbatim.
    ///
    /// A section starts at a line `[<key path>] <timestamp>` and runs to the next line starting
    /// with `[`; the lines before the first section are the header and are not carried over.
    static func spliceRegistry(
        source: String, into destination: String, keeping keep: (_ keyPath: String) -> Bool
    ) -> String {
        var known = Set(sections(of: destination).map { $0.key.lowercased() })
        var result = destination
        for section in sections(of: source) where !known.contains(section.key.lowercased()) && keep(section.key) {
            known.insert(section.key.lowercased())
            if !result.isEmpty, !result.hasSuffix("\n") {
                result += "\n"
            }
            result += section.lines.joined(separator: "\n") + "\n"
        }
        return result
    }

    private static func sections(of text: String) -> [(key: String, lines: [String])] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" {
            lines.removeLast()
        }
        var result: [(key: String, lines: [String])] = []
        for line in lines {
            if line.hasPrefix("["), let close = line.lastIndex(of: "]") {
                result.append((String(line[line.index(after: line.startIndex) ..< close]), [line]))
            } else if !result.isEmpty {
                result[result.count - 1].lines.append(line)
            }
        }
        return result
    }

    /// Whether `key` is `root` or lies under it. Keys are written as in the file, with doubled backslashes.
    private static func isKey(_ key: String, under root: String) -> Bool {
        let key = key.lowercased()
        let root = root.lowercased()
        return key == root || key.hasPrefix(root + "\\\\")
    }

    /// `user.reg`: the application settings under `Software`, not Wine's or Windows' own, plus
    /// the font replacements.
    static func keepsUserKey(_ key: String) -> Bool {
        if isKey(key, under: "Software\\\\Wine\\\\Fonts\\\\Replacements") {
            return true
        }
        guard isKey(key, under: "Software"), key.lowercased() != "software" else { return false }
        return !["Microsoft", "Classes", "Wine"].contains { isKey(key, under: "Software\\\\\($0)") }
    }

    private static let excludedVendors: Set<String> = [
        "microsoft", "wine", "classes", "clients", "policies", "registeredapplications", "odbc"
    ]

    /// `system.reg`: a vendor key `Software\<Vendor>` or `Software\Wow6432Node\<Vendor>`.
    static func keepsSystemKey(_ key: String) -> Bool {
        var parts = key.lowercased().components(separatedBy: "\\\\")
        guard parts.first == "software" else { return false }
        parts.removeFirst()
        if parts.first == "wow6432node" {
            parts.removeFirst()
        }
        guard let vendor = parts.first, !vendor.isEmpty else { return false }
        return !excludedVendors.contains(vendor)
    }
}
