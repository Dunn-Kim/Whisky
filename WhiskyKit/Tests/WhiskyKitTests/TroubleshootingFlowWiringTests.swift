//
//  TroubleshootingFlowWiringTests.swift
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

/// Answers a fixed outcome for its check ID and records the log URL of the
/// preflight snapshot each run saw.
final class ScriptedCheck: TroubleshootingCheck, @unchecked Sendable {
    let checkId: String
    private let outcome: CheckOutcome
    private let evidence: [String: String]
    private let lock = NSLock()
    private var seenLogs: [URL?] = []

    init(_ checkId: String, outcome: CheckOutcome, evidence: [String: String] = [:]) {
        self.checkId = checkId
        self.outcome = outcome
        self.evidence = evidence
    }

    var logURLsSeen: [URL?] {
        lock.withLock { seenLogs }
    }

    func run(params _: [String: String], context: CheckContext) async -> CheckResult {
        lock.withLock { seenLogs.append(context.preflight.recentLogURL) }
        return CheckResult(outcome: outcome, evidence: evidence, summary: "scripted \(outcome.rawValue)")
    }
}

/// Walks the shipped flow definitions through the engine with scripted check
/// outcomes: the transitions the wizard follows after a fix, on the
/// escalation screen, on a fully installed bottle and per launcher.
@MainActor
final class TroubleshootingFlowWiringTests: XCTestCase {
    // MARK: - Fixtures

    private func makeEngine(
        scripted: [String: CheckOutcome] = [:],
        checks: [any TroubleshootingCheck] = [],
        launcherType: String? = nil
    ) -> TroubleshootingFlowEngine {
        let registry = CheckRegistry()
        for (checkId, outcome) in scripted {
            registry.register(ScriptedCheck(checkId, outcome: outcome))
        }
        for check in checks {
            registry.register(check)
        }
        let bottleURL = URL(filePath: "/tmp/flow-wiring-\(UUID().uuidString)")
        var session = TroubleshootingSession(bottleURL: bottleURL)
        session.preflightSnapshot = PreflightData(
            bottleURL: bottleURL,
            bottleName: "Wiring",
            launcherType: launcherType,
            isWineserverRunning: false,
            processCount: 0,
            graphicsBackend: "dxmt"
        )
        return TroubleshootingFlowEngine(
            flowDefinitions: FlowLoader.loadAllFlows(),
            fragments: FlowLoader.loadFragments(),
            checkRegistry: registry,
            sessionStore: SpySessionStore(),
            session: session
        )
    }

    private func waitUntil(
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async {
        for _ in 0 ..< 200 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "timed out waiting for: \(message)", file: file, line: line)
    }

    /// Applies the current node's fix and confirms it landed.
    private func applyCurrentFix(_ engine: TroubleshootingFlowEngine) {
        guard let node = engine.currentNode, let fixId = node.fixId else {
            XCTFail("not on a fix step: \(String(describing: engine.currentNode?.id))")
            return
        }
        engine.applyFix(fixId: fixId, beforeValue: nil, afterValue: nil, params: node.params)
        engine.confirmFixApplied(fixId: fixId)
    }

    // MARK: - Applied fix, verify, retry

    func testAppliedFixLeadsToVerifyAndNotFixedSkipsTheTriedFix() async {
        let engine = makeEngine(scripted: [
            "crash.log_classify": .pass,
            "game.config_available": .pass
        ])
        engine.selectCategory(.graphics)
        await waitUntil("game config fix offered") { engine.currentNode?.id == "suggest_game_config" }

        engine.applyFix(fixId: "apply-game-config", beforeValue: nil, afterValue: nil)
        XCTAssertEqual(engine.currentNode?.id, "suggest_game_config", "the fix step stays up until the fix lands")
        XCTAssertEqual(engine.session.fixAttempts.last?.nodeId, "suggest_game_config")

        engine.confirmFixApplied(fixId: "apply-game-config")
        XCTAssertEqual(engine.currentNode?.id, "verify_fix")
        XCTAssertEqual(engine.session.phase, .verify)

        engine.userReportsNotFixed()
        await waitUntil("escalation") { engine.currentNode?.id == "escalation_summary" }
        XCTAssertEqual(engine.session.failedFixCount, 1)
        XCTAssertEqual(engine.session.fixAttempts.count, 1)
    }

