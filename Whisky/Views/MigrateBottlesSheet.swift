//
//  MigrateBottlesSheet.swift
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

/// Lets the user copy bottles created by the other Whisky apps into new bottles of this
/// build, which runs an arm64 prefix the originals' x86_64 prefixes can't be used as.
/// The originals are only read.
struct MigrateBottlesSheet: View {
    @EnvironmentObject var bottleVM: BottleVM
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [Row] = []
    @State private var didLoad = false

    private struct Row: Identifiable {
        let bottle: LegacyBottleImport.DiscoveredBottle
        var isSelected: Bool
        /// The app the bottle came from is running; its files aren't consistent until it quits.
        let sourceRunning: Bool
        var id: URL {
            bottle.url
        }
    }

    private var selectedCount: Int {
        rows.filter { $0.isSelected && !$0.sourceRunning }.count
    }

    private var allSelected: Bool {
        let available = rows.filter { !$0.sourceRunning }
        return !available.isEmpty && available.allSatisfy(\.isSelected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 460, height: 420)
        .onAppear(perform: loadIfNeeded)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Copy Bottles from Another Whisky")
                .font(.headline)
            Text(
                """
                The selected bottles are copied into new bottles for this build. The originals stay \
                untouched and keep working in the other app. Dependencies installed in the old bottle \
                with winetricks aren't copied. Most programs need none on this engine, and the \
                Microsoft Visual C++ runtime, if installed, is used only by Unity games.
                """
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if rows.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No bottles from another Whisky were found.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach($rows) { $row in
                    Toggle(isOn: $row.isSelected) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.bottle.name)
                            Text(row.bottle.app.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if row.sourceRunning {
                                Text(
                                    """
                                    Quit \(row.bottle.app.displayName) and the programs it started first: \
                                    their files change while they run.
                                    """
                                )
                                .font(.caption)
                                .foregroundStyle(.orange)
                            }
                            Text(row.bottle.url.path(percentEncoded: false))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .disabled(row.sourceRunning)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if !rows.isEmpty {
                Button(allSelected ? "Deselect All" : "Select All", action: toggleAll)
            }
            Spacer()
            Button("button.cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Copy Selected", action: importSelected)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedCount == 0)
        }
        .padding()
    }

    private func toggleAll() {
        let target = !allSelected
        for index in rows.indices where !rows[index].sourceRunning {
            rows[index].isSelected = target
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        rows = LegacyBottleImport
            // `bottles`, not the registry: a bottle still being copied is registered only when it finishes.
            .importableBottles(existingPaths: bottleVM.bottles.map(\.url))
            .filter { !bottleVM.queuedMigrations.contains($0.url) }
            .map {
                let running = LegacyBottleImport.isRunning($0.app)
                return Row(bottle: $0, isSelected: !running, sourceRunning: running)
            }
    }

    private func importSelected() {
        let selected = rows.filter { $0.isSelected && !$0.sourceRunning }.map(\.bottle)
        dismiss()
        Task {
            await bottleVM.migrateLegacyBottles(selected)
        }
    }
}
