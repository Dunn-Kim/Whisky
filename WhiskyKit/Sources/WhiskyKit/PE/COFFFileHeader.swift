//
//  COFFFileHeader.swift
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
    /// COFF File Header (Object and Image)
    ///
    /// https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#coff-file-header-object-and-image
    public struct COFFFileHeader: Hashable, Equatable, Sendable {
        public let numberOfSections: UInt16
        public let sizeOfOptionalHeader: UInt16

        init(handle: FileHandle, offset: UInt64) {
            // `offset` points at the 4-byte "PE\0\0" signature that precedes the header.
            self.numberOfSections = handle.extract(UInt16.self, offset: offset + 6) ?? 0
            self.sizeOfOptionalHeader = handle.extract(UInt16.self, offset: offset + 20) ?? 0
        }
    }
}
