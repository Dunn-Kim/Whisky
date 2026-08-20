//
//  WineProcessScanner.swift
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

import Darwin
import Foundation

/// Cheap, native enumeration of running Wine processes.
///
/// A `wine64 tasklist.exe` round trip costs seconds of wall time and over a billion
/// retired instructions, and boots a wineserver session on an otherwise idle bottle.
/// `proc_listpids` + `proc_pidpath` answer "did the set of Wine processes change?"
/// in about a millisecond, so periodic pollers can reserve the expensive tasklist
/// query for ticks where the membership actually changed.
///
/// Wine processes cannot be matched by process *name*: Wine rewrites the reported
/// command of every Windows process to its Windows image path
/// (`C:\windows\system32\services.exe`), which `ps` and name-based matching would
/// miss entirely. The kernel-reported executable path is authoritative — every
/// Windows process runs the loader under the Whisky Wine distribution folder
/// (`lib/wine/x86_64-unix/wine`, or `bin/wine64` momentarily at spawn).
public enum WineProcessScanner {
    /// The Wine distribution root every Wine executable lives under, with a
    /// trailing separator so prefix matching cannot cross into sibling folders.
    private static let wineRootPrefix = WhiskyWineInstaller.binFolder
        .deletingLastPathComponent().path + "/"

    /// Returns the macOS PIDs of running Wine processes, or `nil` when native
    /// enumeration is unavailable (callers should fall back to unconditional
    /// polling — the failure direction stays safe).
    ///
    /// The wineserver is excluded: it is not a Windows process, and it lingers
    /// briefly after its last client exits, which would otherwise report an idle
    /// bottle as active. The set is also not scoped to a single bottle — all
    /// bottles share one Wine distribution — so with several bottles active, a
    /// change in one triggers a harmless extra refresh in another.
    public static func runningWinePIDs() -> Set<pid_t>? {
        let bytesNeeded = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytesNeeded > 0 else { return nil }

        // Headroom for processes spawned between the size query and the fill.
        let capacity = Int(bytesNeeded) / MemoryLayout<pid_t>.stride + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let bytesFilled = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard bytesFilled > 0 else { return nil }

        var result = Set<pid_t>()
        // proc_pidpath requires a buffer of at least PROC_PIDPATHINFO_MAXSIZE (4 * MAXPATHLEN).
        var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids.prefix(Int(bytesFilled) / MemoryLayout<pid_t>.stride) where pid > 0 {
            let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            // 0 or negative: the process died mid-scan or is not inspectable; skip.
            guard length > 0 else { continue }
            let path = pathBuffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            guard path.hasPrefix(wineRootPrefix), !path.hasSuffix("/wineserver") else { continue }
            result.insert(pid)
        }
        return result
    }
}
