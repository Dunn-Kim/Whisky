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
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
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
}
