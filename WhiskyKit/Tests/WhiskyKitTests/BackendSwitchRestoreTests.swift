//
//  BackendSwitchRestoreTests.swift
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

@testable import WhiskyKit
import XCTest

/// Switching a bottle's graphics backend must not leave the previous backend's
/// native DLLs in the prefix. DXVK ships no `dxgi`, so a bottle moved from DXMT
/// to DXVK used to keep DXMT's native `dxgi.dll` and load it under DXVK's
/// `dxgi=n,b` override.
final class BackendSwitchRestoreTests: XCTestCase {
    private var root: URL!

    private var prefix: URL { root.appending(path: "prefix") }
    private var wineLib: URL { root.appending(path: "wine").appending(path: "lib") }
    private var windows: URL {
        prefix.appending(path: "drive_c").appending(path: "windows")
    }

    private var system32: URL { windows.appending(path: "system32") }
    private var syswow64: URL { windows.appending(path: "syswow64") }

    override func setUpWithError() throws {
        root = URL(filePath: NSTemporaryDirectory())
            .appending(path: "whisky-restore-\(UUID().uuidString)")
        let builtin64 = wineLib.appending(path: "wine").appending(path: "x86_64-windows")
        let builtin32 = wineLib.appending(path: "wine").appending(path: "i386-windows")
        for dir in [system32, syswow64, builtin64, builtin32] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        for name in ["d3d11.dll", "dxgi.dll", "d3d10core.dll"] {
            try Data("builtin-\(name)".utf8).write(to: builtin64.appending(path: name))
            try Data("builtin32-\(name)".utf8).write(to: builtin32.appending(path: name))
            try Data("stale-\(name)".utf8).write(to: system32.appending(path: name))
            try Data("stale-\(name)".utf8).write(to: syswow64.appending(path: name))
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func contents(_ url: URL) throws -> String {
        try String(decoding: Data(contentsOf: url), as: UTF8.self)
    }

    func testStaleDLLFromPreviousBackendIsRestoredToBuiltin() throws {
        // DXVK installs d3d11 and d3d10core, but no dxgi.
        try Wine.restoreUnmanagedTranslationDLLs(
            prefixRoot: prefix, wineLibRoot: wineLib, keeping: ["d3d11.dll", "d3d10core.dll"]
        )
        XCTAssertEqual(try contents(system32.appending(path: "dxgi.dll")), "builtin-dxgi.dll")
        XCTAssertEqual(try contents(syswow64.appending(path: "dxgi.dll")), "builtin32-dxgi.dll")
    }

    func testFilesTheBackendInstallsAreLeftAlone() throws {
        try Wine.restoreUnmanagedTranslationDLLs(
            prefixRoot: prefix, wineLibRoot: wineLib, keeping: ["d3d11.dll", "d3d10core.dll"]
        )
        XCTAssertEqual(try contents(system32.appending(path: "d3d11.dll")), "stale-d3d11.dll")
        XCTAssertEqual(try contents(system32.appending(path: "d3d10core.dll")), "stale-d3d10core.dll")
    }

    /// A backend that installs nothing (D3DMetal, WineD3D) has to clear the whole set.
    func testBackendWithNoPayloadRestoresEverything() throws {
        try Wine.restoreUnmanagedTranslationDLLs(prefixRoot: prefix, wineLibRoot: wineLib, keeping: [])
        for name in ["d3d11.dll", "dxgi.dll", "d3d10core.dll"] {
            XCTAssertEqual(try contents(system32.appending(path: name)), "builtin-\(name)")
        }
    }

    /// A runtime that ships no builtin for a name must not delete what it cannot put back.
    func testMissingBuiltinLeavesPrefixUntouched() throws {
        try Data("stale-winemetal.dll".utf8).write(to: system32.appending(path: "winemetal.dll"))
        try Wine.restoreUnmanagedTranslationDLLs(prefixRoot: prefix, wineLibRoot: wineLib, keeping: [])
        XCTAssertEqual(try contents(system32.appending(path: "winemetal.dll")), "stale-winemetal.dll")
    }

    func testBackendsWithoutPayloadReportNoManagedFiles() {
        XCTAssertTrue(Wine.prefixDLLNames(installedBy: .d3dMetal).isEmpty)
        XCTAssertTrue(Wine.prefixDLLNames(installedBy: .wined3d).isEmpty)
        XCTAssertEqual(Wine.prefixDLLNames(installedBy: .dxmt), Set(Wine.dxmtPrefixDLLs))
    }

    // MARK: - GPTK payload deployed, DXVK launch

    private let dxvkManaged: Set<String> = ["d3d11.dll", "d3d10core.dll"]
    private var originalDXGI: URL { root.appending(path: "store/originals/dxgi.dll") }
    private var system32DXGI: URL { system32.appending(path: "dxgi.dll") }

    /// A PE stub carrying winebuild's "Wine builtin DLL" signature at 0x40.
    private func builtinFake(_ tag: String) -> Data {
        Data(count: 0x40) + Data("Wine builtin DLL".utf8) + Data(tag.utf8)
    }

    /// The file contents outside the 16-byte marker window at 0x40.
    private func strippedTail(_ url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        return data.subdata(in: 0 ..< 0x40) + data.subdata(in: 0x50 ..< data.count)
    }

    private func writeOriginal() throws {
        try FileManager.default.createDirectory(
            at: originalDXGI.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try builtinFake("stored-original").write(to: originalDXGI)
    }

    private func restoreForGPTKDXVK() throws {
        try Wine.restoreUnmanagedTranslationDLLs(
            prefixRoot: prefix, wineLibRoot: wineLib, keeping: dxvkManaged, nativeDXGI: originalDXGI
        )
    }

    /// With the payload deployed the 64-bit builtin is Apple's forwarder, so
    /// system32 gets the stored original, marker-stripped. GPTK forwards only
    /// the 64-bit builtins, so syswow64 keeps Wine's own.
    func testGPTKDXVKLaunchInstallsStrippedOriginalInSystem32() throws {
        try writeOriginal()
        try restoreForGPTKDXVK()
        XCTAssertTrue(try Wine.isNativePE(system32DXGI))
        XCTAssertEqual(try strippedTail(system32DXGI), try strippedTail(originalDXGI))
        XCTAssertEqual(try contents(syswow64.appending(path: "dxgi.dll")), "builtin32-dxgi.dll")
    }

    /// No stored original means nothing better than the builtin to put back.
    func testGPTKDXVKLaunchWithoutStoredOriginalRestoresBuiltin() throws {
        try restoreForGPTKDXVK()
        XCTAssertEqual(try contents(system32DXGI), "builtin-dxgi.dll")
    }

    /// The restore runs on every DXVK launch, so a prefix already holding the
    /// stripped original must not be copied and patched again.
    func testStrippedOriginalIsNotRewritten() throws {
        try writeOriginal()
        try restoreForGPTKDXVK()
        let past = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: past], ofItemAtPath: system32DXGI.path(percentEncoded: false)
        )
        let before = try FileManager.default.attributesOfItem(atPath: system32DXGI.path(percentEncoded: false))

        try restoreForGPTKDXVK()

        let after = try FileManager.default.attributesOfItem(atPath: system32DXGI.path(percentEncoded: false))
        XCTAssertEqual(after[.systemFileNumber] as? Int, before[.systemFileNumber] as? Int)
        XCTAssertEqual(after[.modificationDate] as? Date, past)
    }

    /// A native file that differs from the original outside the marker window
    /// (an older engine's original, or DXMT residue) is rewritten.
    func testMismatchingNativeDXGIIsRewritten() throws {
        try writeOriginal()
        try (Data(count: 0x40) + Data("dxmt-64-residue!".utf8) + Data("stale".utf8)).write(to: system32DXGI)
        try restoreForGPTKDXVK()
        XCTAssertTrue(try Wine.isNativePE(system32DXGI))
        XCTAssertEqual(try strippedTail(system32DXGI), try strippedTail(originalDXGI))
    }

    /// The original byte for byte, marker included, is builtin-marked and so
    /// not the deployed state; it is rewritten and stripped.
    func testUnstrippedCopyOfOriginalIsStripped() throws {
        try writeOriginal()
        try builtinFake("stored-original").write(to: system32DXGI)
        try restoreForGPTKDXVK()
        XCTAssertTrue(try Wine.isNativePE(system32DXGI))
    }
}
