//
//  Section.swift
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

/// Intentionally not marked public to avoid Swift 6 redundant access modifiers.
/// Nested types remain public to preserve the API surface.
extension PEFile {
    /// Section Table (Section Headers)
    ///
    /// https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#section-table-section-headers
    public struct Section: Hashable, Equatable, Sendable {
        public let name: String
        public let virtualSize: UInt32
        public let virtualAddress: UInt32
        public let pointerToRawData: UInt32

        init?(handle: FileHandle, offset: UInt64) {
            do {
                try handle.seek(toOffset: offset)
                if let data = try handle.read(upToCount: 8) {
                    let string = String(data: data, encoding: .utf8) ?? String()
                    self.name = string.replacingOccurrences(of: "\0", with: "")
                } else {
                    self.name = ""
                }
            } catch {
                return nil
            }

            self.virtualSize = handle.extract(UInt32.self, offset: offset + 8) ?? 0
            self.virtualAddress = handle.extract(UInt32.self, offset: offset + 12) ?? 0
            self.pointerToRawData = handle.extract(UInt32.self, offset: offset + 20) ?? 0
        }
    }
}
