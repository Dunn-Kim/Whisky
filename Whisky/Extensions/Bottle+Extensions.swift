//
//  Bottle+Extensions.swift
//  Whisky
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
import WhiskyKit

/// MainActor-isolated cache for Wine usernames to avoid repeated filesystem scans.
@MainActor
private var wineUsernameCache: [URL: String] = [:]

extension Bottle {
    /// The detected Wine username for this bottle.
    ///
    /// Wine creates user profile directories in `drive_c/users/`. This property
    /// scans that directory to find the actual username used by Wine, which may
    /// differ from the default "crossover" depending on the Wine build or
    /// how the bottle was created.
    ///
    /// The result is cached to avoid repeated filesystem operations.
    ///
    /// - Returns: The detected username, or "crossover" as a fallback.
    @MainActor
    var wineUsername: String {
        if let cached = wineUsernameCache[url] {
            return cached
        }
        let usersDir = url.appending(path: "drive_c").appending(path: "users")
        let username = WinePrefixValidation.detectWineUsername(in: usersDir) ?? "crossover"
        wineUsernameCache[url] = username
        return username
    }

    /// Clears the cached Wine username for this bottle.
    ///
    /// Call this after operations that may change the username (e.g., prefix repair).
    @MainActor
    func clearWineUsernameCache() {
        wineUsernameCache.removeValue(forKey: url)
    }

    /// The program for `url`: the bottle's own instance when its list has one,
    /// so a launch and the program's settings page share one copy of the
    /// settings, otherwise a new one (an executable outside `Program Files`).
    @MainActor
    func program(at url: URL) -> Program {
        programs.first(where: { $0.url == url }) ?? Program(url: url, bottle: self)
    }

    func openCDrive() {
        NSWorkspace.shared.open(url.appending(path: "drive_c"))
    }

    func openTerminal() {
        guard let whiskyCmdURL = Bundle.main.url(forResource: "WhiskyCmd", withExtension: nil) else { return }

        // Build a shell command that sources the WhiskyCmd environment.
        // Single-quoted through ShellQuoting: `.esc` backslash-escapes spaces,
        // and inside double quotes bash keeps those backslashes, so any bottle
        // name with a space reached WhiskyCmd as `QA\ Smoke` and failed to
        // resolve.
        let whiskyCmd = whiskyCmdURL.path(percentEncoded: false)
        let shellenv = ShellQuoting.commandLine([whiskyCmd, "shellenv", settings.name])
        let command = "eval \"$(\(shellenv))\""
        let scriptContent = "#!/bin/bash\n\(command)\n"
        let subject = url.lastPathComponent

        Task.detached(priority: .userInitiated) {
            let scriptURL: URL
            do {
                scriptURL = try await TerminalApp.runScript(scriptContent, namePrefix: "whisky-env", subject: subject)
            } catch {
                Logger.wineKit.error("Failed to write terminal script: \(error)")
                return
            }

            // Clean up temp script after a delay to ensure the terminal has read it
            try? await Task.sleep(for: .seconds(5))
            await TempFileTracker.shared.cleanupWithRetry(file: scriptURL)
        }
    }

