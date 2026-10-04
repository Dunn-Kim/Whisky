//
//  BottleFontBootstrap.swift
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

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "BottleFontBootstrap")

/// Copies a small set of host fonts into a bottle's `drive_c/windows/Fonts` directory
/// so Unity titles using dynamic font fallback don't render missing glyphs.
public enum BottleFontBootstrap {
    /// Host font candidates to copy into a bottle. The first existing path for each
    /// destination filename wins; missing host fonts are skipped silently.
    private static let candidates: [(destination: String, sources: [String])] = [
        ("Arial Unicode.ttf", ["/Library/Fonts/Arial Unicode.ttf"]),
        ("Arial.ttf", ["/Library/Fonts/Arial.ttf", "/System/Library/Fonts/Supplemental/Arial.ttf"]),
        ("Tahoma.ttf", ["/Library/Fonts/Tahoma.ttf", "/System/Library/Fonts/Supplemental/Tahoma.ttf"])
    ]

    /// Korean font names, each answered by the host's Apple SD Gothic Neo.
    ///
    /// Wine has already enumerated Apple SD Gothic Neo from the host, but nothing
    /// asks for it by that name. DirectWrite's system fallback sends every Hangul
    /// range to `Noto Sans CJK KR` (wine 11.0, `dlls/dwrite/analyzer.c`) and, not
    /// finding it, leaves the text unmapped: an embedded Chromium page set in
    /// Arial draws its Hangul as boxes. A Korean UI that names a Windows font —
    /// Malgun Gothic, Gulim, Dotum, Batang — misses the same way. gdi and
    /// DirectWrite both resolve these names through `Software\Wine\Fonts\Replacements`.
    static let koreanFontReplacements = [
        "Noto Sans CJK KR",
        "Malgun Gothic", "맑은 고딕", "Gulim", "굴림", "GulimChe", "굴림체",
        "Dotum", "돋움", "DotumChe", "돋움체", "Batang", "바탕", "BatangChe", "바탕체",
        "Gungsuh", "궁서", "GungsuhChe", "궁서체"
    ]

    /// The `.reg` section mapping ``koreanFontReplacements`` onto Apple SD Gothic
    /// Neo. Values only: the key is never deleted, so replacements a user added
    /// for other names survive.
    static var fontReplacementsRegistrySection: String {
        let values = koreanFontReplacements.map { "\"\($0)\"=\"Apple SD Gothic Neo\"" }
        return ([#"[HKCU\Software\Wine\Fonts\Replacements]"#] + values + [""]).joined(separator: "\r\n")
    }

    /// Copies missing fonts into `<bottlePrefix>/drive_c/windows/Fonts`.
    /// Idempotent: existing destination files are left untouched.
    public static func copySystemFonts(toPrefix prefix: URL) {
        let dest = prefix.appending(path: "drive_c/windows/Fonts")
        let manager = FileManager.default
        try? manager.createDirectory(at: dest, withIntermediateDirectories: true)

        for (filename, sources) in candidates {
            let destURL = dest.appending(path: filename)
            guard !manager.fileExists(atPath: destURL.path(percentEncoded: false)) else { continue }
            guard let source = sources.first(where: { manager.fileExists(atPath: $0) }) else { continue }
            do {
                try manager.copyItem(at: URL(fileURLWithPath: source), to: destURL)
                logger.info("Bootstrapped \(filename, privacy: .public) into bottle fonts")
            } catch {
                logger.warning("Failed to copy \(filename, privacy: .public): \(error.localizedDescription)")
            }
        }
    }
}