    func testThirdFixThatDidNotHelpEscalates() async {
        let engine = makeEngine(scripted: [
            "crash.log_classify": .pass,
            "game.config_available": .pass
        ])
        // Two earlier fixes that landed and did not help.
        for fixId in ["enable-esync", "enable-controller-compat"] {
            var earlier = FixAttempt(fixId: fixId, result: .failed)
            earlier.wasApplied = true
            engine.session.fixAttempts.append(earlier)
        }
        engine.selectCategory(.graphics)

        await waitUntil("suggest_game_config offered") { engine.currentNode?.id == "suggest_game_config" }
        applyCurrentFix(engine)
        engine.userReportsNotFixed()

        XCTAssertEqual(engine.session.failedFixCount, 3)
        XCTAssertEqual(engine.session.phase, .escalation)
        XCTAssertEqual(engine.currentNode?.id, "escalation_summary")
    }

    func testVerifiedFixResolvesTheSession() async {
        let engine = makeEngine(scripted: ["crash.log_classify": .pass, "game.config_available": .pass])
        engine.selectCategory(.graphics)
        await waitUntil("game config fix offered") { engine.currentNode?.id == "suggest_game_config" }

        applyCurrentFix(engine)
        engine.userReportsFixed()

        XCTAssertEqual(engine.session.outcome, .resolved)
        XCTAssertEqual(engine.session.phase, .export)
        XCTAssertEqual(engine.session.fixAttempts.last?.result, .verified)
    }

    func testFixThatFailedToApplyStaysOnItsStepUntilTheCap() async {
        let engine = makeEngine(scripted: ["crash.log_classify": .pass, "game.config_available": .pass])
        engine.selectCategory(.graphics)
        await waitUntil("game config fix offered") { engine.currentNode?.id == "suggest_game_config" }

        for _ in 1 ... 2 {
            engine.applyFix(fixId: "apply-game-config", beforeValue: nil, afterValue: nil)
            engine.markFixFailed(fixId: "apply-game-config")
            XCTAssertEqual(engine.currentNode?.id, "suggest_game_config")
            XCTAssertEqual(engine.session.phase, .fix)
        }
        engine.applyFix(fixId: "apply-game-config", beforeValue: nil, afterValue: nil)
        engine.markFixFailed(fixId: "apply-game-config")

        XCTAssertEqual(engine.session.phase, .escalation)
    }

    func testFixAttemptKeepsTheParamsItWasAppliedWith() async {
        let engine = makeEngine(scripted: ["registry.value_check": .pass], launcherType: nil)
        engine.selectCategory(.networkDownload)
        await waitUntil("DNS fix offered") { engine.currentNode?.id == "fix_wine_dns" }
        let params = engine.currentNode?.params

        engine.applyFix(fixId: "set-registry-value", beforeValue: "1.1.1.1", afterValue: nil, params: params)

        XCTAssertNotNil(params?["key"])
        XCTAssertEqual(engine.session.fixAttempts.last?.params, params, "undo needs the key and value name back")
    }

    // MARK: - Escalation

    func testEscalationScreenControlsKeepTheSessionEscalated() {
        let engine = makeEngine()
        engine.escalate()
        XCTAssertEqual(engine.currentNode?.id, "escalation_summary")

        XCTAssertFalse(engine.canContinue)
        XCTAssertFalse(engine.canSkip)
        engine.continueStep()
        engine.skipStep()

        XCTAssertEqual(engine.session.phase, .escalation)
        XCTAssertEqual(engine.currentNode?.id, "escalation_summary")
        XCTAssertNil(engine.session.outcome)
    }

    func testExportStepOfAnUnresolvedSessionStaysEscalated() {
        let engine = makeEngine()
        engine.escalate()

        engine.navigateToNode("export_bundle")

        XCTAssertEqual(engine.session.phase, .escalation, "the export phase draws the resolved screen")
    }

    func testGoingBackToTheEscalationSummaryStaysEscalated() {
        let engine = makeEngine()
        engine.escalate()
        engine.applyFix(fixId: "run-enhanced-diagnostics", beforeValue: nil, afterValue: "verbose")
        engine.confirmFixApplied(fixId: "run-enhanced-diagnostics")
        XCTAssertEqual(engine.session.phase, .checks)

        engine.goBack()

        XCTAssertEqual(engine.currentNode?.id, "escalation_summary")
        XCTAssertEqual(engine.session.phase, .escalation)
    }

