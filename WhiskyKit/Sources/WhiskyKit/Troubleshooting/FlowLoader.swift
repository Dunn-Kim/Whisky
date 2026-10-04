//
//  FlowLoader.swift
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
import os.log

/// Loads troubleshooting flow definitions from bundled JSON resources: one
/// flow file per symptom category plus shared fragments. SPM `.process()`
/// flattens resource directories, so each file loads by its bare name.
public enum FlowLoader {
    private static let logger = Logger(
        subsystem: "com.franke.Whisky",
        category: "FlowLoader"
    )

    /// Loads every symptom category's flow, keyed by category ID (the flow
    /// file name without ".json"). ``SymptomCategory/other`` has no flow by
    /// design: selecting it escalates straight to the export fragment.
    ///
    /// - Returns: A dictionary of flow definitions keyed by category ID.
    public static func loadAllFlows() -> [String: FlowDefinition] {
        var flows: [String: FlowDefinition] = [:]
        for category in SymptomCategory.allCases where category != .other {
            let categoryId = String(category.flowFileName.dropLast(5)) // Remove ".json"
            flows[categoryId] = loadFlow(categoryId)
        }

        logger.debug("Loaded \(flows.count) flow definitions")
        return flows
    }

    /// Loads all shared fragment flow definitions, keyed by resource name
    /// (e.g., "export-escalation").
    public static func loadFragments() -> [String: FlowDefinition] {
        var fragments: [String: FlowDefinition] = [:]
        for name in ["export-escalation"] {
            fragments[name] = loadFlow(name)
        }

        logger.debug("Loaded \(fragments.count) fragment definitions")
        return fragments
    }

    static func loadFlow(_ name: String) -> FlowDefinition? {
        Bundle.module.decodeJSONResource(name) { url in
            try JSONDecoder().decode(FlowDefinition.self, from: Data(contentsOf: url))
        }
    }
}
