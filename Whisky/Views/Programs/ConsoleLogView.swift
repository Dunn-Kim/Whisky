// swiftlint:disable file_length
//
//  ConsoleLogView.swift
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

import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

/// Displays console log output for a specific run with channel filtering and export actions.
///
/// Log lines are classified into channels: output (stdout), stderr, and WINEDEBUG.
/// Users can toggle visibility of each channel, copy/export filtered content, and
/// open the logs folder. For running processes, the view polls for new content.
struct ConsoleLogView: View {
    let runEntry: RunLogEntry
    let bottle: Bottle

    @State private var logLines: [ConsoleLogLine] = []
    @State private var showOutput = true
    @State private var showStderr = true
    @State private var showWineDebug = false
    @State private var currentExitCode: Int32?
    @State private var isStillRunning: Bool = false
    @State private var logFollower: WineLogFollower?
    @State private var refreshTimer: Timer?

    /// Regex patterns that indicate WINEDEBUG output.
    private static let wineDebugPrefixes = ["wine:", "fixme:", "err:", "trace:", "warn:"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logHeader
            channelFilterBar
            logContentView
            logFooter
            actionBar
        }
        .onAppear { loadLog() }
        .onDisappear { stopRefreshTimer() }
        .task {
            isStillRunning = runEntry.isRunning
            currentExitCode = runEntry.exitCode
            if runEntry.isRunning {
                startRefreshTimer()
            }
        }
    }

    // MARK: - Header

    private var logHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(runEntry.programName)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text(runEntry.startTime, style: .date)
                        + Text(" ")
                        + Text(runEntry.startTime, style: .time)
                    if let duration = runEntry.duration {
                        Text(formattedDuration(duration))
                            .foregroundStyle(.secondary)
                    } else if isStillRunning {
                        Text("console.running")
                            .foregroundStyle(.green)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if isStillRunning {
                liveIndicator
            } else if let exitCode = currentExitCode {
                exitCodeBadge(exitCode)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Channel Filter Bar

    private var channelFilterBar: some View {
        HStack(spacing: 8) {
            filterToggle(
                label: String(localized: "console.log.filter.stdout"),
                isOn: $showOutput,
                color: .primary
            )
            filterToggle(
                label: String(localized: "console.log.filter.stderr"),
                isOn: $showStderr,
                color: .red
            )
            if runEntry.hasWineDebugOutput {
                filterToggle(
                    label: String(localized: "console.log.filter.winedebug"),
                    isOn: $showWineDebug,
                    color: .gray
                )
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func filterToggle(label: String, isOn: Binding<Bool>, color: Color) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isOn.wrappedValue ? color.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        isOn.wrappedValue ? color.opacity(0.4) : Color.secondary.opacity(0.2),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log Content

    private var logContentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(filteredLines.enumerated()), id: \.offset) { index, line in
                        logLineView(line)
                            .id(index)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: 300)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onChange(of: logLines.count) {
                if isStillRunning, let lastIndex = filteredLines.indices.last {
                    proxy.scrollTo(lastIndex, anchor: .bottom)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func logLineView(_ line: ConsoleLogLine) -> some View {
        Text(line.text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(colorForChannel(line.channel))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func colorForChannel(_ channel: ConsoleLogChannel) -> Color {
        switch channel {
        case .output: .primary
        case .stderr: .red
        case .wineDebug: .gray
        }
    }

    var filteredLines: [ConsoleLogLine] {
        shown(logLines)
    }

    /// The lines of `lines` the channel toggles let through.
    func shown(_ lines: [ConsoleLogLine]) -> [ConsoleLogLine] {
        lines.filter { line in
            switch line.channel {
            case .output: showOutput
            case .stderr: showStderr
            case .wineDebug: showWineDebug
            }
        }
    }

    /// How many lines the view keeps. A log at its 20 MiB cap holds about
    /// 250,000, and every refresh filtered and diffed them all on the main thread.
    /// Copy and export read the whole file.
    private static let maxLines = 5_000

    // MARK: - Footer

    private var logFooter: some View {
        Group {
            if !isStillRunning, let exitCode = currentExitCode {
                HStack {
                    Text("console.exited \(Int(exitCode))")
                        .font(.caption)
                        .foregroundStyle(exitCode == 0 ? .green : .red)
                    Spacer()
                    Text("\(filteredLines.count) / \(logLines.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                copyToClipboard()
            } label: {
                Label("console.log.copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .font(.caption)

            Button {
                exportToFile()
            } label: {
                Label("console.log.export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .font(.caption)

            Button {
                NSWorkspace.shared.open(Wine.logsFolder)
            } label: {
                Label("console.openLogsFolder", systemImage: "folder")
            }
            .buttonStyle(.plain)
            .font(.caption)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Shared Components

    private var liveIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
                .modifier(ConsoleLogPulseModifier())
            Text("console.log.liveIndicator")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    private func exitCodeBadge(_ exitCode: Int32) -> some View {
        Text("console.exitCode \(Int(exitCode))")
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(exitCode == 0 ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
            )
            .foregroundStyle(exitCode == 0 ? .green : .red)
    }
}

// MARK: - ConsoleLogView Data Operations

extension ConsoleLogView {
    func formattedDuration(_ interval: TimeInterval) -> String {
        RunDurationFormatting.string(from: interval)
    }

    func loadLog() {
        let logURL = Wine.logsFolder.appending(path: runEntry.logFileName)
        guard FileManager.default.fileExists(atPath: logURL.path(percentEncoded: false)) else {
            logLines = [ConsoleLogLine(
                text: String(localized: "console.log.fileNotFound"),
                channel: .stderr
            )]
            return
        }

        // One read for the lines and the offset the live tail goes on from.
        var follower = WineLogFollower(logFileURL: logURL, start: .beginning)
        do {
            let chunk = try follower.read()
            guard let content = String(data: chunk.data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            logLines = classifyLines(content, keepingLast: Self.maxLines)
            logFollower = follower
        } catch {
            logLines = [ConsoleLogLine(
                text: String(localized: "console.log.loadError"),
                channel: .stderr
            )]
        }
    }

    func loadNewContent() {
        let logURL = Wine.logsFolder.appending(path: runEntry.logFileName)
        guard FileManager.default.fileExists(atPath: logURL.path(percentEncoded: false)) else { return }

        var follower = logFollower ?? WineLogFollower(logFileURL: logURL, start: .beginning)
        if let chunk = try? follower.read() {
            logFollower = follower
            if chunk.resumedAtMarker {
                // The log reached its size cap and was cut back to its head
                // with the newest output after it; read it again from the top.
                loadLog()
            } else if !chunk.data.isEmpty, let newContent = String(data: chunk.data, encoding: .utf8) {
                logLines.append(contentsOf: classifyLines(newContent, keepingLast: Self.maxLines))
                if logLines.count > Self.maxLines {
                    logLines.removeFirst(logLines.count - Self.maxLines)
                }
            }
        }
        // Read errors are ignored during live tailing; the next tick tries again.

        // Check if the process has exited
        let history = RunLogStore.load(for: runEntry.programName, in: bottle.url)
        if let updated = history.entries.first(where: { $0.id == runEntry.id }), !updated.isRunning {
            isStillRunning = false
            currentExitCode = updated.exitCode
            stopRefreshTimer()
        }
    }

    func classifyLines(_ content: String, keepingLast limit: Int = .max) -> [ConsoleLogLine] {
        content
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .suffix(limit)
            .map { line in
                if isWineDebugLine(line) {
                    ConsoleLogLine(text: line, channel: .wineDebug)
                } else if isStderrLine(line) {
                    ConsoleLogLine(text: line, channel: .stderr)
                } else {
                    ConsoleLogLine(text: line, channel: .output)
                }
            }
    }

    /// A Wine debug line: a thread id (`002c:fixme:…`) or a channel prefix.
    /// Checked without regular expressions, which cost six searches a line.
    func isWineDebugLine(_ line: String) -> Bool {
        let bytes = line.utf8
        let isThreadID = bytes.count > 4
            && bytes.prefix(4).allSatisfy { (48 ... 57).contains($0) || (97 ... 102).contains($0) }
            && bytes.dropFirst(4).first == UInt8(ascii: ":")
        return isThreadID || Self.wineDebugPrefixes.contains { line.hasPrefix($0) }
    }

    /// The whole log, classified, for copy and export: the view keeps only its tail.
    func allLogLines() -> [ConsoleLogLine] {
        let logURL = Wine.logsFolder.appending(path: runEntry.logFileName)
        guard let data = try? Data(contentsOf: logURL), let text = String(bytes: data, encoding: .utf8) else {
            return logLines
        }
        return classifyLines(text)
    }

    func isStderrLine(_ line: String) -> Bool {
        let stderrIndicators = ["Error:", "error:", "FAILED", "fatal:", "FATAL:", "Exception:"]
        return stderrIndicators.contains(where: { line.contains($0) })
    }

    func copyToClipboard() {
        let text = shown(allLogLines()).map(\.text).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func exportToFile() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        let dateFormatter = ISO8601DateFormatter()
        let dateString = dateFormatter.string(from: runEntry.startTime)
        savePanel.nameFieldStringValue = "\(runEntry.programName)-\(dateString).log"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                let lines = allLogLines()
                var exportContent = shown(lines).map(\.text).joined(separator: "\n")
                if runEntry.hasWineDebugOutput, !showWineDebug {
                    let debugLines = lines
                        .filter { $0.channel == .wineDebug }
                        .map(\.text)
                    if !debugLines.isEmpty {
                        exportContent += "\n\n--- WINEDEBUG Output ---\n"
                        exportContent += debugLines.joined(separator: "\n")
                    }
                }
                try exportContent.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // Best-effort export
            }
        }
    }

    func startRefreshTimer() {
        stopRefreshTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                loadNewContent()
            }
        }
    }

    func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Supporting Types

/// A single classified log line with channel attribution.
struct ConsoleLogLine {
    let text: String
    let channel: ConsoleLogChannel
}

/// Channel classification for console output lines.
enum ConsoleLogChannel {
    /// Standard output (stdout) content.
    case output
    /// Standard error (stderr) content.
    case stderr
    /// WINEDEBUG diagnostic output.
    case wineDebug
}

/// Pulse animation modifier for the live streaming indicator.
private struct ConsoleLogPulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}
