// swiftlint:disable file_length
//
//  DiagnosticExporter.swift
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

/// Options controlling what content is included in a diagnostic export.
public struct ExportOptions: Sendable {
    /// Whether to include sensitive details (home paths, secret env values).
    /// Defaults to `false` (redacted by default).
    public var includeSensitiveDetails: Bool

    /// Whether to include the full log file in the ZIP export.
    public var includeFullLog: Bool

    public init(includeSensitiveDetails: Bool = false, includeFullLog: Bool = true) {
        self.includeSensitiveDetails = includeSensitiveDetails
        self.includeFullLog = includeFullLog
    }
}

/// Exports diagnostic data as ZIP archives or Markdown reports.
///
/// All exported content passes through ``Redactor`` by default unless
/// ``ExportOptions/includeSensitiveDetails`` is set to `true`.
/// Follows the ``GPUDetection`` caseless-enum pattern.
///
/// ## Export Formats
///
/// - **ZIP**: Contains `report.md`, `crash.json`, `env.json`, settings files,
///   log files, and `system.json`. Created via `/usr/bin/ditto`.
/// - **Markdown**: A single paste-ready Markdown block for GitHub issues.
///   Always redacted regardless of options.
public enum DiagnosticExporter {
    // MARK: - ZIP Export

    /// Exports a complete diagnostic report as a ZIP archive.
    /// Creates a temporary directory containing all diagnostic files, then
    /// compresses it via `/usr/bin/ditto`. The temporary directory is cleaned
    /// up after compression.
    @MainActor
    public static func exportZIP(
        diagnosis: CrashDiagnosis,
        bottle: Bottle,
        program: Program,
        logFileURL: URL?,
        options: ExportOptions = ExportOptions()
    ) async -> URL {
        let name = "Whisky-Diagnostics-\(sanitizeName(bottle.settings.name))-\(sanitizeName(program.name))"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let contentDir = tempDir.appendingPathComponent(name, isDirectory: true)
        let zipURL = tempDir.appendingPathComponent(
            zipFilename(bottleName: bottle.settings.name, programName: program.name, date: Date())
        )

        let report = generateMarkdownReport(diagnosis: diagnosis, bottle: bottle)
        let files: [(name: String, text: String)] = [
            ("report.md", report),
            ("env.json", generateEnvironmentJSON(bottle: bottle, options: options)),
            ("bottle-settings.json", bottleSettingsSummary(bottle: bottle)),
            ("program-settings.json", programSettingsSummary(program: program, options: options))
        ]
        let systemInfo = await generateSystemInfoJSON()

        await Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
                let crashEncoder = JSONEncoder()
                crashEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                crashEncoder.dateEncodingStrategy = .iso8601
                // Own try?: an encoding failure must not drop the other files.
                try? crashEncoder.encode(CrashDiagnosisCodableWrapper(diagnosis))
                    .write(to: contentDir.appendingPathComponent("crash.json"))
                for (fileName, text) in files {
                    try text.write(to: contentDir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
                }
                writeLogFiles(contentDir: contentDir, logFileURL: logFileURL, options: options)
                try systemInfo.write(
                    to: contentDir.appendingPathComponent("system.json"), atomically: true, encoding: .utf8
                )
            } catch {
                // Best effort
            }
            compressZIP(from: contentDir, to: zipURL)
            try? FileManager.default.removeItem(at: contentDir)
        }.value

