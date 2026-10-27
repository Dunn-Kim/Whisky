//
//  FileManager+Extensions.swift
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

extension FileManager {
    /// Installs `sourceURL` at `destinationURL`, replacing any existing file;
    /// the copy also happens when the destination does not exist yet. A silently
    /// skipped install would leave a translation layer half-deployed with no error.
    ///
    /// The replace is non-destructive on failure: the source is copied to a
    /// sibling temp file first and only swapped into place once the copy
    /// succeeds, so an unreadable source or an interrupted copy can never leave
    /// the destination missing (which would degrade even unrelated launches
    /// when the destination is a shared runtime file).
    func installFile(at destinationURL: URL, from sourceURL: URL) throws {
        guard fileExists(atPath: destinationURL.path(percentEncoded: false)) else {
            try copyItem(at: sourceURL, to: destinationURL)
            return
        }
        let tempURL = destinationURL.appendingPathExtension("whisky-tmp")
        if fileExists(atPath: tempURL.path(percentEncoded: false)) {
            try removeItem(at: tempURL)
        }
        try copyItem(at: sourceURL, to: tempURL)
        _ = try replaceItemAt(destinationURL, withItemAt: tempURL)
    }

    /// Installs `sourceURL` at `destinationURL` only when the destination is
    /// missing or its contents differ. Returns `true` when a copy happened.
    /// Used for idempotent placement of runtime components that a runtime
    /// update may revert (the installer replaces all of `Libraries/`).
    @discardableResult
    func installFileIfContentDiffers(at destinationURL: URL, from sourceURL: URL) throws -> Bool {
        if fileExists(atPath: destinationURL.path(percentEncoded: false)),
           let existing = try? Data(contentsOf: destinationURL),
           let replacement = try? Data(contentsOf: sourceURL),
           existing == replacement {
            return false
        }
        try installFile(at: destinationURL, from: sourceURL)
        return true
    }
}
