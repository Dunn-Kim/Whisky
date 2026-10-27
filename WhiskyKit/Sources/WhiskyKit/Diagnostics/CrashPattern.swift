//
//  CrashPattern.swift
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

/// Severity level for a crash pattern match.
public enum PatternSeverity: String, Codable, Sendable, Comparable {
    case critical
    case error
    case warning
    case info

    private var sortOrder: Int {
        switch self {
        case .critical: 3
        case .error: 2
        case .warning: 1
        case .info: 0
        }
    }

    public static func < (lhs: PatternSeverity, rhs: PatternSeverity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// A single crash pattern definition loaded from the pattern database.
///
/// Each pattern specifies a regex to match against Wine log lines, with an
/// optional substring prefilter for performance. The prefilter is checked
/// with `String.contains()` before the regex is evaluated.
public struct CrashPattern: Codable, Sendable, Identifiable {
    /// Stable identifier for this pattern.
    public let id: String

    /// Category this pattern belongs to.
    public let category: CrashCategory

    /// Severity when this pattern matches.
    public let severity: PatternSeverity

    /// Confidence score (0...1) when this pattern matches.
    public let confidence: Double

    /// Optional fast-path substring check. If set and the line does not
    /// contain this substring, the regex is skipped entirely.
    public let substringPrefilter: String?

    /// Regular expression pattern string.
    public let regex: String

    /// IDs of remediation actions applicable when this pattern matches.
    public let remediationActionIds: [String]?

    enum CodingKeys: String, CodingKey {
        case id, category, severity, confidence, substringPrefilter
        case regex, remediationActionIds
    }

    public init(
        id: String,
        category: CrashCategory,
        severity: PatternSeverity,
        confidence: Double,
        substringPrefilter: String?,
        regex: String,
        remediationActionIds: [String]?
    ) {
        self.id = id
        self.category = category
        self.severity = severity
        self.confidence = confidence
        self.substringPrefilter = substringPrefilter
        self.regex = regex
        self.remediationActionIds = remediationActionIds
    }

    /// Attempts to match this pattern against a single log line.
    ///
    /// If `substringPrefilter` is set and the line does not contain it,
    /// the regex is not evaluated (fast path). This compiles the regex on every
    /// call that passes the prefilter; ``CrashClassifier`` compiles once and
    /// uses ``match(line:using:)``.
    ///
    /// - Parameter line: A single line of Wine log output.
    /// - Returns: The regex captures if the pattern matched, or `nil`.
    public func match(line: String) -> [String]? {
        guard passesPrefilter(line) else { return nil }
        return match(line: line, using: compiledRegex())
    }

    /// Compiles ``regex``, or `nil` when it is not a valid pattern.
    func compiledRegex() -> Regex<AnyRegexOutput>? {
        try? Regex(regex)
    }

    func passesPrefilter(_ line: String) -> Bool {
        substringPrefilter.map(line.contains) ?? true
    }

    /// Matches `line` with an already compiled `compiled` regex (this pattern's own).
    func match(line: String, using compiled: Regex<AnyRegexOutput>?) -> [String]? {
        guard passesPrefilter(line),
              let compiled,
              let result = try? compiled.firstMatch(in: line)
        else {
            return nil
        }

        // Extract captures (skip the full match at index 0)
        return (1 ..< result.count).compactMap { result[$0].substring.map(String.init) }
    }
}
