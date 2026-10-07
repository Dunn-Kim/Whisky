//
//  DiagnosticsEnhanceCheck.swift
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

/// Checks whether enhanced diagnostics (WINEDEBUG preset) can provide additional info.
///
/// Reads the WINEDEBUG preset persisted in the troubleshot program's settings,
/// which is where the launch path takes it from. Returns `.alreadyConfigured`
/// if a debug preset is already active, `.pass` if enhanced diagnostics would
/// add value (no program, or the default/normal preset), or `.error` if the
/// bottle settings cannot be read.
public struct DiagnosticsEnhanceCheck: TroubleshootingCheck {
    public let checkId = "diagnostics.can_enhance"

    public init() {}

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        let metadataURL = context.bottleURL.appending(path: "Metadata.plist")
        do {
            _ = try BottleSettings.decode(from: metadataURL)
        } catch {
            return .error("Failed to read bottle settings", evidence: ["error": error.localizedDescription])
        }

        // Check if a non-default WINEDEBUG preset is active, as the launch path
        // applies it: any preset but normal.
        let preset = context.programURL.flatMap {
            Program.persistedSettings(for: $0, bottleURL: context.bottleURL)?.activeWineDebugPreset
        }
        if let preset, preset != .normal {
            return CheckResult(
                outcome: .alreadyConfigured,
                evidence: [
                    "currentPreset": preset.displayName,
                    "winedebug": preset.winedebugValue
                ],
                summary: "Enhanced diagnostics already active: \(preset.displayName)",
                confidence: .high
            )
        }

        // Default or normal preset -- enhanced diagnostics can help
        let suggestedPreset = params["preset"] ?? "crash"
        return CheckResult(
            outcome: .pass,
            evidence: [
                "currentPreset": "normal",
                "suggestedPreset": suggestedPreset
            ],
            summary: "Enhanced diagnostics available for more detailed logging",
            confidence: .medium
        )
    }
}
