//
//  TroubleshootingHistoryEntry.swift
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

/// A redacted summary of a completed troubleshooting session.
///
/// Contains only the essential metadata from a session -- no raw log content
/// or sensitive payloads are stored. Used by ``TroubleshootingHistory`` for
/// bounded per-bottle history.
public struct TroubleshootingHistoryEntry: Codable, Sendable, Identifiable {
    /// Unique identifier for this history entry.
    public var id: UUID = UUID()

    /// The symptom category that was investigated.
    public let symptomCategory: SymptomCategory

    /// The final outcome of the session.
    public let outcome: TroubleshootingSession.SessionOutcome

    /// Summary descriptions of key findings during the session.
    public let primaryFindings: [String]

    /// Human-readable descriptions of fix results.
    public let fixResults: [String]

    /// When the troubleshooting session completed.
    public let completedAt: Date

    /// The name of the program that was troubleshot, if any.
    public let programName: String?

    /// The name of the bottle where troubleshooting occurred.
    public let bottleName: String
}
