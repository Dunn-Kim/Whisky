//
//  BottleGraphicsConfig.swift
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

/// The graphics translation backend for a Wine bottle.
///
/// The runtime ships its graphics layers built in and picks one per executable.
/// `.recommended` is the runtime's default, which ``GraphicsBackendResolver``
/// resolves to DXMT for `dxgi`, or to WineD3D for programs whose window Chromium draws.
///
/// A raw value this build does not know decodes as `.recommended`: settings
/// written when DXVK and D3DMetal were choices (`"dxvk"`, `"d3dMetal"`) still load.
public enum GraphicsBackend: String, Codable, CaseIterable, Equatable, Sendable {
    /// The runtime's default.
    case recommended
    /// DXMT: Direct3D-11-to-Metal translation.
    case dxmt
    /// Wine's built-in OpenGL-based Direct3D translation.
    case wined3d

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .recommended
    }

    /// A human-readable display name for this backend.
    public var displayName: String {
        switch self {
        case .recommended:
            String(localized: "config.graphics.backend.recommended")
        case .dxmt:
            "DXMT"
        case .wined3d:
            "WineD3D"
        }
    }

    /// A one-line summary suitable for selection cards or tooltips.
    public var summary: String {
        switch self {
        case .recommended:
            String(localized: "config.graphics.backend.recommended.summary")
        case .dxmt:
            String(localized: "config.graphics.backend.dxmt.summary")
        case .wined3d:
            String(localized: "config.graphics.backend.wined3d.summary")
        }
    }
}

extension KeyedDecodingContainer {
    /// Decodes a string-backed enum leniently: an absent key yields `nil`, and an
    /// unknown or wrong-typed value also yields `nil` (logged) instead of throwing
    /// out of the parent decode. This keeps settings written by a newer Whisky —
    /// one that added an enum case this build doesn't know — loadable, instead of
    /// a single unrecognized value bricking the whole bottle's settings.
    ///
    /// Only applies to `String`-raw-value enums.
    func decodeLenientIfPresent<T: RawRepresentable>(
        _: T.Type,
        forKey key: Key
    ) -> T? where T.RawValue == String {
        let typeName = String(describing: T.self)
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        let raw: String?
        do {
            raw = try decodeIfPresent(String.self, forKey: key)
        } catch let error as DecodingError {
            // A wrong-typed value (e.g. a number or object where a string was expected) is
            // corruption — it cannot be produced by any real Whisky build — so log at .error.
            Logger.wineKit.error(
                """
                Ignoring corrupt \(typeName, privacy: .public) at \
                `\(key.stringValue, privacy: .public)` (path: \(path, privacy: .public)): \
                \(String(describing: error), privacy: .public)
                """
            )
            return nil
        } catch {
            Logger.wineKit.error(
                """
                Ignoring malformed \(typeName, privacy: .public) at \
                `\(key.stringValue, privacy: .public)` (path: \(path, privacy: .public)): \
                \(String(describing: error), privacy: .public)
                """
            )
            return nil
        }
        guard let raw else { return nil }
        guard let value = T(rawValue: raw) else {
            // A well-formed string that this build doesn't recognize is legitimate
            // forward-compat (a newer Whisky added an enum case) — log at .warning.
            Logger.wineKit.warning(
                """
                Ignoring unknown \(typeName, privacy: .public) value `\(raw, privacy: .public)` at \
                `\(key.stringValue, privacy: .public)` (path: \(path, privacy: .public)); using default
                """
            )
            return nil
        }
        return value
    }
}

/// Stores the graphics backend choice for a bottle.
///
/// This config is serialized alongside other bottle config groups in
/// ``BottleSettings``. The defensive `init(from:)` decodes a malformed backend
/// value gracefully to `.recommended` rather than throwing out of the whole
/// settings decode.
public struct BottleGraphicsConfig: Codable, Equatable {
    /// The selected graphics backend. Defaults to `.recommended`.
    var backend: GraphicsBackend = .recommended

    /// How many frames a game may present per second.
    ///
    /// New bottles cap at the display's refresh rate, since frames rendered past
    /// it are discarded before they are shown and only cost power. Bottles
    /// written before this setting existed decode to ``FrameRateLimit/unlimited``
    /// so their behaviour does not change underneath them.
    var frameRateLimit: FrameRateLimit = .matchDisplay

    /// Whether DXMT runs its swapchain through MetalFX's spatial upscaler.
    ///
    /// DXMT doubles the output resolution, so a game
    /// keeps rendering at the size it chose and reaches a Retina panel sharpened
    /// by MetalFX rather than stretched by the compositor. That is a quality
    /// trade, not a speedup — the upscale costs GPU time — so it is off unless
    /// asked for. Inert under every other backend.
    var dxmtMetalFXUpscale: Bool = false

    /// Creates a new graphics config with the default `.recommended` backend.
    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.backend = (try? container.decodeIfPresent(GraphicsBackend.self, forKey: .backend)) ?? .recommended
        // Int-raw enum, so the String-only lenient helper does not apply. An
        // unknown value or one of another type decodes to `.unlimited` rather
        // than failing the bottle.
        let rawLimit = (try? container.decodeIfPresent(Int.self, forKey: .frameRateLimit)) ?? nil
        self.frameRateLimit = rawLimit.flatMap(FrameRateLimit.init(rawValue:)) ?? .unlimited
        self.dxmtMetalFXUpscale = (try? container.decodeIfPresent(Bool.self, forKey: .dxmtMetalFXUpscale)) ?? false
    }
}
