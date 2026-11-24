//
//  SteamLauncher+AppLaunch.swift
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

extension SteamLauncher {
    /// A game's launch plan: the GameDB variant the user applied to the
    /// bottle, or the recommended one, under the user's own overrides for
    /// the game's executables.
    ///
    /// - Parameters:
    ///   - appId: The game's Steam App ID.
    ///   - scan: The scan of the game's install folder, when it is known.
    ///   - bottle: The bottle the game is in.
    /// - Returns: The plan a launch of the game carries.
    @MainActor
    static func launchPlan(appId: Int, scan: SteamExecutableScan?, bottle: Bottle) -> LaunchPlan {
        LaunchResolver.plan(
            steamAppId: appId,
            userOverrides: scan.flatMap { userOverrides(forExecutables: $0.planExecutables, bottle: bottle) },
            appliedConfiguration: GameConfigSnapshot.load(from: bottle.url)
        )
    }

    /// What `steam.exe -applaunch` is started with for a game.
    ///
    /// The plan is the game's; `steam.exe` is only the vehicle. It goes into
    /// the game executables' own entries, so it reaches the game whichever
    /// process starts it.
    ///
    /// - Parameters:
    ///   - appId: The game's Steam App ID.
    ///   - scan: The scan of the game's install folder, when it is known.
    ///   - plan: The game's launch plan.
    /// - Returns: The request ``Wine`` prepares and runs the invocation from.
    static func appLaunchRequest(appId: Int, scan: SteamExecutableScan?, plan: LaunchPlan) -> Wine
        .ProgramLaunchRequest {
        Wine.ProgramLaunchRequest(
            args: ["-applaunch", String(appId)] + plan.launchArguments,
            environment: [:],
            programOverrides: plan.overrides,
            programSettings: nil,
            gameProfileEnvironment: plan.gameProfileEnvironment,
            overridesApplyToDescendants: true,
            descendantExecutables: gameExecutables(scanned: scan?.planExecutables ?? [], plan: plan),
            ownSettingsExecutables: scan?.ownSettingsExecutables ?? [],
            descendantLaunchers: plan.startsLaunchers
        )
    }
}
