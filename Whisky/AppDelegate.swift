//
//  AppDelegate.swift
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

import Foundation
import os
import SwiftUI
import WhiskyKit

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "AppDelegate")

class AppDelegate: NSObject, NSApplicationDelegate {
    @AppStorage("hasShownMoveToApplicationsAlert") private var hasShownMoveToApplicationsAlert = false

    func application(_ application: NSApplication, open urls: [URL]) {
        // Test if automatic window tabbing is enabled
        // as it is disabled when ContentView appears
        if NSWindow.allowsAutomaticWindowTabbing, let url = urls.first {
            // Reopen the file after Whisky has been opened
            // so that the `onOpenURL` handler is actually called
            NSWorkspace.shared.open(url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !hasShownMoveToApplicationsAlert, !AppDelegate.insideAppsFolder {
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                NSApp.activate(ignoringOtherApps: true)
                self.showAlertOnFirstLaunch()
                self.hasShownMoveToApplicationsAlert = true
            }
        }

        // Background cleanup of orphaned temp files from previous sessions
        Task.detached {
            await TempFileTracker.shared.cleanupOldFiles(olderThan: 24 * 60 * 60)
        }

        // Startup orphan process detection
        // Probe each known bottle's wineserver to detect processes from previous sessions
        Task {
            // Wait for bottles to load (BottleVM needs time to initialize)
            try? await Task.sleep(for: .seconds(2))
            await self.sweepOrphanProcesses()
        }
    }

    /// The "Terminate Wine processes when Whisky closes" setting.
    ///
    /// Read as an optional: the Settings toggle is an `@AppStorage` that
    /// defaults to on without ever writing the key, and `bool(forKey:)`
    /// reports an absent key as off, which silently disabled kill-on-quit
    /// for anyone who never touched the toggle.
    static var killOnTerminate: Bool {
        UserDefaults.standard.object(forKey: "killOnTerminate") as? Bool ?? true
    }

    func applicationWillTerminate(_ notification: Notification) {
        let globalKill = Self.killOnTerminate

        // Per-bottle kill-on-quit with policy overrides
        for bottle in BottleVM.shared.bottles {
            let bottlePolicy = bottle.settings.killOnQuit
            let shouldKill: Bool = switch bottlePolicy {
            case .inherit:
                globalKill
            case .alwaysKill:
                true
            case .neverKill:
                false
            }

            if shouldKill {
                // Synchronous: the app exits when this delegate returns.
                Wine.killBottleAndWait(bottle: bottle)
                ProcessRegistry.shared.clearRegistry(for: bottle.url)
                logger.info(
                    "Killing bottle '\(bottle.settings.name)' on quit (policy: \(String(describing: bottlePolicy)))"
                )
            }
        }

        // Synchronous best-effort temp file cleanup (cannot await in applicationWillTerminate)
        let trackedFiles = TempFileTracker.shared.getAllTrackedFiles()
        for (fileURL, _) in trackedFiles {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // When the user opts into the menu-bar extra, keep Whisky running after
        // the window closes so it stays reachable from the menu bar (and Wine
        // processes keep running). Otherwise quit on last window close, as usual.
        !UserDefaults.standard.bool(forKey: "showMenuBarExtra")
    }

    // MARK: - Dock Menu

    /// The pin behind a Dock menu item.
    private final class DockPin: NSObject {
        let bottleURL: URL
        let pinURL: URL

        init(bottleURL: URL, pinURL: URL) {
            self.bottleURL = bottleURL
            self.pinURL = pinURL
        }
    }

    /// Right-clicking Whisky in the Dock lists the pinned games, launchable
    /// without the main window.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let entries = QuickLaunch.availablePins()
        guard !entries.isEmpty else { return nil }

        let menu = NSMenu()
        let bottleCount = Set(entries.map(\.bottle.url)).count
        for entry in entries.prefix(10) {
            guard let pinURL = entry.pin.url else { continue }
            let title = bottleCount > 1
                ? "\(entry.pin.name) (\(entry.bottle.settings.name))"
                : entry.pin.name
            let item = NSMenuItem(
                title: title, action: #selector(launchDockPin(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = DockPin(bottleURL: entry.bottle.url, pinURL: pinURL)
            menu.addItem(item)
        }
        return menu
    }

    @MainActor @objc private func launchDockPin(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? DockPin,
              let bottle = BottleVM.shared.bottles.first(where: { $0.url == ref.bottleURL }),
              let pin = bottle.settings.pins.first(where: { $0.url == ref.pinURL })
        else { return }
        QuickLaunch.launch(pin: pin, in: bottle)
    }

    private static var appUrl: URL? {
        Bundle.main.resourceURL?.deletingLastPathComponent().deletingLastPathComponent()
    }

    // Named after this bundle: the move replaces whatever sits there, and
    // /Applications/Whisky.app can be the Rosetta build installed next to this one.
    private static let expectedUrl = URL(fileURLWithPath: "/Applications")
        .appending(path: Bundle.main.bundleURL.lastPathComponent)

    private static var insideAppsFolder: Bool {
        if let url = appUrl {
            return url.path.contains("Xcode") || url.path.contains(expectedUrl.path)
        }
        return false
    }

    @MainActor
    private func sweepOrphanProcesses() async {
        for bottle in BottleVM.shared.bottles {
            // The sweep runs 2 s after launch. Only a wineserver that no launch
            // or helper of this app session accounts for is a leftover; one the
            // user just started a program, batch file or winecfg in is not.
            guard await Wine.runState(for: bottle) == .orphaned else { continue }

            // Flagged, never killed: a game started from a shortcut or `whisky run`
            // runs under a wineserver this session did not start, and the sidebar's
            // stop button already offers to end a real leftover.
            let bottleName = bottle.settings.name
            logger.info("Detected orphan Wine processes in bottle '\(bottleName)' (flagged, not auto-cleaned)")
        }
    }

    @MainActor
    private func showAlertOnFirstLaunch() {
        let alert = NSAlert()
        alert.messageText = String(localized: "showAlertOnFirstLaunch.messageText")
        alert.informativeText = String(localized: "showAlertOnFirstLaunch.informativeText")
        alert.addButton(withTitle: String(localized: "showAlertOnFirstLaunch.button.moveToApplications"))
        alert.addButton(withTitle: String(localized: "showAlertOnFirstLaunch.button.dontMove"))

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            let appURL = Bundle.main.bundleURL

            do {
                _ = try FileManager.default.replaceItemAt(AppDelegate.expectedUrl, withItemAt: appURL)
                NSWorkspace.shared.open(AppDelegate.expectedUrl)
            } catch {
                logger.error("Failed to move the app: \(error.localizedDescription)")
            }
        }
    }
}
