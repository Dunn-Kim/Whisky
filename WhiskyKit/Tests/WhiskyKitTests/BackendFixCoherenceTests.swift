//
//  BackendFixCoherenceTests.swift
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

/// The backend fixes must do what their cards say: the crash diagnosis card that
/// resets to Recommended says so and stays out of the way on a bottle already there.
@MainActor
final class BackendFixCoherenceTests: XCTestCase {
    private var tempDir: URL!
    private var bottle: Bottle!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bottle = Bottle(bottleUrl: tempDir, inFlight: false, isAvailable: true)
    }

    override func tearDownWithError() throws {
        bottle = nil
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
    }

    // MARK: - Guided Troubleshooting

    func testValidatorRejectsSwitchBackendWithoutTargetBackend() {
        func flow(params: [String: String]?) -> FlowDefinition {
            FlowDefinition(
                version: 1,
                categoryId: "test",
                nodes: [
                    "start": FlowStepNode(
                        id: "start", type: .fix, phase: .fix, params: params,
                        on: ["applied": "start"], fixId: "switch-backend"
                    )
                ],
                entryNodeId: "start"
            )
        }

        for params in [nil, ["backend": "not-a-backend"]] as [[String: String]?] {
            let issues = FlowValidator.validate(flows: ["test": flow(params: params)], fragments: [:])
            XCTAssertTrue(
                issues.contains { $0.severity == .error && $0.message.contains("backend") },
                "switch-backend with params \(String(describing: params)) must fail validation, got: \(issues)"
            )
        }

        let valid = FlowValidator.validate(flows: ["test": flow(params: ["backend": "wined3d"])], fragments: [:])
        XCTAssertFalse(valid.contains { $0.message.contains("backend") }, "got: \(valid)")
    }

    // MARK: - Crash diagnosis card

    private func switchBackendRemediation() throws -> RemediationAction {
        let (_, remediations) = PatternLoader.loadDefaults()
        return try XCTUnwrap(remediations["switch-backend"])
    }

    func testSwitchBackendRemediationSaysItResetsToRecommended() throws {
        let action = try switchBackendRemediation()

        XCTAssertEqual(action.targetBackend, .recommended)
        XCTAssertTrue(action.title.contains("Recommended"), action.title)
        XCTAssertTrue(action.whatWillChange.contains("Recommended"), action.whatWillChange)
        XCTAssertFalse(action.description.contains("DXVK"), action.description)
    }

    func testSwitchBackendRemediationIsANoOpOnRecommendedBottle() throws {
        let action = try switchBackendRemediation()

        bottle.settings.graphicsBackend = .recommended
        XCTAssertFalse(action.wouldChange(bottle.settings), "a reset to Recommended changes nothing here")

        for backend in [GraphicsBackend.dxmt, .wined3d] {
            bottle.settings.graphicsBackend = backend
            XCTAssertTrue(action.wouldChange(bottle.settings), "\(backend) should be offered the reset")
        }
    }

    func testNonBackendRemediationsAlwaysApply() {
        let (_, remediations) = PatternLoader.loadDefaults()
        let others = remediations.values.filter { $0.actionType != .switchBackend }
        XCTAssertFalse(others.isEmpty)
        for action in others {
            XCTAssertNil(action.targetBackend, action.id)
            XCTAssertTrue(action.wouldChange(bottle.settings), action.id)
        }
    }
}
