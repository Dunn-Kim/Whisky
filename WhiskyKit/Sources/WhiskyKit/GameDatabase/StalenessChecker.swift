//
//  StalenessChecker.swift
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

/// Flags game database entries tested long ago or on an older macOS.
///
/// An entry is stale when it was last tested more than 90 days ago, or on a
/// macOS older than this one by a major release or more than one minor
/// release. Stale entries show a warning but are not blocked from being applied.
public enum StalenessChecker {
    /// The number of days after which an entry is considered date-stale.
    private static let stalenessThresholdDays: Double = 90

    /// A user-facing warning for a stale entry, or `nil` when it is fresh.
    public static func warning(for testedWith: TestedWith) -> String? {
        var messageParts: [String] = []

        let daysSinceTested = Date().timeIntervalSince(testedWith.lastTestedAt) / 86_400
        if daysSinceTested > stalenessThresholdDays {
            messageParts.append("last tested \(Int(daysSinceTested)) days ago")
        }

        let current = ProcessInfo.processInfo.operatingSystemVersion
        let currentVersion = "\(current.majorVersion).\(current.minorVersion).\(current.patchVersion)"
        if isMacOSVersionStale(tested: testedWith.macOSVersion, current: currentVersion) {
            messageParts.append("on macOS \(testedWith.macOSVersion)")
        }

        return messageParts.isEmpty ? nil : "This config was \(messageParts.joined(separator: ", "))."
    }

    /// Whether `current` is newer than `tested` by a major release or by more
    /// than one minor release. Unparseable versions are never stale.
    static func isMacOSVersionStale(tested: String, current: String) -> Bool {
        let testedParts = tested.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        guard testedParts.count >= 2, currentParts.count >= 2 else { return false }

        if currentParts[0] != testedParts[0] {
            return currentParts[0] > testedParts[0]
        }
        return currentParts[1] - testedParts[1] > 1
    }
}
