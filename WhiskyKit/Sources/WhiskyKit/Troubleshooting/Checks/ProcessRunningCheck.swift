//
//  ProcessRunningCheck.swift
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

/// Checks whether Wine is running for the current bottle.
///
/// Probes the bottle's wineserver (`wineserver -k0`), which is up for as long
/// as any Wine process in the prefix is. Returns `.pass` if it is running and
/// `.fail` if not. Uses `params["process"]` as an optional name for reporting
/// purposes.
public struct ProcessRunningCheck: TroubleshootingCheck {
    public let checkId = "process.running_check"

    public func run(params: [String: String], context: CheckContext) async -> CheckResult {
        let processName = params["process"] ?? "wineserver"
        let running = await Wine.isWineserverRunning(at: context.bottleURL)
        let evidence = [
            "process": processName,
            "running": "\(running)"
        ]

        if running {
            return CheckResult(
                outcome: .pass,
                evidence: evidence,
                summary: "Wine is running for this bottle",
                confidence: .high
            )
        }

        return CheckResult(
            outcome: .fail,
            evidence: evidence,
            summary: "No Wine processes running for this bottle",
            confidence: .high
        )
    }
}
