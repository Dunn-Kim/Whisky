//
//  Winetricks+Install.swift
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
import WhiskyKit

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "WinetricksInstall")

/// Progress events emitted during a headless winetricks verb installation.
enum WinetricksInstallProgress {
    /// The installation is being prepared (environment setup).
    case preparing
    /// A line of output from the winetricks process.
    case output(String)
    /// The installation completed with the given exit code.
    case completed(exitCode: Int32)
    /// The installation failed with an error message.
    case failed(String)
}

// MARK: - Headless Verb Installation

extension Winetricks {
    /// Installs a single winetricks verb headlessly via Process.
    ///
    /// Runs the verb installation as a child process (not via Terminal AppleScript),
    /// streaming stdout and stderr lines as ``WinetricksInstallProgress/output(_:)``
    /// events. This keeps volume access attributed to Whisky rather than Terminal.
    ///
    /// After successful completion, the ``WinetricksVerbCache`` is refreshed
    /// by calling ``loadInstalledVerbs(for:)``.
    ///
    /// - Parameters:
    ///   - verb: The winetricks verb name to install (e.g. "vcrun2019").
    ///   - bottle: The bottle whose prefix to install into.
    ///   - timeout: Maximum time in seconds before the process is terminated.
    ///     Defaults to 600 seconds (10 minutes).
    /// - Returns: An ``AsyncStream`` of progress events.
    static func installVerb(
        _ verb: String,
        for bottle: Bottle,
        timeout: TimeInterval = 600
    ) -> AsyncStream<WinetricksInstallProgress> {
        AsyncStream { continuation in
            let task = Task {
                await executeVerbInstall(verb, for: bottle, timeout: timeout, continuation: continuation)
            }
            // A consumer that stops iterating (the install sheet's Cancel)
            // cancels the install rather than leaving it running headless.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Installs a single winetricks verb and waits for it to finish.
    ///
    /// - Returns: `nil` on success, otherwise the failure detail: the error
    ///   message, or `exit <code>` for a nonzero exit.
    static func install(_ verb: String, for bottle: Bottle) async -> String? {
        var exitCode: Int32?
        var failure: String?
        for await progress in installVerb(verb, for: bottle) {
            switch progress {
            case let .completed(code): exitCode = code
            case let .failed(message): failure = message
            case .preparing, .output: break
            }
        }
        if failure == nil, exitCode == 0 {
            return nil
        }
        return failure ?? "exit \(exitCode ?? -1)"
    }

    /// Installs multiple winetricks verbs sequentially with per-verb progress.
    ///
    /// Verbs are installed one at a time in the order given. A failure in
    /// one verb does not prevent subsequent verbs from being attempted.
    ///
    /// - Parameters:
    ///   - verbs: The winetricks verb names to install.
    ///   - bottle: The bottle whose prefix to install into.
    /// - Returns: An ``AsyncStream`` of tuples pairing the current verb
    ///   name with its progress event.
    static func installVerbs(
        _ verbs: [String],
        for bottle: Bottle
    ) -> AsyncStream<(verb: String, progress: WinetricksInstallProgress)> {
        AsyncStream { continuation in
            let task = Task {
                for verb in verbs where !Task.isCancelled {
                    for await progress in installVerb(verb, for: bottle) {
                        continuation.yield((verb: verb, progress: progress))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    /// Configures and returns a Process running the bundled winetricks with
    /// `arguments` against the prefix at `bottleURL`.
    static func winetricksProcess(
        arguments: [String],
        bottleURL: URL,
        resourcesURL: URL
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let winetricksPath = resourcesURL.appending(path: "winetricks").path(percentEncoded: false)
        process.arguments = ["bash", winetricksPath] + arguments
        process.environment = [
            "WINEPREFIX": bottleURL.path(percentEncoded: false),
            "WINE": "wine64",
            "PATH": [
                WhiskyWineInstaller.binFolder.path(percentEncoded: false),
                resourcesURL.path(percentEncoded: false),
                "/usr/bin",
                "/bin"
            ].joined(separator: ":"),
            "HOME": NSHomeDirectory()
        ]
        return process
    }

    /// Attaches readability handlers that forward pipe output as progress events.
    private static func attachOutputHandlers(
        stdout: Pipe,
        stderr: Pipe,
        continuation: AsyncStream<WinetricksInstallProgress>.Continuation
    ) {
        let handler: @Sendable (FileHandle) -> Void = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let line = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty
            else { return }
            continuation.yield(.output(line))
        }
        stdout.fileHandleForReading.readabilityHandler = handler
        stderr.fileHandleForReading.readabilityHandler = handler
    }

    /// Executes the verb installation process with timeout and cache refresh.
    private static func executeVerbInstall(
        _ verb: String,
        for bottle: Bottle,
        timeout: TimeInterval,
        continuation: AsyncStream<WinetricksInstallProgress>.Continuation
    ) async {
        continuation.yield(.preparing)

        let bottleURL = await MainActor.run { bottle.url }

        guard let resourcesURL = bundledResourcesURL else {
            logger.warning("Could not locate cabextract resource for winetricks install")
            continuation.yield(.failed("Missing cabextract resource"))
            continuation.finish()
            return
        }

        // The vcrun verbs are passed `--force`: Microsoft rotates the vc_redist
        // binaries in place, so the checksums pinned in the bundled winetricks go
        // stale between releases and the unattended install aborts with exit 1 on
        // the SHA256 mismatch (winetricks#2195).
        //
        // They also get `-q` (W_OPT_UNATTENDED, adds `/q` to the redist install):
        // without it the vc_redist installer shows its wizard and waits for a
        // click nothing in the panel prompts for, so the process never exits and
        // the winetricks.log entry is never written. Scoped to the vcrun verbs
        // until other verbs are checked for unattended behavior.
        let arguments = verb.hasPrefix("vcrun") ? ["--force", "-q", verb] : [verb]
        let process = winetricksProcess(arguments: arguments, bottleURL: bottleURL, resourcesURL: resourcesURL)
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        attachOutputHandlers(stdout: stdoutPipe, stderr: stderrPipe, continuation: continuation)

        do {
            try process.run()
            logger.info("Started winetricks install for verb '\(verb)'")
        } catch {
            logger.error("Failed to launch winetricks install: \(error.localizedDescription)")
            continuation.yield(.failed(error.localizedDescription))
            continuation.finish()
            return
        }

        await withTaskCancellationHandler {
            await awaitProcessCompletion(process, timeout: timeout) {
                logger.warning("winetricks install '\(verb)' timed out after \(Int(timeout)) seconds")
            }
        } onCancel: {
            if process.isRunning {
                logger.info("winetricks install '\(verb)' cancelled, terminating")
                process.terminate()
            }
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let exitCode = process.terminationStatus
        logger.info("winetricks install '\(verb)' exited with status \(exitCode)")
        continuation.yield(.completed(exitCode: exitCode))

        // Refresh the verb cache after installation
        _ = await Winetricks.loadInstalledVerbs(for: bottle)
        continuation.finish()
    }

    /// Waits for the process to exit, terminating it after `timeout` seconds
    /// (calling `onTimeout` first).
    static func awaitProcessCompletion(
        _ process: Process,
        timeout: TimeInterval,
        onTimeout: @escaping @Sendable () -> Void
    ) async {
        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeout))
            if process.isRunning {
                onTimeout()
                process.terminate()
            }
        }
        process.waitUntilExit()
        timeoutTask.cancel()
    }
}
