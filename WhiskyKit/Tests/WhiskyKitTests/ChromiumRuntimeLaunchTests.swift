//
//  ChromiumRuntimeLaunchTests.swift
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

/// Steering of an Electron app found by its files (#372): a program carries the
/// steering it was scanned with, and the preflight reports it as the reason.
@Suite("Chromium runtime steering")
@MainActor
final class ChromiumRuntimeLaunchTests {
    let tempRoot: URL
    let bottleURL: URL
    let appFolder: URL

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "chromium_runtime_launch_\(UUID().uuidString)")
        bottleURL = tempRoot.appending(path: "Bottle")
        let driveC = bottleURL.appending(path: "drive_c")
        appFolder = driveC.appending(path: "Program Files/Chat")
        try touch(["resources/app.asar", "icudtl.dat", "v8_context_snapshot.bin", "ffmpeg.dll"], in: appFolder)
        try ChromiumRuntimeDetectorTests.electron45.write(to: appFolder.appending(path: "Chat.exe"))
    }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func touch(_ paths: [String], in base: URL) throws {
        for relative in paths {
            let url = base.appending(path: relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("MZ".utf8).write(to: url)
        }
    }

    func makeBottle(_ backend: GraphicsBackend = .recommended) -> Bottle {
        let bottle = Bottle(bottleUrl: bottleURL)
        bottle.settings.graphicsBackend = backend
        return bottle
    }

    @Test("A program carries the steering it was scanned with, and falls back to its name")
    func programSteering() {
        let bottle = makeBottle()
        let chat = appFolder.appending(path: "Chat.exe")
        let scanned = Program(
            url: chat, bottle: bottle, peFile: nil, backendSteering: BackendSteering.inspect(executable: chat)
        )
        #expect(scanned.backendSteering == .chromiumRuntime(kind: .electron, evidence: "resources/app.asar"))
        #expect(Program(url: chat, bottle: bottle, peFile: nil).backendSteering == nil, "name only, no read")

        let steam = bottleURL.appending(path: "drive_c/Program Files (x86)/Steam/steam.exe")
        #expect(Program(url: steam, bottle: bottle, peFile: nil).backendSteering == .launcher(.steam))
    }

    @Test("The preflight reports the Electron steering as the reason")
    func preflightReason() {
        let backends = PreflightCollector.resolvedBackends(
            bottle: .recommended, programOverride: nil, programURL: appFolder.appending(path: "Chat.exe")
        )
        #expect(backends.effective == .wined3d)
        #expect(backends.bottle == .dxmt)
        #expect(backends.reason == .steered(.chromiumRuntime(kind: .electron, evidence: "resources/app.asar")))
    }

    @Test("An Electron app is steered to WineD3D whatever the bottle's own backend is")
    func steeredResolution() {
        let steering = BackendSteering.inspect(executable: appFolder.appending(path: "Chat.exe"))
        #expect(GraphicsBackendResolver.resolution(for: steering).backend == .wined3d)
    }
}