        return zipURL
    }

    /// The default file name of a diagnostic ZIP export.
    public static func zipFilename(bottleName: String, programName: String, date: Date) -> String {
        "Whisky-Diagnostics-\(sanitizeName(bottleName))-\(sanitizeName(programName))"
            + "-\(formatDateForFilename(date)).zip"
    }

    // MARK: - Markdown Export

    /// Generates a Markdown diagnostic report suitable for pasting into GitHub issues.
    ///
    /// The report is always redacted (no sensitive details in clipboard copy).
    /// Includes system info, bottle config, diagnosis summary, matched patterns,
    /// suggested remediations, and environment keys (keys only, no values).
    ///
    /// The ZIP export reuses it as `report.md`.
    ///
    /// - Parameters:
    ///   - diagnosis: The crash diagnosis to report.
    ///   - bottle: The bottle that was analyzed.
    /// - Returns: A Markdown string ready for pasting.
    @MainActor
    public static func generateMarkdownReport(diagnosis: CrashDiagnosis, bottle: Bottle) -> String {
        var markdown = "## Whisky Diagnostic Report\n\n"
        markdown += "**Generated:** \(Date().formatted())\n\n"

        markdown += generateSystemInfoSection()
        markdown += generateBottleConfigSection(bottle: bottle)
        markdown += generateDiagnosisSummarySection(diagnosis: diagnosis)
        markdown += generateMatchedPatternsSection(diagnosis: diagnosis)
        markdown += generateSuggestedRemediationsSection(diagnosis: diagnosis)
        markdown += generateEnvironmentKeysSection(bottle: bottle)

        return markdown
    }

    // MARK: - Internal Content Generators

    @MainActor
    private static func generateSystemInfoSection() -> String {
        var section = "### System Info\n\n"
        let version = MacOSVersion.current
        section += "- **macOS:** \(version.description)\n"
        if HostArchitecture.isAppleSilicon {
            section += "- **Architecture:** Apple Silicon (arm64)\n"
        } else {
            section += "- **Architecture:** Intel (x86_64)\n"
        }
        let runtimeInfo = WhiskyWineInstaller.whiskyWineInfo()
        if let whiskyWineVersion = runtimeInfo?.version {
            section += "- **WhiskyWine:** \(whiskyWineVersion.major).\(whiskyWineVersion.minor)"
            section += ".\(whiskyWineVersion.patch)\n"
        }
        if let dxvkVersion = runtimeInfo?.dxvkVersion {
            section += "- **DXVK:** \(dxvkVersion)\n"
        }
        if let dxmtVersion = runtimeInfo?.dxmtVersion {
            section += "- **DXMT:** \(dxmtVersion)\n"
        }
        section += "\n"
        return section
    }

    @MainActor
    private static func generateBottleConfigSection(bottle: Bottle) -> String {
        var section = "### Bottle Config\n\n"
        section += "- **Bottle:** \(bottle.settings.name)\n"
        section += "- **Windows Version:** \(bottle.settings.windowsVersion)\n"
        section += "- **Graphics Backend:** \(bottle.settings.graphicsBackend)\n"
        section += "- **DXVK Async:** \(bottle.settings.dxvkAsync ? "Enabled" : "Disabled")\n"
        section += "- **Enhanced Sync:** \(bottle.settings.enhancedSync)\n"
        section += "\n"
        return section
    }

    @MainActor
    private static func generateDiagnosisSummarySection(diagnosis: CrashDiagnosis) -> String {
        var section = "### Diagnosis Summary\n\n"
        if let headline = diagnosis.headline {
            section += "**\(headline)**\n\n"
        }
        if let category = diagnosis.primaryCategory, let confidence = diagnosis.primaryConfidence {
            section += "- **Primary Category:** \(category.displayName)\n"
            section += "- **Confidence:** \(confidence.displayName)\n"
        }
        if let exitCode = diagnosis.exitCode {
            section += "- **Exit Code:** \(exitCode)\n"
        }
        if !diagnosis.categoryCounts.isEmpty {
            section += "\n**Category Counts:**\n"
            for (category, count) in diagnosis.categoryCounts.sorted(by: { $0.value > $1.value }) {
                section += "- \(category.displayName): \(count)\n"
            }
        }
        section += "\n"
        return section
    }

    @MainActor
    private static func generateMatchedPatternsSection(diagnosis: CrashDiagnosis) -> String {
        guard !diagnosis.matches.isEmpty else { return "" }
        var section = "### Matched Patterns\n\n"
        for diagMatch in diagnosis.matches.prefix(5) {
            let conf = ConfidenceTier(score: diagMatch.pattern.confidence).displayName
            section += "- **\(diagMatch.pattern.id)** [\(diagMatch.pattern.category.displayName)]"
            section += " (\(conf) confidence)\n"
            if !diagMatch.captures.isEmpty {
                section += "  - Captures: \(diagMatch.captures.joined(separator: ", "))\n"
            }
        }
        section += "\n"
        return section
    }

    @MainActor
    private static func generateSuggestedRemediationsSection(diagnosis: CrashDiagnosis) -> String {
        guard !diagnosis.applicableRemediationIds.isEmpty else { return "" }
        let resolved = diagnosis.remediations(from: PatternLoader.defaultRemediations())
        guard !resolved.isEmpty else { return "" }

        var section = "### Suggested Remediations\n\n"
        for action in resolved {
            section += "- **\(action.title)** [\(action.risk) risk]: \(action.whatWillChange)\n"
        }
        section += "\n"
        return section
    }

    @MainActor
    private static func generateEnvironmentKeysSection(bottle: Bottle) -> String {
        var section = "### Environment Keys\n\n"
        let env = Wine.constructWineEnvironment(for: bottle, environment: [:])
        let sortedKeys = env.keys.sorted()
        section += sortedKeys.joined(separator: ", ")
        section += "\n"
        return section
    }

    /// Generates a JSON string with bottle settings summary.
    @MainActor
    static func bottleSettingsSummary(bottle: Bottle) -> String {
        var info: [String: String] = [:]
        info["name"] = bottle.settings.name
        info["windowsVersion"] = "\(bottle.settings.windowsVersion)"
        info["graphicsBackend"] = "\(bottle.settings.graphicsBackend)"
        info["dxvkAsync"] = "\(bottle.settings.dxvkAsync)"
        info["enhancedSync"] = "\(bottle.settings.enhancedSync)"
        info["metalHud"] = "\(bottle.settings.metalHud)"
        info["metalValidation"] = "\(bottle.settings.metalValidation)"
        info["dxrEnabled"] = "\(bottle.settings.dxrEnabled)"
        info["shaderCacheEnabled"] = "\(bottle.settings.shaderCacheEnabled)"
        info["avxEnabled"] = "\(bottle.settings.avxEnabled)"
        info["launcherCompatibilityMode"] = "\(bottle.settings.launcherCompatibilityMode)"

        return dictionaryToJSON(info)
    }

    /// Generates a JSON string with program settings summary.
    ///
    /// Launch arguments are free text the user typed and routinely carry
    /// tokens and passwords, so they get the same scrubbing as a log line
    /// unless sensitive details were asked for.
    @MainActor
    static func programSettingsSummary(program: Program, options: ExportOptions) -> String {
        var info: [String: String] = [:]
        info["name"] = program.name
        info["path"] = Redactor.redactHomePaths(program.url.path(percentEncoded: false))
        info["locale"] = "\(program.settings.locale)"
        info["arguments"] = options.includeSensitiveDetails
            ? program.settings.arguments
            : Redactor.redactLogText(program.settings.arguments)
        info["hasOverrides"] = "\(program.settings.overrides != nil)"

        return dictionaryToJSON(info)
    }

    /// Generates a JSON string with environment variables, redacted as configured.
    @MainActor
    static func generateEnvironmentJSON(bottle: Bottle, options: ExportOptions) -> String {
        let env = Wine.constructWineEnvironment(for: bottle, environment: [:])
        let redacted = Redactor.redactEnvironment(env, includeSensitive: options.includeSensitiveDetails)
        return dictionaryToJSON(redacted)
    }

    /// Generates a JSON string with system information.
    static func generateSystemInfoJSON() async -> String {
        var info: [String: String] = [:]
        let version = MacOSVersion.current
        info["macOS"] = version.description
        info["architecture"] = HostArchitecture.isAppleSilicon ? "arm64" : "x86_64"

        if let whiskyWineVersion = WhiskyWineInstaller.whiskyWineVersion() {
            info["whiskyWineVersion"] =
                "\(whiskyWineVersion.major).\(whiskyWineVersion.minor).\(whiskyWineVersion.patch)"
        }

        return dictionaryToJSON(info)
    }
}

