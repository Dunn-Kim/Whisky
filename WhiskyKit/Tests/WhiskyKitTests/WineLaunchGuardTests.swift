//
//  WineLaunchGuardTests.swift
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
import Testing
@testable import WhiskyKit

@Suite("Wine launch guard")
@MainActor
struct WineLaunchGuardTests {
    @Test("A bottle in flight refuses a launch with the busy message and prepares nothing")
    func busyBottleRefusesLaunch() async throws {
        let bottle = Bottle(bottleUrl: FileManager.default.temporaryDirectory
            .appending(path: "busy-\(UUID().uuidString)"))
        bottle.inFlight = true
        var prepared = false
        do {
            _ = try await Wine.runProgram(
                at: URL(fileURLWithPath: "/tmp/a.exe"), bottle: bottle, programSettings: nil, onOutput: nil
            ) {
                prepared = true
                return Wine.PreparedLaunch(environment: [:], arguments: [])
            }
            Issue.record("The launch was not refused")
        } catch {
            #expect(error.localizedDescription == String(localized: "bottle.error.busy"))
        }
        #expect(!prepared)
    }
}
