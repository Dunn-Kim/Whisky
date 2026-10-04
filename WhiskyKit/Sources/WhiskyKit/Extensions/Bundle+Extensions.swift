//
//  Bundle+Extensions.swift
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

public extension Bundle {
    static var whiskyBundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.franke.Whisky"
    }
}

extension Bundle {
    /// Loads the bundled `<name>.json` with `load`. A missing or undecodable
    /// resource is a packaging bug: it asserts in debug builds and returns
    /// `nil` in release.
    func decodeJSONResource<T>(_ name: String, with load: (URL) throws -> T) -> T? {
        guard let url = url(forResource: name, withExtension: "json") else {
            Logger.wineKit.error("Missing resource: \(name).json")
            assertionFailure("Missing resource: \(name).json in \(bundleURL.lastPathComponent)")
            return nil
        }
        do {
            return try load(url)
        } catch {
            Logger.wineKit.error("Failed to decode \(name).json: \(error.localizedDescription)")
            assertionFailure("Failed to decode \(name).json: \(error)")
            return nil
        }
    }
}