    @discardableResult
    // swiftlint:disable:next function_body_length
    func getStartMenuPrograms() -> [Program] {
        let globalStartMenu = url
            .appending(path: "drive_c")
            .appending(path: "ProgramData")
            .appending(path: "Microsoft")
            .appending(path: "Windows")
            .appending(path: "Start Menu")

        let userStartMenu = url
            .appending(path: "drive_c")
            .appending(path: "users")
            .appending(path: wineUsername)
            .appending(path: "AppData")
            .appending(path: "Roaming")
            .appending(path: "Microsoft")
            .appending(path: "Windows")
            .appending(path: "Start Menu")

        var startMenuPrograms: [Program] = []
        var linkURLs: [URL] = []
        let globalEnumerator = FileManager.default.enumerator(
            at: globalStartMenu,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = globalEnumerator?.nextObject() as? URL {
            if url.pathExtension == "lnk" {
                linkURLs.append(url)
            }
        }

        let userEnumerator = FileManager.default.enumerator(
            at: userStartMenu,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = userEnumerator?.nextObject() as? URL {
            if url.pathExtension == "lnk" {
                linkURLs.append(url)
            }
        }

        linkURLs.sort(by: { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() })

        for link in linkURLs {
            do {
                if let program = try ShellLinkHeader.getProgram(
                    url: link,
                    handle: FileHandle(forReadingFrom: link),
                    bottle: self
                ) {
                    if !startMenuPrograms.contains(where: { $0.url == program.url }) {
                        startMenuPrograms.append(program)
                    }
                    // Remove every shortcut to the program, not just the first one.
                    // A leftover duplicate would be picked up again on the next scan.
                    try FileManager.default.removeItem(at: link)
                }
            } catch {
                Logger.wineKit.warning("Failed to process Start Menu shortcut: \(error.localizedDescription)")
            }
        }

        return startMenuPrograms
    }

    /// Rescans the bottle for installed programs and repopulates ``programs``.
    ///
    /// The expensive work — walking the `Program Files` trees and parsing each
    /// executable's PE header — runs off the main actor so switching to or
    /// opening a large bottle no longer hitches the UI. ``programsLoading`` is
    /// set for the duration so views can show a progress indicator.
    ///
    /// Concurrent callers are coalesced via ``Bottle/coalesceProgramScan(_:)``:
    /// a redundant call awaits the in-flight scan rather than dropping it, so a
    /// caller that reads ``programs`` right after (e.g. the Start Menu auto-pin)
    /// sees that scan's completed results instead of a half-populated or empty
    /// list.
    @MainActor
    func updateInstalledPrograms() async {
        await coalesceProgramScan { [self] in
            programsLoading = true
            defer { programsLoading = false }

            let driveC = url.appending(path: "drive_c")
            // Snapshot main-actor state before crossing to the background task.
            let blocklist = Set(settings.blocklist)

            // Walk Program Files and parse each PE off the main actor (PEFile is Sendable).
            let scanned: [(url: URL, peFile: PEFile?)] = await Task.detached(priority: .userInitiated) {
                Bottle.discoverInstalledExecutables(driveC: driveC, blocklist: blocklist)
                    .map { (url: $0, peFile: try? PEFile(url: $0)) }
            }.value

            var foundURLS: Set<URL> = []
            var programs: [Program] = []
            for entry in scanned {
                foundURLS.insert(entry.url)
                programs.append(Program(url: entry.url, bottle: self, peFile: entry.peFile))
            }

            // Detect ClickOnce applications (small scan, kept on the main actor).
            let clickOnceApps = ClickOnceManager.shared.detectAppRefFile(in: self, wineUsername: wineUsername)
            for appRefURL in clickOnceApps {
                let displayName = ClickOnceManager.shared.displayName(for: appRefURL)
                let program = Program(appRefURL: appRefURL, bottle: self, displayName: displayName)
                programs.append(program)
            }

            // Add missing programs from pins
            for pin in settings.pins {
                guard let url = pin.url else { continue }
                guard !foundURLS.contains(url) else { continue }
                programs.append(Program(url: url, bottle: self))
            }

            self.programs = programs.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
    }

    @MainActor
    func remove(delete: Bool) async {
        // Check for running processes before deletion
        let isRunning = await Wine.isWineserverRunning(for: self)
        let trackedCount = ProcessRegistry.shared.getProcessCount(for: self)

        if isRunning || trackedCount > 0 {
            let alert = NSAlert()
            alert.messageText = String(localized: "bottle.remove.hasProcesses.title")
            alert.informativeText = String(localized: "bottle.remove.hasProcesses.message")
            alert.alertStyle = .warning
            let stopAndRemove = alert.addButton(
                withTitle: String(localized: "bottle.remove.hasProcesses.stopAndRemove")
            )
            stopAndRemove.hasDestructiveAction = true
            alert.addButton(withTitle: String(localized: "bottle.remove.hasProcesses.cancel"))

            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }

            Wine.killBottle(bottle: self)
            try? await Task.sleep(for: .seconds(2))
            ProcessRegistry.shared.clearRegistry(for: url)
        }

        BottleOperations.remove(bottleAt: url, deleteFiles: delete, registry: BottleVM.shared)
    }

}

extension Program {
    /// A launch from a click: counts the attempt and launches, in Terminal when
    /// `useTerminal`. That defaults to Shift, read at the call, before anything
    /// async, so it is the key state of the click.
    @MainActor
    func launchFromUI(
        useTerminal: Bool = NSEvent.modifierFlags.contains(.shift),
        completion: @escaping @MainActor (LaunchResult) -> Void
    ) {
        Telemetry.capture(.firstProgramLaunchAttempted)
        Task {
            completion(await launchWithUserMode(useTerminal: useTerminal))
        }
    }
}

extension TerminalApp {
    /// Has the preferred terminal `source` `script`, written to a temp `.sh`
    /// tracked for cleanup. Throws when the script can't be written; an
    /// AppleScript failure is shown as the run-error alert naming `subject`.
    @discardableResult
    static func runScript(_ script: String, namePrefix: String, subject: String) async throws -> URL {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(namePrefix)-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        TempFileTracker.shared.register(file: scriptURL)

        var error: NSDictionary?
        NSAppleScript(source: preferred.generateAppleScript(for: scriptURL.path))?.executeAndReturnError(&error)
        if let error {
            Logger.wineKit.error("Failed to run terminal script \(error)")
            if let description = error["NSAppleScriptErrorMessage"] as? String {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = String(localized: "alert.message")
                    alert.informativeText = String(localized: "alert.info") + " \(subject): " + description
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: String(localized: "button.ok"))
                    alert.runModal()
                }
            }
        }
        return scriptURL
    }
}

// MARK: - BottleRegistry Conformance

/// Bridges `BottleOperations` to the app's bottle list. The `loadBottles()`
/// requirement is satisfied by the existing method on `BottleVM`.
extension BottleVM: BottleRegistry {
    var bottlePaths: [URL] {
        get { bottlesList.paths }
        set { bottlesList.paths = newValue }
    }

    func bottle(for url: URL) -> Bottle? {
        bottles.first(where: { $0.url == url })
    }
}
