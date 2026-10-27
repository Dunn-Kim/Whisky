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
            // Headers of 0x24+ carry a Unicode local base path offset at +20, older ones an ANSI one at +8.
            let unicode = linkInfoHeaderSize >= 0x0000_0024
            offset += unicode ? 20 : 8
            let localBasePathOffset = handle.extract(UInt32.self, offset: offset) ?? 0
            program = getProgram(
                handle: handle,
                offset: startOfSection + UInt64(localBasePathOffset),
                bottle: bottle,
                unicode: unicode
            )
        }

        offset = startOfSection + UInt64(linkInfoSize)
    }

    func getProgram(handle: FileHandle, offset: UInt64, bottle: Bottle, unicode: Bool) -> Program? {
        do {
            try handle.seek(toOffset: offset)
            if let pathData = try handle.readToEnd() {
                if let nullRange = pathData.firstIndex(of: 0) {
                    let encoding: String.Encoding = unicode ? .utf16 : .windowsCP1254
                    if var string = String(data: pathData[..<nullRange], encoding: encoding) {
                        // UNIX-ify the path
                        string.replace("\\", with: "/")
                        string.replace("C:", with: "\(bottle.url.path)/drive_c")
                        let url = URL(filePath: string)
                        return Program(url: url, bottle: bottle)
                    }
                }
            }
        } catch {
            return nil
        }

        return nil
    }
}

public struct LinkInfoFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    static let volumeIDAndLocalBasePath = LinkInfoFlags(rawValue: 1 << 0)
}
