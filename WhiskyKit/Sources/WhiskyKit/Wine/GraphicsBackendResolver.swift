//
//  GraphicsBackendResolver.swift
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

/// Resolves the `.recommended` graphics backend to a concrete backend.
///
/// This is a caseless enum (static methods only) following the ``GPUDetection`` pattern.
/// `.recommended` is the runtime's default, which is DXMT for `dxgi`.
public enum GraphicsBackendResolver {
    /// Resolves the recommended graphics backend for the current system.
    ///
    /// - Parameter launcher: The launcher this launch targets, if any. Launchers
    ///   always resolve to WineD3D: their Chromium UIs cannot render on DXMT.
    /// - Returns: A concrete ``GraphicsBackend`` (never `.recommended`).
    public static func resolve(for launcher: LauncherType? = nil) -> GraphicsBackend {
        resolution(for: launcher.map { BackendSteering.launcher($0) }).backend
    }

    /// Resolves the recommended graphics backend for what is being launched,
    /// with the reason for the pick.
    ///
    /// - Parameter steering: Why the executable being launched needs WineD3D, if it does
    ///   (``BackendSteering/inspect(executable:)``). A steered executable always
    ///   resolves to WineD3D: its window is drawn by Chromium, which cannot
    ///   render on DXMT.
    /// - Returns: A concrete backend (never `.recommended`) and why it was picked.
    public static func resolution(for steering: BackendSteering?) -> BackendResolution {
        // Launcher clients and Chromium front ends cannot render on DXMT: the
        // CEF gpu process fails to create its window swapchain and the window
        // stays black, or never appears. What they start still resolves below.
        if let steering {
            return BackendResolution(backend: .wined3d, reason: .steered(steering))
        }
        return BackendResolution(backend: .dxmt, reason: .dxmt)
    }

    /// Returns a localized explanation for the recommended backend choice.
    ///
    /// Suitable for display in a detail label or tooltip next to the "Recommended" option.
    ///
    /// - Parameter macOSVersion: The macOS version to consider. Defaults to the running system.
    /// - Returns: A human-readable rationale string.
    public static func rationale(macOSVersion: MacOSVersion = .current) -> String {
        String(localized: "config.graphics.backend.recommended.rationale")
    }
}

/// Why an executable needs WineD3D whatever Recommended picks for the bottle's
/// games: its window is drawn by Chromium.
public enum BackendSteering: Sendable, Equatable {
    /// A launcher client, which also gets its helpers and chain entries.
    case launcher(LauncherType)
    /// A program from the curated ``ChromiumFrontEnd`` table.
    case chromiumFrontEnd(ChromiumFrontEnd)
    /// An Electron or NW.js app, found by its files (``ChromiumRuntimeDetector``).
    /// `evidence` is the file beside it that identified it, such as
    /// `resources/app.asar`.
    case chromiumRuntime(kind: ChromiumRuntimeKind, evidence: String)

    /// Detects the steering for an executable: a launcher first, so every
    /// launcher keeps its own path, then the front-end table. String matching
    /// only, so it is safe in a view body. Electron and NW.js apps need their
    /// files read: ``inspect(executable:)``.
    public static func detect(executable url: URL) -> BackendSteering? {
        if let launcher = LauncherType.detect(from: url) {
            return .launcher(launcher)
        }
        return ChromiumFrontEnd.match(url: url).map { .chromiumFrontEnd($0) }
    }

    /// The launcher's or front end's name, or the runtime's, as shown in the UI.
    public var displayName: String {
        switch self {
        case let .launcher(launcher):
            launcher.displayName
        case let .chromiumFrontEnd(frontEnd):
            frontEnd.displayName
        case let .chromiumRuntime(kind, _):
            kind.displayName
        }
    }

    /// The name a steered program is listed under: the launcher's or front
    /// end's, and an Electron or NW.js app's own, from its executable.
    public func listedName(executable url: URL) -> String {
        guard case .chromiumRuntime = self else { return displayName }
        return url.deletingPathExtension().lastPathComponent
    }

    /// Separate executables that share the steered executable's set, with the
    /// NVIDIA bridges disabled.
    public var helperExecutables: [String] {
        switch self {
        case let .launcher(launcher):
            launcher.helperExecutables
        case let .chromiumFrontEnd(frontEnd):
            frontEnd.helperExecutables
        case .chromiumRuntime:
            // Its Chromium children run as the same executable.
            []
        }
    }

    /// The evidence, for logs and diagnostics exports. Not localized.
    public var evidence: String {
        switch self {
        case let .launcher(launcher):
            "launcher: \(launcher.rawValue)"
        case let .chromiumFrontEnd(frontEnd):
            "Chromium front end: \(frontEnd.displayName)"
        case let .chromiumRuntime(kind, evidence):
            "\(kind.displayName) app: \(evidence)"
        }
    }
}

/// Why Recommended resolved to the backend it did.
public enum RecommendedReason: Sendable, Equatable {
    /// The executable's window is drawn by Chromium, so it runs on WineD3D.
    case steered(BackendSteering)
    /// The runtime's default for `dxgi`.
    case dxmt

    /// A short, stable description for diagnostics exports. Not localized.
    public var exportName: String {
        switch self {
        case let .steered(steering):
            "steered to WineD3D (\(steering.evidence))"
        case .dxmt:
            "runtime default, DXMT"
        }
    }
}

/// The backend Recommended resolves to, and why.
public struct BackendResolution: Sendable, Equatable {
    /// The concrete backend, never `.recommended`.
    public let backend: GraphicsBackend
    /// Why it was picked.
    public let reason: RecommendedReason

    public init(backend: GraphicsBackend, reason: RecommendedReason) {
        self.backend = backend
        self.reason = reason
    }

    /// A localized explanation of the pick.
    ///
    /// - Parameter gamesBackend: What Recommended resolves to for the bottle's
    ///   games, which the programs a steered executable starts keep.
    public func rationale(gamesBackend: GraphicsBackend) -> String {
        guard case let .steered(steering) = reason else {
            return GraphicsBackendResolver.rationale()
        }
        let games = gamesBackend.displayName
        return switch steering {
        case .launcher:
            String(localized: "config.graphics.backend.recommended.launcher \(games)")
        case .chromiumFrontEnd:
            String(localized: "config.graphics.backend.recommended.frontEnd \(games)")
        case let .chromiumRuntime(.electron, evidence):
            String(localized: "config.graphics.backend.recommended.electron \(evidence)")
        case let .chromiumRuntime(.nwjs, evidence):
            String(localized: "config.graphics.backend.recommended.nwjs \(evidence)")
        }
    }
}
