//
//  GPUDetection.swift
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

/// Utilities for GPU capability detection and spoofing.
///
/// ## Overview
///
/// Many game launchers perform GPU compatibility checks using DirectX and OpenGL
/// queries. On Apple Silicon Macs using Wine/CrossOver, these queries may return
/// incomplete or incorrect information, causing launchers to report "GPU not supported"
/// or display black screens.
///
/// This system addresses frankea/Whisky#41 by configuring environment variables that make
/// Wine report high-end GPU capabilities, allowing launchers to pass their checks.
///
/// ## Safety Note
///
/// GPU spoofing only affects capability reporting to launchers and DirectX queries.
/// It does **not** modify game memory or interfere with anti-cheat systems. The
/// actual rendering still uses Apple's Metal API through Wine's translation layer.
///
/// ## Example
///
/// ```swift
/// // Spoofing for a launcher's GPU check
/// let env = GPUDetection.spoofGPU()
/// ```
public enum GPUDetection {
    /// Configures environment to report specific GPU capabilities.
    ///
    /// This method sets environment variables that Wine and DirectX use to report
    /// GPU features. Helps launchers pass compatibility checks that would otherwise
    /// fail due to incomplete Metal driver information.
    ///
    /// Only the two Mesa version overrides are set. No shipped runtime reads
    /// a vendor or device id variable, so there is no vendor to choose.
    ///
    /// - Returns: Dictionary of environment variables for GPU spoofing
    public static func spoofGPU() -> [String: String] {
        var env: [String: String] = [:]

        // OpenGL version reporting (4.6 is modern and well-supported)
        env["MESA_GL_VERSION_OVERRIDE"] = "4.6"
        env["MESA_GLSL_VERSION_OVERRIDE"] = "460"

        return env
    }
}
