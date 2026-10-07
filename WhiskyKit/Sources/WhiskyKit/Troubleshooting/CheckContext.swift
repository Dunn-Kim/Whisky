//
//  CheckContext.swift
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

/// Context passed to every ``TroubleshootingCheck`` implementation.
///
/// Provides the bottle and program identity and the preflight data snapshot
/// as `Sendable` values.
public struct CheckContext: Sendable {
    /// URL of the bottle being troubleshot.
    public let bottleURL: URL

    /// Display name of the program, if any.
    public let programName: String?

    /// Preflight data snapshot collected at session start.
    public let preflight: PreflightData

    public init(
        bottleURL: URL,
        programName: String? = nil,
        preflight: PreflightData
    ) {
        self.bottleURL = bottleURL
        self.programName = programName
        self.preflight = preflight
    }
}