// MARK: - DiagnosticExporter ZIP Building

extension DiagnosticExporter {
    fileprivate static func writeLogFiles(contentDir: URL, logFileURL: URL?, options: ExportOptions) {
        guard let logURL = logFileURL else { return }

        if options.includeFullLog,
           FileManager.default.fileExists(atPath: logURL.path(percentEncoded: false)) {
            if let logContent = try? String(contentsOf: logURL, encoding: .utf8) {
                let redacted = options.includeSensitiveDetails ? logContent
                    : Redactor.redactLogText(logContent)
                try? redacted.write(
                    to: contentDir.appendingPathComponent("wine.log"),
                    atomically: true,
                    encoding: .utf8
                )
            }
        }

        let tailText = StabilityDiagnostics.tailOfLogFile(
            logURL, lineCount: 500, maxBytes: 256 * 1_024
        )
        let redactedTail = options.includeSensitiveDetails ? tailText
            : Redactor.redactLogText(tailText)
        try? redactedTail.write(
            to: contentDir.appendingPathComponent("wine.tail.log"),
            atomically: true,
            encoding: .utf8
        )
    }

    fileprivate static func compressZIP(from contentDir: URL, to zipURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c",
            "-k",
            "--norsrc",
            contentDir.path(percentEncoded: false),
            zipURL.path(percentEncoded: false)
        ]
        try? process.run()
        process.waitUntilExit()
    }
}

