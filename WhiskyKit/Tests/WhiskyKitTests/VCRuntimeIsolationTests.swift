//
//  VCRuntimeIsolationTests.swift
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

@Suite("VC++ runtime isolation")
@MainActor
final class VCRuntimeIsolationTests {
    private let root: URL
    private let prefix: URL
    private let libWine: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "VCRuntimeIsolationTests-\(UUID().uuidString)")
        prefix = root.appending(path: "Bottle")
        libWine = root.appending(path: "lib/wine")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Fixtures

    /// A PE header with the given machine at `e_lfanew` 0x80 and a native DOS stub at 0x40.
    private func native(_ machine: UInt16, tag: String = "native") -> Data {
        var data = Data("MZ".utf8) + Data(count: 0x3E)
        data.replaceSubrange(0x3C ..< 0x40, with: [0x80, 0, 0, 0])
        data += Data("This program cannot be run in DOS mode.".utf8)
        data += Data(count: 0x80 - data.count)
        data += Data([0x50, 0x45, 0, 0, UInt8(machine & 0xFF), UInt8(machine >> 8)])
        return data + Data(tag.utf8)
    }

    private var wineMarked: Data {
        Data("MZ".utf8) + Data(count: 0x3E) + Data("Wine builtin DLL".utf8) + Data(count: 16)
    }

    private func write(_ data: Data, _ path: String, in base: URL? = nil) throws {
        let url = (base ?? prefix).appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func read(_ path: String) throws -> Data {
        try Data(contentsOf: prefix.appending(path: path))
    }

    private func builtins() throws {
        for name in ["ucrtbase", "msvcp140", "vcruntime140", "concrt140"] {
            try write(wineMarked + Data("a64".utf8), "aarch64-windows/\(name).dll", in: libWine)
            try write(wineMarked + Data("i386".utf8), "i386-windows/\(name).dll", in: libWine)
        }
    }

    // MARK: - isolate

    @Test("Native files move to the store by machine and the builtins go back")
    func isolatesNativeFiles() throws {
        try builtins()
        try write(native(0x8664), "drive_c/windows/system32/ucrtbase.dll")
        try write(native(0x14C), "drive_c/windows/syswow64/msvcp140.dll")
        try write(native(0xAA64), "drive_c/windows/system32/vcruntime140.dll")
        try write(wineMarked, "drive_c/windows/system32/concrt140.dll")
        // Native, but the runtime has no builtin of this name.
        try write(native(0x8664), "drive_c/windows/system32/atl140.dll")

        let moved = VCRuntimeIsolation.isolate(prefix: prefix, runtimeLibWine: libWine)

        #expect(Set(moved.map(\.name)) == ["ucrtbase", "msvcp140", "vcruntime140"])
        #expect(try read("VC Runtime/x64/ucrtbase.dll") == native(0x8664))
        #expect(try read("VC Runtime/x86/msvcp140.dll") == native(0x14C))
        #expect(try read("VC Runtime/arm64/vcruntime140.dll") == native(0xAA64))
        #expect(try read("drive_c/windows/system32/ucrtbase.dll") == wineMarked + Data("a64".utf8))
        #expect(try read("drive_c/windows/syswow64/msvcp140.dll") == wineMarked + Data("i386".utf8))
        #expect(try read("drive_c/windows/system32/concrt140.dll") == wineMarked)
        #expect(try read("drive_c/windows/system32/atl140.dll") == native(0x8664))

        #expect(VCRuntimeIsolation.isolate(prefix: prefix, runtimeLibWine: libWine).isEmpty)
    }

    @Test("A newer native copy replaces an older one in the store")
    func overwritesOlderStoreCopy() throws {
        try builtins()
        try write(native(0x8664, tag: "old"), "VC Runtime/x64/msvcp140.dll")
        try write(native(0x8664, tag: "new"), "drive_c/windows/system32/msvcp140.dll")

        VCRuntimeIsolation.isolate(prefix: prefix, runtimeLibWine: libWine)

        #expect(try read("VC Runtime/x64/msvcp140.dll") == native(0x8664, tag: "new"))
    }

    @Test("A native file goes back when the builtin cannot be copied in")
    func rollsBackWhenBuiltinCopyFails() throws {
        try builtins()
        try write(native(0x8664), "drive_c/windows/system32/ucrtbase.dll")
        // Present, so the file is a candidate, but unreadable, so the copy fails.
        let builtin = libWine.appending(path: "aarch64-windows/ucrtbase.dll")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: builtin.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: builtin.path) }

        let moved = VCRuntimeIsolation.isolate(prefix: prefix, runtimeLibWine: libWine)

        #expect(moved.isEmpty)
        #expect(try read("drive_c/windows/system32/ucrtbase.dll") == native(0x8664))
        #expect(!FileManager.default.fileExists(atPath: prefix.appending(path: "VC Runtime/x64/ucrtbase.dll").path))
    }

    // MARK: - placeForUnity

    private func game(machine: UInt16, unity: Bool = true) throws -> URL {
        let folder = root.appending(path: "Game")
        try write(native(machine), "Game.exe", in: folder)
        if unity {
            try write(Data("unity".utf8), "UnityPlayer.dll", in: folder)
        }
        return folder.appending(path: "Game.exe")
    }

    private func populateStore() throws {
        for machine in ["x64", "x86"] {
            for name in ["msvcp140", "vcruntime140", "ucrtbase"] {
                try write(native(machine == "x64" ? 0x8664 : 0x14C), "VC Runtime/\(machine)/\(name).dll")
            }
        }
    }

    @Test("Only a Unity game gets the DLLs, by its own architecture, never the UCRT")
    func placesForUnity() throws {
        try populateStore()
        let store = VCRuntimeIsolation.store(prefix: prefix)

        let plain = try game(machine: 0x8664, unity: false)
        #expect(VCRuntimeIsolation.placeForUnity(executable: plain, store: store).isEmpty)
        let leftover = plain.deletingLastPathComponent().appending(path: "msvcp140.dll")
        #expect(!FileManager.default.fileExists(atPath: leftover.path))

        try FileManager.default.removeItem(at: root.appending(path: "Game"))
        let x64 = try game(machine: 0x8664)
        let names = VCRuntimeIsolation.placeForUnity(executable: x64, store: store)
        #expect(Set(names) == ["msvcp140", "vcruntime140"])
        let folder = x64.deletingLastPathComponent()
        #expect(try Data(contentsOf: folder.appending(path: "msvcp140.dll")) == native(0x8664))
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "ucrtbase.dll").path))

        try FileManager.default.removeItem(at: root.appending(path: "Game"))
        let x86 = try game(machine: 0x14C)
        _ = VCRuntimeIsolation.placeForUnity(executable: x86, store: store)
        #expect(try Data(contentsOf: x86.deletingLastPathComponent().appending(path: "msvcp140.dll")) == native(0x14C))
    }

    @Test("A file the game ships is never overwritten")
    func keepsGameFiles() throws {
        try populateStore()
        let exe = try game(machine: 0x8664)
        let own = native(0x8664, tag: "game")
        try write(own, "msvcp140.dll", in: exe.deletingLastPathComponent())

        _ = VCRuntimeIsolation.placeForUnity(executable: exe, store: VCRuntimeIsolation.store(prefix: prefix))

        #expect(try Data(contentsOf: exe.deletingLastPathComponent().appending(path: "msvcp140.dll")) == own)
    }

    // MARK: - Detector

    @Test("A store-only install counts as installed")
    func detectorCountsStore() throws {
        #expect(!VCRedistDetector.isInstalled(prefixURL: prefix))
        try write(native(0x8664), "VC Runtime/x64/msvcp140.dll")
        #expect(!VCRedistDetector.isInstalled(prefixURL: prefix))
        try write(native(0x8664), "VC Runtime/x64/vcruntime140.dll")
        #expect(VCRedistDetector.isInstalled(prefixURL: prefix))
    }

    // MARK: - Registry

    @Test("Stale native overrides are deleted, a user's own entry is kept")
    func staleOverrides() {
        let values = [
            "*ucrtbase": "\"native,builtin\"", "msvcp140": "\"native,builtin\"",
            "*vcruntime140": "\"builtin\"", "dxgi": "\"native\"", "*concrt140": "\"native,builtin\""
        ]
        let stale = VCRuntimeIsolation.staleOverrides(in: values, keeping: ["concrt140"])
        #expect(stale == ["*ucrtbase", "msvcp140"])

        let doc = Wine.registryDocument(
            for: [(key: Wine.DLLOverrideScope.bottle.registryKey, overrides: ["msvcp140": "n,b"])],
            staleNativeNames: stale
        )
        #expect(doc.contains("\"*ucrtbase\"=-"))
        #expect(!doc.contains("\"msvcp140\"=-"))
        #expect(doc.contains("\"msvcp140\"=\"n,b\""))
        let program = Wine.registryDocument(
            for: [(key: Wine.DLLOverrideScope.program("a.exe").registryKey, overrides: [:])], staleNativeNames: stale
        )
        #expect(!program.contains("ucrtbase"))
    }

    // MARK: - Launch

    private final class Recorder: @unchecked Sendable {
        var scopes: [(scope: Wine.DLLOverrideScope, overrides: String)] = []
    }

    private func launchOverrides(of exe: URL, bottle: Bottle) async throws -> String? {
        let recorder = Recorder()
        _ = try await Wine.prepareProgramLaunch(
            at: exe, bottle: bottle,
            overrideWriter: { _, scopes in recorder.scopes = scopes }, importer: { _, _ in }
        )
        return recorder.scopes.first { $0.scope == .program(exe.lastPathComponent) }?.overrides
    }

    @Test("A Unity launch loads the placed DLLs natively, a plain one does not")
    func launchOverrides() async throws {
        try populateStore()
        try FileManager.default.createDirectory(
            at: prefix.appending(path: "drive_c/windows/system32"), withIntermediateDirectories: true
        )
        let bottle = Bottle(bottleUrl: prefix)
        let unity = try game(machine: 0x8664)
        let overrides = try #require(try await launchOverrides(of: unity, bottle: bottle))
        #expect(overrides.contains("msvcp140=n,b"))
        #expect(overrides.contains("vcruntime140=n,b"))
        #expect(!overrides.contains("ucrtbase"))

        try FileManager.default.removeItem(at: unity.deletingLastPathComponent().appending(path: "UnityPlayer.dll"))
        try FileManager.default.removeItem(at: unity.deletingLastPathComponent().appending(path: "msvcp140.dll"))
        try FileManager.default.removeItem(at: unity.deletingLastPathComponent().appending(path: "vcruntime140.dll"))
        let plain = try await launchOverrides(of: unity, bottle: bottle)
        #expect(plain?.contains("msvcp140") != true)
    }
}