    func testEnhancedDiagnosticsAnalyzeTheLogOfTheNextLaunch() async {
        let classifier = ScriptedCheck("crash.log_classify", outcome: .fail)
        let engine = makeEngine(checks: [classifier])
        let newLog = URL(filePath: "/tmp/flow-wiring-enhanced.log")
        engine.preflightProvider = {
            PreflightData(
                bottleURL: URL(filePath: "/tmp/flow-wiring"),
                bottleName: "Wiring",
                isWineserverRunning: false,
                processCount: 0,
                recentLogURL: newLog,
                graphicsBackend: "dxmt"
            )
        }
        engine.escalate()

        engine.applyFix(fixId: "run-enhanced-diagnostics", beforeValue: "default", afterValue: "verbose")
        XCTAssertEqual(engine.session.fixAttempts.last?.nodeId, "run_enhanced_diagnostics")
        engine.confirmFixApplied(fixId: "run-enhanced-diagnostics")
        XCTAssertEqual(engine.currentNode?.id, "relaunch_for_enhanced_logs")
        XCTAssertEqual(engine.session.phase, .checks)
        XCTAssertTrue(engine.canContinue)

        engine.continueStep()
        await waitUntil("findings shown") { engine.currentNode?.id == "enhanced_findings" }
        XCTAssertEqual(classifier.logURLsSeen.last, newLog, "the analysis reads the log of the new launch")

        engine.continueStep()
        XCTAssertEqual(engine.currentNode?.id, "export_bundle")
        XCTAssertEqual(engine.session.phase, .escalation)
    }

    // MARK: - All verbs installed

    func testAllVerbsInstalledMovesOnToTheDLLCheck() async {
        let engine = makeEngine(scripted: [
            "winetricks.verb_check": .alreadyConfigured,
            "dependency.check_missing": .pass,
            "game.config_available": .fail
        ])
        engine.selectCategory(.installDependencies)
        await waitUntil("flow finished") { engine.session.phase == .escalation }

        XCTAssertTrue(engine.session.branchDecisions.contains {
            $0.fromNodeId == "check_installed_verbs" && $0.toNodeId == "check_dlls"
        })
    }

    func testAllVerbsInstalledAfterACrashEscalates() async {
        let engine = makeEngine(scripted: [
            "crash.log_classify": .pass,
            "winetricks.verb_check": .alreadyConfigured
        ])
        engine.selectCategory(.launchCrash)
        await waitUntil("flow escalated") { engine.session.phase == .escalation }

        XCTAssertTrue(engine.session.branchDecisions.contains {
            $0.fromNodeId == "check_winetricks" && $0.toNodeId == "escalate"
        })
    }

    // MARK: - Launcher branches

    func testLauncherIssuesBranchOnTheDetectedLauncher() async {
        let expectations: [(LauncherType?, String)] = [
            (.steam, "show_steam_download_info"),
            (.eaApp, "fix_launcher_env"),
            (.epicGames, "fix_launcher_env"),
            (.rockstar, "fix_launcher_env"),
            (.battleNet, "fix_launcher_env")
        ]
        for (launcher, expectedNode) in expectations {
            let engine = makeEngine(
                scripted: ["process.running_check": .pass], launcherType: launcher?.rawValue
            )
            engine.selectCategory(.launcherIssues)
            await waitUntil("\(String(describing: launcher)) routed") { engine.currentNode?.id == expectedNode }
        }
    }

    func testLauncherIssuesWithoutALauncherEscalate() async {
        let engine = makeEngine(launcherType: nil)
        engine.selectCategory(.launcherIssues)

        await waitUntil("escalated") { engine.session.phase == .escalation }
    }

    func testNetworkFlowTakesTheSteamPathOnlyForSteam() async {
        let steam = makeEngine(scripted: ["process.running_check": .fail], launcherType: LauncherType.steam.rawValue)
        steam.selectCategory(.networkDownload)
        await waitUntil("Steam restart offered") { steam.currentNode?.id == "fix_restart_steam" }

        let other = makeEngine(scripted: ["registry.value_check": .pass], launcherType: LauncherType.eaApp.rawValue)
        other.selectCategory(.networkDownload)
        await waitUntil("DNS fix offered") { other.currentNode?.id == "fix_wine_dns" }
        XCTAssertFalse(other.session.stepHistory.contains { $0.nodeId == "check_steam_download" })
    }
}
