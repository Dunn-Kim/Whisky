//
//  BottleWineConfig.swift
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
import SemanticVersion

public enum WinVersion: String, CaseIterable, Codable, Sendable {
    case winXP = "winxp64"
    case win7
    case win8
    case win81
    case win10
    case win11

    public func pretty() -> String {
        switch self {
        case .winXP:
            "Windows XP"
        case .win7:
            "Windows 7"
        case .win8:
            "Windows 8"
        case .win81:
            "Windows 8.1"
        case .win10:
            "Windows 10"
        case .win11:
            "Windows 11"
        }
    }
}

/// The runtime implements msync and runs it by default; `none` turns it off.
///
/// Stored as the synthesized form (`{"msync": {}}`). Older versions also had `esync`,
/// which no runtime implements: it, and anything unknown, loads as the default, `msync`.
public enum EnhancedSync: Codable, Equatable, Sendable {
    case none, msync

    private enum CodingKeys: String, CodingKey {
        case none, msync
    }

    public init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        self = container?.contains(.none) == true ? .none : .msync
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        _ = container.nestedContainer(keyedBy: CodingKeys.self, forKey: self == .none ? .none : .msync)
    }
}

public struct BottleWineConfig: Codable, Equatable {
    static let defaultWineVersion = SemanticVersion(7, 7, 0)
    var wineVersion: SemanticVersion = Self.defaultWineVersion
    var windowsVersion: WinVersion = .win10
    var enhancedSync: EnhancedSync = .msync

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.wineVersion = try container.decodeIfPresent(SemanticVersion.self, forKey: .wineVersion) ?? Self
            .defaultWineVersion
        self.windowsVersion = container.decodeLenientIfPresent(WinVersion.self, forKey: .windowsVersion) ?? .win10
        self.enhancedSync = try container.decodeIfPresent(EnhancedSync.self, forKey: .enhancedSync) ?? .msync
    }
}
