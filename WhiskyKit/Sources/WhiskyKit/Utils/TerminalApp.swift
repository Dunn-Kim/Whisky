//
//  TerminalApp.swift
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
import os.log

/// Supported terminal applications for running Wine commands.
///
/// This enum provides AppleScript generation for launching shell scripts in different
/// terminal applications. Use ``generateAppleScript(for:)`` to execute a script file.
///
/// ## Terminal Support Notes
///
/// - **Terminal.app**: Full AppleScript support via `do script`
/// - **iTerm2**: Full AppleScript support via `write text`
/// - **Warp**: Limited AppleScript support; uses `open -a Warp` to launch script files.
///   Warp executes `.sh` files when opened if they have executable permissions.
public enum TerminalApp: String, CaseIterable, Identifiable {
    case terminal
    case iterm
    case warp

    public var id: String {
        rawValue
    }

    /// The display name for the terminal application.
    public var displayName: String {
        switch self {
        case .terminal:
            "Terminal"
        case .iterm:
            "iTerm2"
        case .warp:
            "Warp"
        }
    }

    /// The bundle identifier for the terminal application.
    public var bundleIdentifier: String {
        switch self {
        case .terminal:
            "com.apple.Terminal"
        case .iterm:
            "com.googlecode.iterm2"
        case .warp:
            "dev.warp.Warp-Stable"
        }
    }

    /// Whether this terminal application is installed on the system.
    public var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    /// Returns the list of installed terminal applications.
    public static var installedTerminals: [TerminalApp] {
        allCases.filter(\.isInstalled)
    }

    /// The user's preferred terminal application.
    /// Falls back to Terminal.app if the preferred app is not installed.
    public static var preferred: TerminalApp {
        let rawValue = UserDefaults.standard.string(forKey: "preferredTerminal") ?? "terminal"
        let preferred = TerminalApp(rawValue: rawValue) ?? .terminal
        // Fall back to Terminal if preferred is not installed
        return preferred.isInstalled ? preferred : .terminal
    }

    /// Has the preferred terminal `source` `script`, written to a temp `.sh`
    /// the caller deletes. Throws when the script can't be written; an
    /// AppleScript failure is shown as the run-error alert naming `subject`.
    @discardableResult
    public static func runScript(_ script: String, namePrefix: String, subject: String) async throws -> URL {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(namePrefix)-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        var error: NSDictionary?
        NSAppleScript(source: preferred.generateAppleScript(for: scriptURL.path))?.executeAndReturnError(&error)
        if let error {
            Logger.wineKit.error("Failed to run terminal script \(error)")
            if let description = error["NSAppleScriptErrorMessage"] as? String {
                await showError("\(subject): " + description)
            }
        }
        return scriptURL
    }

    /// The critical "failed to open" alert, `detail` appended to the standard text.
    @MainActor
    public static func showError(_ detail: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = String(localized: "alert.info") + detail
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }

    /// Generates an AppleScript to run the given script file in this terminal.
    /// - Parameter scriptPath: The path to the shell script to execute.
    /// - Returns: The AppleScript source code.
    public func generateAppleScript(for scriptPath: String) -> String {
        let escapedPath = scriptPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        switch self {
        case .terminal:
            return """
            tell application "Terminal"
                activate
                do script "source \\"\(escapedPath)\\""
            end tell
            """

        case .iterm:
            return """
            tell application "iTerm"
                activate
                create window with default profile
                tell current session of current window
                    write text "source \\"\(escapedPath)\\""
                end tell
            end tell
            """

        case .warp:
            // Warp doesn't support AppleScript's `do script` or `write text` commands.
            // Instead, we use `open -a Warp` with the script file, which Warp will execute
            // if the file has executable permissions (.sh extension and chmod +x).
            return """
            tell application "Warp"
                activate
            end tell
            do shell script "open -a Warp \\"\(escapedPath)\\""
            """
        }
    }
}
