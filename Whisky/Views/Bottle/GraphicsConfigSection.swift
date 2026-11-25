//
//  GraphicsConfigSection.swift
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
import WhiskyKit

struct GraphicsConfigSection: View {
    @ObservedObject var bottle: Bottle
    @AppStorage("graphicsAdvancedMode") private var advancedMode: Bool = false
    @State private var hasRunningProcesses: Bool = false

    private var resolvedBackend: GraphicsBackend {
        if bottle.settings.graphicsBackend == .recommended {
            return GraphicsBackendResolver.resolve()
        }
        return bottle.settings.graphicsBackend
    }

    var body: some View {
        Section("config.title.graphics") {
            // Simple/Advanced segmented control
            Picker("", selection: $advancedMode) {
                Text("config.graphics.simple").tag(false)
                Text("config.graphics.advanced").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Backend picker -- always visible
            BackendPickerView(
                selection: $bottle.settings.graphicsBackend,
                chromiumPrograms: chromiumProgramNames
            )

            chromiumOnExplicitBackendNotice

            // Running process warning banner
            if hasRunningProcesses {
                runningProcessWarning
            }

            frameRateLimitPicker

            dxmtMetalFXToggle

            // The Sequoia compatibility toggle is gone: everything it set is a
            // platform-layer fix applied on every supported macOS, so the
            // switch changed nothing in either position.

            // "Advanced settings active" badge in Simple mode
            if !advancedMode, hasAdvancedSettingsConfigured {
                advancedSettingsBadge
            }

            // Per-program override note in Simple mode
            if !advancedMode, !programsWithGraphicsOverrides.isEmpty {
                programOverridesBadge
            }

            // Advanced mode content
            if advancedMode {
                // Metal settings subsection
                VStack(alignment: .leading, spacing: 8) {
                    Text("config.metal.title")
                        .font(.headline)
                    Toggle(isOn: $bottle.settings.metalHud) {
                        Text("config.metalHud")
                    }
                    Toggle(isOn: $bottle.settings.metalTrace) {
                        Text("config.metalTrace")
                        Text("config.metalTrace.info")
                    }
                    Toggle(isOn: $bottle.settings.metalValidation) {
                        Text("config.metalValidation")
                    }
                }

                // Per-program override info
                if !programsWithGraphicsOverrides.isEmpty {
                    programOverridesInfo
                }
            }
        }
        .animation(.default, value: advancedMode)
        .task {
            await checkRunningProcesses()
        }
    }

    // MARK: - Running Process Warning

    private var runningProcessWarning: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
            Text("config.graphics.nextLaunchInfo")
                .font(.caption)
            Spacer()
            Button("config.graphics.stopBottle") {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = String(
                    localized: "config.graphics.stopBottle.confirm.title", defaultValue: "Stop this bottle?"
                )
                alert.informativeText = String(
                    localized: "config.graphics.stopBottle.confirm.body",
                    defaultValue: "This closes every program running in this bottle without saving."
                )
                alert.addButton(withTitle: String(localized: "config.graphics.stopBottle")).hasDestructiveAction = true
                alert.addButton(withTitle: String(localized: "bottle.remove.hasProcesses.cancel"))
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                Wine.killBottle(bottle: bottle)
                Task {
                    // Brief delay for wineserver to stop
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await checkRunningProcesses()
                }
            }
            .font(.caption)
            .foregroundStyle(.red)
        }
        .padding(8)
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Running Process Check

    private func checkRunningProcesses() async {
        let wineserverActive = await Wine.isWineserverRunning(for: bottle)
        let trackedCount = ProcessRegistry.shared.getProcessCount(for: bottle)
        hasRunningProcesses = wineserverActive || trackedCount > 0
    }

    // MARK: - Advanced Settings Badge

    private var hasAdvancedSettingsConfigured: Bool {
        bottle.settings.metalHud
            || bottle.settings.metalTrace
            || bottle.settings.metalValidation
    }

    private var advancedSettingsBadge: some View {
        HStack {
            Image(systemName: "gearshape.2")
                .foregroundStyle(.secondary)
            Text("config.graphics.advancedActive")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("config.graphics.showAdvanced") {
                advancedMode = true
            }
            .font(.caption)
        }
    }

    // MARK: - Per-Program Override Info

    private var programsWithGraphicsOverrides: [Program] {
        bottle.programs.filter { $0.settings.overrides?.graphicsBackend != nil }
    }

    private var programOverridesBadge: some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.secondary)
            Text("config.graphics.programOverridesActive")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("config.graphics.showAdvanced") {
                advancedMode = true
            }
            .font(.caption)
        }
    }

    private var programOverridesInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("config.graphics.programOverrides")
                .font(.headline)
            ForEach(programsWithGraphicsOverrides) { program in
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text(program.name)
                        .font(.callout)
                    Spacer()
                    Text(
                        program.settings.overrides?.graphicsBackend?.displayName
                            ?? String(localized: "config.graphics.inherited")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Text("config.graphics.programOverrides.hint")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private extension GraphicsConfigSection {
    var frameRateLimitPicker: some View {
        // Frame rate cap -- always visible. Uncapped rendering is the single
        // biggest avoidable source of GPU power draw and heat.
        VStack(alignment: .leading, spacing: 4) {
            FrameRateLimitPicker(limit: $bottle.settings.frameRateLimit, backend: resolvedBackend)
            Text(
                resolvedBackend.supportsFrameRateLimit
                    ? "config.frameRateLimit.info" as LocalizedStringKey : "config.frameRateLimit.unsupported"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var dxmtMetalFXToggle: some View {
        if resolvedBackend == .dxmt {
            Toggle(isOn: $bottle.settings.dxmtMetalFXUpscale) {
                VStack(alignment: .leading) {
                    Text("config.dxmtMetalFXUpscale")
                    Text("config.dxmtMetalFXUpscale.info")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Chromium Programs

extension GraphicsConfigSection {
    /// The launchers, Chromium front ends, and Electron and NW.js apps among
    /// the bottle's programs, by name, each once: the programs Recommended
    /// runs on WineD3D (#372). Read from each program's scan, not its files.
    var chromiumProgramNames: [String] {
        var seen = Set<String>()
        return bottle.programs
            .compactMap { program in program.backendSteering?.listedName(executable: program.url) }
            .filter { seen.insert($0).inserted }
    }

    /// Recommended would run these on WineD3D; an explicit DXMT does not.
    @ViewBuilder
    var chromiumOnExplicitBackendNotice: some View {
        let names = chromiumProgramNames
        if bottle.settings.graphicsBackend == .dxmt, !names.isEmpty {
            Text("config.graphics.chromiumOnExplicitBackend \(ListFormatter.localizedString(byJoining: names))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// The frame cap picker, with the warning DXMT needs when the cap does not
/// divide the main display's refresh rate. Shared by the bottle and the
/// program overrides, which must say the same thing.
struct FrameRateLimitPicker: View {
    @Binding var limit: FrameRateLimit
    let backend: GraphicsBackend

    var body: some View {
        Picker("config.frameRateLimit", selection: $limit) {
            ForEach(FrameRateLimit.allCases, id: \.self) { limit in
                Text(limit.label).tag(limit)
            }
        }
        if backend == .dxmt, !limit.pacesEvenly(displayRefreshRate: FrameRateLimit.mainDisplayRefreshRate()) {
            Text("config.frameRateLimit.uneven")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}
