//
//  DLLOverrideEditor.swift
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

/// Reusable DLL override table editor for the user's custom entries.
///
/// Used at both bottle and program levels.
struct DLLOverrideEditor: View {
    /// Custom overrides (editable by the user).
    @Binding var customOverrides: [DLLOverrideEntry]

    @State private var newDLLName: String = ""
    @State private var newDLLMode: DLLOverrideMode = .nativeThenBuiltin

    var body: some View {
        customSection
        addRow
    }

    // MARK: - Custom Overrides Section

    @ViewBuilder
    private var customSection: some View {
        if !customOverrides.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("config.dllOverrides.custom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(customOverrides.enumerated()), id: \.element.dllName) { index, entry in
                    HStack {
                        Text(entry.dllName)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Picker("", selection: modeBinding(at: index)) {
                            ForEach(DLLOverrideMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        Button {
                            customOverrides.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Add Row

    private var addRow: some View {
        HStack {
            TextField("config.dllOverrides.placeholder", text: $newDLLName)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 120)
                .onChange(of: newDLLName) {
                    // Strip .dll suffix if the user types it
                    if newDLLName.lowercased().hasSuffix(".dll") {
                        newDLLName = String(newDLLName.dropLast(4))
                    }
                }
            Picker("", selection: $newDLLMode) {
                ForEach(DLLOverrideMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 200)
            Button {
                addEntry()
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .disabled(newDLLName.trimmingCharacters(in: .whitespaces).isEmpty || entryExists(newDLLName))
        }
    }

    // MARK: - Helpers

    private func modeBinding(at index: Int) -> Binding<DLLOverrideMode> {
        Binding(
            get: {
                guard index < customOverrides.count else { return .nativeThenBuiltin }
                return customOverrides[index].mode
            },
            set: { newMode in
                guard index < customOverrides.count else { return }
                let entry = customOverrides[index]
                customOverrides[index] = DLLOverrideEntry(dllName: entry.dllName, mode: newMode)
            }
        )
    }

    private func entryExists(_ name: String) -> Bool {
        let normalizedName = name.lowercased().trimmingCharacters(in: .whitespaces)
        return customOverrides.contains { $0.dllName == normalizedName }
    }

    private func addEntry() {
        let name = newDLLName.lowercased().trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !entryExists(name) else { return }
        customOverrides.append(DLLOverrideEntry(dllName: name, mode: newDLLMode))
        newDLLName = ""
    }
}
