//
//  CheckRegistry.swift
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

/// Maps stable check ID strings to ``TroubleshootingCheck`` implementations.
///
/// The registry decouples flow definition JSON (which references check IDs)
/// from the concrete check implementations. Each check wraps an existing
/// diagnostic primitive and returns a normalized ``CheckResult``.
///
/// ## Usage
///
/// ```swift
/// let registry = CheckRegistry()  // All built-in checks pre-registered
/// let result = await registry.run(
///     checkId: "setting.value_check",
///     params: ["setting": "graphicsBackend", "expected": "dxvk"],
///     context: checkContext
/// )
/// ```
public final class CheckRegistry: Sendable {
    /// Every built-in check implementation.
    ///
    /// Each check wraps an existing diagnostic primitive and returns a
    /// normalized ``CheckResult``. Check IDs are stable and match the
    /// references in flow definition JSON files.
    public static let builtIn: [any TroubleshootingCheck] = [
        // Crash diagnostics
        CrashLogCheck(),

        // Audio diagnostics
        AudioDriverCheck(),
        AudioDeviceCheck(),

        // Dependency and winetricks
        DependencyCheck(),
        WinetricksVerbCheck(),

        // Launcher and process
        LauncherTypeCheck(),
        ProcessRunningCheck(),

        // Registry
        RegistryValueCheck(),

        // Game config, settings, and diagnostics
        GameConfigAvailableCheck(),
        SettingValueCheck(),
        DiagnosticsEnhanceCheck()
    ]

    private let checks: [String: any TroubleshootingCheck]

    private let logger = Logger(
        subsystem: "com.franke.Whisky",
        category: "CheckRegistry"
    )

    // MARK: - Init

    /// Creates a check registry from `checks`, all built-in checks by default.
    ///
    /// If two checks share a ``TroubleshootingCheck/checkId``, the later one
    /// wins.
    public init(checks: [any TroubleshootingCheck] = builtIn) {
        self.checks = Dictionary(checks.map { ($0.checkId, $0) }, uniquingKeysWith: { _, later in later })
    }

    // MARK: - Execution

    /// Runs the check identified by `checkId` with the given parameters and context.
    ///
    /// If the check ID is not registered, returns an error result with a descriptive
    /// summary. This ensures the flow engine always receives a valid result for branching.
    ///
    /// - Parameters:
    ///   - checkId: The stable identifier of the check to run.
    ///   - params: Key-value parameters from the flow step node.
    ///   - context: The check context with bottle, program, and preflight data.
    /// - Returns: The check result for flow branching.
    public func run(
        checkId: String,
        params: [String: String],
        context: CheckContext
    ) async -> CheckResult {
        guard let check = checks[checkId] else {
            logger.error("Unknown check ID: \(checkId)")
            return .error("Check not found: \(checkId)", evidence: ["error": "Unknown checkId: \(checkId)"])
        }

        logger.debug("Running check: \(checkId)")
        return await check.run(params: params, context: context)
    }
}
