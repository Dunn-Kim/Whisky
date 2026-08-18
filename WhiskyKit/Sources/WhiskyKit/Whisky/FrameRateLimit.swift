//
//  FrameRateLimit.swift
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

import AppKit
import Foundation

/// A cap on how many frames a game is allowed to present per second.
///
/// Games that present without a limiter render as fast as the GPU allows. Every
/// frame past the display's refresh rate is discarded before it is ever shown,
/// so the extra work buys nothing and pins the GPU at its maximum clock. On a
/// laptop that is the difference between a warm chassis and a hot one.
///
/// The limit is applied by the translation layer, so it only takes effect on
/// backends that ship a limiter -- see ``GraphicsBackend/supportsFrameRateLimit``.
public enum FrameRateLimit: Int, Codable, CaseIterable, Equatable, Sendable {
    /// No cap: the game presents as fast as it can render.
    case unlimited = 0
    /// Cap at the refresh rate of the display the Mac is currently driving.
    case matchDisplay = -1
    case fps30 = 30
    case fps60 = 60
    case fps90 = 90
    case fps120 = 120
    case fps144 = 144

    /// A human-readable label for pickers.
    public var label: String {
        switch self {
        case .unlimited:
            String(localized: "config.frameRateLimit.unlimited")
        case .matchDisplay:
            String(localized: "config.frameRateLimit.matchDisplay")
        default:
            "\(rawValue) FPS"
        }
    }

    /// The refresh rate of the main display, or `nil` when it cannot be read.
    ///
    /// `NSScreen.maximumFramesPerSecond` reports the panel's peak rate, which is
    /// what a variable-refresh display should be allowed to reach.
    @MainActor
    public static func mainDisplayRefreshRate() -> Int? {
        guard let rate = NSScreen.main?.maximumFramesPerSecond, rate > 0 else { return nil }
        return rate
    }

    /// Resolves this limit to a concrete frames-per-second value.
    ///
    /// - Parameter displayRefreshRate: The refresh rate to use for
    ///   ``matchDisplay``. When `nil`, ``matchDisplay`` resolves to no cap
    ///   rather than guessing a rate that could cap a fast panel too low.
    /// - Returns: The cap in frames per second, or `nil` for no cap.
    public func resolved(displayRefreshRate: Int?) -> Int? {
        switch self {
        case .unlimited:
            nil
        case .matchDisplay:
            displayRefreshRate
        default:
            rawValue
        }
    }
}

public extension GraphicsBackend {
    /// Whether this backend ships a frame rate limiter Whisky can drive.
    ///
    /// D3DMetal and WineD3D expose no such knob, so a limit selected against
    /// them is inert and the UI says so instead of pretending it applied.
    var supportsFrameRateLimit: Bool {
        switch self {
        case .dxvk, .dxmt:
            true
        case .recommended, .d3dMetal, .wined3d:
            false
        }
    }

    /// Every variable any backend may use to cap the frame rate.
    ///
    /// A program-level override has to clear the bottle's cap before applying
    /// its own, including the variable belonging to a *different* backend when
    /// the program also overrides which backend is used.
    static var allFrameRateLimitKeys: [String] {
        ["DXVK_FRAME_RATE", "DXMT_CONFIG"]
    }

    /// Environment entries that cap presentation at `fps` for this backend.
    ///
    /// - Parameter fps: The cap in frames per second. Values below 1 are ignored.
    /// - Returns: The variables to set, or an empty dictionary when this backend
    ///   has no limiter.
    func frameRateLimitEnvironment(fps: Int) -> [String: String] {
        guard fps > 0 else { return [:] }
        switch self {
        case .dxvk:
            // DXVK's own limiter; also settable as `dxgi.maxFrameRate` in dxvk.conf.
            return ["DXVK_FRAME_RATE": String(fps)]
        case .dxmt:
            // DXMT reads a DXVK-style `key=value` list from DXMT_CONFIG.
            return ["DXMT_CONFIG": "d3d11.preferredMaxFrameRate=\(fps)"]
        case .recommended, .d3dMetal, .wined3d:
            return [:]
        }
    }
}
