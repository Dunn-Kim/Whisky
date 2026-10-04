//
//  FlowLoaderValidatorTests.swift
//  WhiskyKitTests
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

@testable import WhiskyKit
import XCTest

/// Every fixId `FixApplicator.apply` implements. A flow naming anything else
/// would render a fix card whose Apply button does nothing.
private let knownFixIds: Set<String> = [
    "switch-backend", "enable-dxvk-async", "set-audio-driver",
    "set-buffer-size", "enable-esync", "enable-controller-compat",
    "install-winetricks-verb", "run-enhanced-diagnostics",
    "restart-wineserver", "set-registry-value", "apply-launcher-fixes",
    "apply-game-config"
]

/// Structural errors in flow graphs: a missing entry node, branch targets or
/// fragment refs that resolve nowhere, and fix IDs with no implementation.
private func validationErrors(
    flows: [String: FlowDefinition],
    fragments: [String: FlowDefinition] = [:]
) -> [String] {
    let all = Array(flows) + Array(fragments)
    let allNodeIds = Set(all.flatMap(\.value.nodes.keys))
    var errors: [String] = []
    for (flowId, flow) in all {
        if flow.nodes[flow.entryNodeId] == nil {
            errors.append("\(flowId): entry node '\(flow.entryNodeId)' not found")
        }
        for (nodeId, node) in flow.nodes {
            for target in (node.on ?? [:]).values where !allNodeIds.contains(target) {
                errors.append("\(flowId)/\(nodeId): target '\(target)' not found")
            }
            if let fixId = node.fixId, !knownFixIds.contains(fixId) {
                errors.append("\(flowId)/\(nodeId): fix '\(fixId)' has no implementation")
            }
            if let ref = node.fragmentRef, fragments[ref] == nil {
                errors.append("\(flowId)/\(nodeId): fragment '\(ref)' not found")
            }
        }
    }
    return errors
}

/// Integration tests over the flow JSON actually shipped in the package
/// resources: every flow must load, validate, and reference only checks
/// that exist. These are the tests that catch a broken flow file at CI
/// time instead of at the user's first troubleshooting attempt.
final class FlowLoaderValidatorTests: XCTestCase {
    // MARK: - Bundled resources

    func testEveryCategoryExceptOtherLoadsItsFlow() {
        let flows = FlowLoader.loadAllFlows()

        // Selecting any symptom in the UI must reach a real flow, except
        // .other, which by design has no flow: selecting it escalates
        // directly to the export fragment (the engine's no-flow path).
        for category in SymptomCategory.allCases where category != .other {
            let categoryId = String(category.flowFileName.dropLast(5))
            XCTAssertEqual(
                flows[categoryId]?.categoryId, categoryId,
                "\(category.flowFileName) must load; a silently skipped flow means a dead symptom path"
            )
        }
        XCTAssertEqual(flows.count, SymptomCategory.allCases.count - 1)
    }

    func testFragmentsLoad() {
        let fragments = FlowLoader.loadFragments()

        // The engine's escalation path depends on export-escalation existing.
        XCTAssertNotNil(fragments["export-escalation"])
    }

    func testBundledFlowsPassValidationWithoutErrors() {
        let flows = FlowLoader.loadAllFlows()
        let fragments = FlowLoader.loadFragments()
        XCTAssertFalse(flows.isEmpty)

        let errors = validationErrors(flows: flows, fragments: fragments)

        XCTAssertTrue(errors.isEmpty, "bundled flows have validation errors: \(errors)")
    }

    func testEveryReferencedCheckIdHasAnImplementation() {
        // Collect the checkIds the shipped flows actually reference…
        let flows = FlowLoader.loadAllFlows()
        let fragments = FlowLoader.loadFragments()
        var referenced: Set<String> = []
        for flow in flows.values.map(\.nodes) + fragments.values.map(\.nodes) {
            for node in flow.values {
                if let checkId = node.checkId {
                    referenced.insert(checkId)
                }
            }
        }
        XCTAssertFalse(referenced.isEmpty)

        // …and compare against the concrete implementations the registry
        // registers, without running any of them (several probe hardware).
        let implemented: Set<String> = Set(
            ([
                CrashLogCheck(),
                AudioDriverCheck(), AudioDeviceCheck(),
                DependencyCheck(), WinetricksVerbCheck(),
                LauncherTypeCheck(), ProcessRunningCheck(),
                RegistryValueCheck(),
                GameConfigAvailableCheck(), SettingValueCheck(), DiagnosticsEnhanceCheck()
            ] as [any TroubleshootingCheck]).map(\.checkId)
        )

        let missing = referenced.subtracting(implemented)
        XCTAssertTrue(
            missing.isEmpty,
            "flow JSON references check IDs with no implementation: \(missing.sorted())"
        )
    }

    // MARK: - Validator failure detection

    private func makeNode(
        id: String,
        type: NodeType = .check,
        checkId: String? = "setting.value_check",
        on: [String: String]? = nil // swiftlint:disable:this identifier_name
    ) -> FlowStepNode {
        FlowStepNode(id: id, type: type, phase: .checks, checkId: checkId, on: on)
    }

    func testValidatorFlagsDanglingNodeReference() {
        let flow = FlowDefinition(
            version: 1,
            categoryId: "test",
            nodes: ["start": makeNode(id: "start", on: ["pass": "does-not-exist"])],
            entryNodeId: "start"
        )

        let errors = validationErrors(flows: ["test": flow])

        XCTAssertFalse(errors.isEmpty, "a branch target that resolves nowhere must be a validation error")
    }

    func testValidatorFlagsUnknownFixId() {
        let flow = FlowDefinition(
            version: 1,
            categoryId: "test",
            nodes: [
                "start": FlowStepNode(
                    id: "start", type: .fix, phase: .fix,
                    on: ["applied": "start"], fixId: "not-a-real-fix"
                )
            ],
            entryNodeId: "start"
        )

        let errors = validationErrors(flows: ["test": flow])

        XCTAssertTrue(
            errors.contains { $0.contains("not-a-real-fix") },
            "a fixId with no implementation must fail validation, got: \(errors)"
        )
    }

    func testValidatorFlagsMissingEntryNode() {
        let flow = FlowDefinition(
            version: 1,
            categoryId: "test",
            nodes: ["start": makeNode(id: "start")],
            entryNodeId: "nope"
        )

        XCTAssertFalse(validationErrors(flows: ["test": flow]).isEmpty)
    }

    func testValidatorAcceptsWellFormedFlow() {
        let flow = FlowDefinition(
            version: 1,
            categoryId: "test",
            nodes: [
                "start": makeNode(id: "start", on: ["pass": "done", "fail": "done"]),
                "done": makeNode(id: "done", type: .info, checkId: nil)
            ],
            entryNodeId: "start"
        )

        let errors = validationErrors(flows: ["test": flow])

        XCTAssertTrue(errors.isEmpty, "well-formed flow should have no errors, got: \(errors)")
    }
}