// MARK: - DiagnosticExporter Helpers

extension DiagnosticExporter {
    /// Sanitizes a name for use in filenames by replacing non-alphanumeric characters with hyphens.
    public static func sanitizeName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return name.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }
            .joined()
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Formats a date for use in filenames: YYYYMMDD-HHmmss.
    public static func formatDateForFilename(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// Converts a [String: String] dictionary to a pretty-printed JSON string.
    fileprivate static func dictionaryToJSON(_ dict: [String: String]) -> String {
        let data = try? JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

// MARK: - Codable Wrapper for CrashDiagnosis

/// Lightweight Codable wrapper for ``CrashDiagnosis`` to encode as JSON.
///
/// ``CrashDiagnosis`` itself contains non-Codable ``DiagnosisMatch`` entries,
/// so this wrapper encodes only the serializable portions.
struct CrashDiagnosisCodableWrapper: Codable {
    let primaryCategory: String?
    let primaryConfidence: String?
    let headline: String?
    let exitCode: Int32?
    let categoryCounts: [String: Int]
    let matchCount: Int
    let applicableRemediationIds: [String]
    let topMatches: [MatchSummary]

    struct MatchSummary: Codable {
        let patternId: String
        let category: String
        let confidence: Double
        let severity: String
        let lineIndex: Int
        let captures: [String]
    }

    init(_ diagnosis: CrashDiagnosis) {
        self.primaryCategory = diagnosis.primaryCategory?.rawValue
        self.primaryConfidence = diagnosis.primaryConfidence?.rawValue
        self.headline = diagnosis.headline
        self.exitCode = diagnosis.exitCode
        self.categoryCounts = Dictionary(
            uniqueKeysWithValues: diagnosis.categoryCounts.map { ($0.key.rawValue, $0.value) }
        )
        self.matchCount = diagnosis.matches.count
        self.applicableRemediationIds = diagnosis.applicableRemediationIds
        self.topMatches = diagnosis.matches.prefix(20).map { diagMatch in
            MatchSummary(
                patternId: diagMatch.pattern.id,
                category: diagMatch.pattern.category.rawValue,
                confidence: diagMatch.pattern.confidence,
                severity: diagMatch.pattern.severity.rawValue,
                lineIndex: diagMatch.lineIndex,
                captures: diagMatch.captures
            )
        }
    }
}

// swiftlint:enable file_length
