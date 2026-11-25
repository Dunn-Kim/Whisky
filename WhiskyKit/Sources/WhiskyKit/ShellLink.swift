//
//  ShellLink.swift
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

public enum ShellLinkHeader {
    @MainActor
    public static func getProgram(url: URL, handle: FileHandle, bottle: Bottle) -> Program? {
        var offset: UInt64 = 0
        let headerSize = handle.extract(UInt32.self) ?? 0
        // Move past headerSize and linkCLSID
        offset += 4 + 16
        let rawLinkFlags = handle.extract(UInt32.self, offset: offset) ?? 0
        let linkFlags = LinkFlags(rawValue: rawLinkFlags)

        offset = UInt64(headerSize)
        if linkFlags.contains(.hasLinkTargetIDList) {
            // We don't need this section so just get the size, and skip ahead
            offset += UInt64(handle.extract(UInt16.self, offset: offset) ?? 0) + 2
        }

        if linkFlags.contains(.hasLinkInfo) {
            let linkInfo = LinkInfo(
                handle: handle,
                bottle: bottle,
                offset: &offset
            )
            return linkInfo.program
        } else {
            return nil
        }
    }
}

public struct LinkFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    static let hasLinkTargetIDList = LinkFlags(rawValue: 1 << 0)
    static let hasLinkInfo = LinkFlags(rawValue: 1 << 1)
    static let hasIconLocation = LinkFlags(rawValue: 1 << 6)
}

@MainActor
public struct LinkInfo: Hashable {
    public var linkInfoFlags: LinkInfoFlags
    public var program: Program?

    public init(handle: FileHandle, bottle: Bottle, offset: inout UInt64) {
        let startOfSection = offset

        let linkInfoSize = handle.extract(UInt32.self, offset: offset) ?? 0

        offset += 4
        let linkInfoHeaderSize = handle.extract(UInt32.self, offset: offset) ?? 0

        offset += 4
        let rawLinkInfoFlags = handle.extract(UInt32.self, offset: offset) ?? 0
        linkInfoFlags = LinkInfoFlags(rawValue: rawLinkInfoFlags)

        if linkInfoFlags.contains(.volumeIDAndLocalBasePath) {
            if linkInfoHeaderSize >= 0x0000_0024 {
                offset += 20
                let localBasePathOffsetUnicode = handle.extract(UInt32.self, offset: offset) ?? 0
                let localPathOffset = startOfSection + UInt64(localBasePathOffsetUnicode)

                program = getProgram(
                    handle: handle,
                    offset: localPathOffset,
                    bottle: bottle,
                    unicode: true
                )
            } else {
                offset += 8
                let localBasePathOffset = handle.extract(UInt32.self, offset: offset) ?? 0
                let localPathOffset = startOfSection + UInt64(localBasePathOffset)

                program = getProgram(
                    handle: handle,
                    offset: localPathOffset,
                    bottle: bottle,
                    unicode: false
                )
            }
        }

        offset = startOfSection + UInt64(linkInfoSize)
    }

    func getProgram(handle: FileHandle, offset: UInt64, bottle: Bottle, unicode: Bool) -> Program? {
        do {
            try handle.seek(toOffset: offset)
            if let pathData = try handle.readToEnd(),
               var string = Self.localBasePath(in: pathData, unicode: unicode) {
                // UNIX-ify the path
                string.replace("\\", with: "/")
                string.replace("C:", with: "\(bottle.url.path)/drive_c")
                let url = URL(filePath: string)
                return Program(url: url, bottle: bottle)
            }
        } catch {
            return nil
        }

        return nil
    }

    /// The NUL-terminated local base path at the start of `data`: UTF-16LE when
    /// `unicode`, ended by two zero bytes on an even offset (the first zero byte is
    /// the high half of `C`), otherwise in the ANSI code page.
    nonisolated static func localBasePath(in data: Data, unicode: Bool) -> String? {
        let bytes = [UInt8](data)
        if unicode {
            var end = 0
            while end + 1 < bytes.count {
                if bytes[end] == 0, bytes[end + 1] == 0 {
                    return String(bytes: bytes[..<end], encoding: .utf16LittleEndian)
                }
                end += 2
            }
            return nil
        }
        guard let end = bytes.firstIndex(of: 0) else { return nil }
        return String(bytes: bytes[..<end], encoding: .windowsCP1254)
    }
}

public struct LinkInfoFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    static let volumeIDAndLocalBasePath = LinkInfoFlags(rawValue: 1 << 0)
    static let commonNetworkRelativeLinkAndPathSuffix = LinkInfoFlags(rawValue: 1 << 1)
}
