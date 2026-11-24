//
//  CompatdbRulesTests.swift
//  WhiskyKitTests
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

/// The `WINE_COMPATDB` rules that carry the graphics backend choice to the runtime.
@Suite("WINE_COMPATDB rules")
struct CompatdbRulesTests {
    private let wined3d = "dxgi=wined3d;d3d9=wined3d"
    private let frontEnd = "exe=3DMark.exe;dxgi=wined3d;d3d9=wined3d"

    private func rules(
        bottle: GraphicsBackend = .recommended, steered: [String] = [],
        programs: [(executable: String, backend: GraphicsBackend)] = [], user: String? = nil
    ) -> [String] {
        Wine.compatdbRules(
            bottleBackend: bottle, steeredExecutables: steered, programBackends: programs, userRules: user
        )?.components(separatedBy: "\n") ?? []
    }

    @Test("An untouched bottle emits only the Chromium front ends of the table")
    func untouchedBottle() {
        #expect(rules() == [frontEnd])
    }

    @Test("An explicit bottle backend is an exe=* rule; Recommended adds none")
    func bottleWide() {
        #expect(rules(bottle: .dxmt) == ["exe=*;dxgi=dxmt", frontEnd])
        #expect(rules(bottle: .wined3d) == ["exe=*;\(wined3d)", frontEnd])
    }

    @Test("Steered executables run on WineD3D by name, once each however the case")
    func steered() {
        let lines = rules(steered: ["RSI Launcher.exe", "steamwebhelper.exe", "STEAMWEBHELPER.EXE"])
        #expect(lines == [frontEnd, "exe=RSI Launcher.exe;\(wined3d)", "exe=STEAMWEBHELPER.EXE;\(wined3d)"])
    }

    @Test("A program's own backend beats steering and the bottle's")
    func programOverrideWins() {
        let lines = rules(
            bottle: .wined3d, steered: ["Chat.exe"],
            programs: [("chat.exe", .dxmt), ("Game.exe", .dxmt)]
        )
        #expect(lines == ["exe=*;\(wined3d)", frontEnd, "exe=chat.exe;dxgi=dxmt", "exe=Game.exe;dxgi=dxmt"])
    }

    @Test("A program set to Recommended means the recommended backend under an explicit bottle backend")
    func programRecommended() {
        let programs: [(executable: String, backend: GraphicsBackend)] = [
            ("Game.exe", .recommended), ("Chat.exe", .recommended)
        ]
        #expect(rules(programs: programs) == [frontEnd])
        #expect(
            rules(bottle: .wined3d, steered: ["Chat.exe"], programs: programs)
                == ["exe=*;\(wined3d)", frontEnd, "exe=Chat.exe;\(wined3d)", "exe=Game.exe;dxgi=dxmt"]
        )
    }

    @Test("Names are escaped so a rule stays one line of fields")
    func escaping() {
        let lines = rules(programs: [("a%b;c=d\ne\rf.exe", .dxmt)])
        #expect(lines.last == "exe=a%25b%3Bc%3Dd%0Ae%0Df.exe;dxgi=dxmt")
        #expect(rules(programs: [("My Game.exe", .dxmt)]).last == "exe=My Game.exe;dxgi=dxmt")
    }

    @Test("Rules a user or a GameDB profile set stay, after the app's")
    func userRulesKept() {
        #expect(rules(user: "exe=x.exe;dxgi=default") == [frontEnd, "exe=x.exe;dxgi=default"])
    }

    @Test("The launch environment carries the value, and keeps what the caller set")
    @MainActor
    func environment() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "compatdb_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bottle = Bottle(bottleUrl: root)
        bottle.settings.graphicsBackend = .wined3d

        let plain = Wine.constructWineEnvironment(for: bottle, recommendedBackend: .dxmt)
        #expect(plain["WINE_COMPATDB"] == "exe=*;\(wined3d)\n\(frontEnd)")

        let withUser = Wine.constructWineEnvironment(
            for: bottle, environment: ["WINE_COMPATDB": "exe=x.exe;dxgi=default"],
            recommendedBackend: .dxmt, programBackends: [("Game.exe", .dxmt)]
        )
        #expect(
            withUser["WINE_COMPATDB"]
                == "exe=*;\(wined3d)\n\(frontEnd)\nexe=Game.exe;dxgi=dxmt\nexe=x.exe;dxgi=default"
        )
    }
}
