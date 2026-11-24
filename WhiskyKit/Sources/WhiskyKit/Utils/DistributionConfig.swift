//
//  DistributionConfig.swift
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

public enum DistributionConfig {
    /// Base URL for GitHub Pages distribution
    public static let baseURL = "https://frankea.github.io/Whisky"

    // shortcut: no arm64 runtime is published yet, so this feed 404s; publish the plist when one is.
    /// URL for the WhiskyWine version plist file, which names the engine to
    /// install and offers as an update.
    ///
    /// Apps before 3.10.0 read `WhiskyWineVersion.plist`, which stays on the
    /// stock 3.1.1 engine: the GPTK-capable engine was tested with 3.10.0 and
    /// its graphics, DLL override and environment fixes, so older apps are not
    /// offered an engine switch nobody tested them with. This feed is the one
    /// that moves.
    ///
    /// This fork serves the feed from its own repository: its engine carries
    /// patches upstream's does not, so an upstream engine would install
    /// without them and be offered as an update over them.
    public static let versionPlistURL =
        "https://raw.githubusercontent.com/Dunn-Kim/Whisky/arm64-native/dist/pages/WhiskyWineVersion-arm64.plist"

    /// The feed apps before 3.10.0 read. This arm64 build has no stock engine to
    /// freeze on, so it shares the arm64 feed.
    static let legacyVersionPlistURL = versionPlistURL

    /// The GitHub Releases page, which lists the Wine Libraries engine builds
    /// this fork's feed names.
    public static let releasesPageURL = "https://github.com/Dunn-Kim/Whisky/releases"

    /// Base URL for GitHub Releases downloads
    public static let releasesBaseURL = "\(releasesPageURL)/download"

    /// URL for the Sparkle appcast feed
    public static let appcastURL = "\(baseURL)/appcast.xml"

    /// Constructs the download URL for Wine Libraries from GitHub Releases
    /// - Parameter version: The version string (e.g., "2.5.0")
    /// - Returns: The full URL to download Libraries.tar.gz from GitHub Releases
    public static func librariesURL(version: String) -> String {
        "\(releasesBaseURL)/v\(version)/Libraries.tar.gz"
    }
}
