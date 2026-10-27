//
//  FlowDefinition.swift
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

/// A complete troubleshooting flow loaded from a JSON resource file.
///
/// Each flow file corresponds to a single symptom category and contains
/// a graph of step nodes the engine traverses. The ``entryNodeId`` identifies
/// the first node to evaluate when the flow begins.
public struct FlowDefinition: Codable, Sendable {
    /// Graph of step nodes keyed by node ID.
    public let nodes: [String: FlowStepNode]

    /// The node ID where execution begins.
    public let entryNodeId: String
}

/// A single step in a troubleshooting flow graph.
///
/// Nodes represent checks, fixes, informational steps, or branch points. The ``on`` dictionary maps normalized
/// outcomes to the next node ID, enabling data-driven branching without hardcoded logic.
public struct FlowStepNode: Codable, Sendable, Identifiable {
    /// Unique identifier within the flow.
    public let id: String

    /// What kind of step this node represents.
    public let type: NodeType

    /// Which wizard phase this step belongs to.
    public let phase: TroubleshootingSession.SessionPhase

    /// Short title displayed in the step card header.
    public var title: String?

    /// Longer explanation displayed in the step card body.
    public var description: String?

    /// Stable check identifier for ``TroubleshootingCheck`` lookup.
    public var checkId: String?

    /// Parameters passed to the check implementation.
    public var params: [String: String]?

    /// Outcome-to-next-node-ID branching map.
    public var on: [String: String]? // swiftlint:disable:this identifier_name

    /// Maps evidence keys to user-facing labels for UI display.
    public var evidenceMap: [String: String]?

    /// Stable fix identifier for fix application.
    public var fixId: String?

    /// Whether an extra confirmation dialog is shown before applying.
    public var requiresConfirmation: Bool?

    /// Reference to a shared fragment flow for delegation.
    public var fragmentRef: String?
}

/// The kind of action a flow step node represents.
public enum NodeType: String, Codable, Sendable {
    /// Runs an automated check via the check registry.
    case check
    /// Applies a fix with preview and confirmation.
    case fix
    /// Displays informational content to the user.
    case info
}
