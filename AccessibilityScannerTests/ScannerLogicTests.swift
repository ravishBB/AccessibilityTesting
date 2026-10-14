//
//  ScannerLogicTests.swift
//  AccessibilityScannerTests
//

import Testing
import Foundation
import CoreGraphics
@testable import AccessibilityScanner

@MainActor
@Suite("Text size estimate")
struct TextSizeEstimateTests {

    private func size(_ width: CGFloat, _ height: CGFloat, _ text: String) -> TextSizeClass {
        TextSizeEstimate.classify(frame: CGRect(x: 0, y: 0, width: width, height: height), text: text, role: .staticText)
    }

    private func points(_ width: CGFloat, _ height: CGFloat, _ text: String) -> CGFloat {
        TextSizeEstimate.fontSize(frame: CGRect(x: 0, y: 0, width: width, height: height), text: text) ?? 0
    }

    @Test func singleLineEstimate() {
        // iOS 17pt body text has a line height of about 20.3pt.
        #expect(abs(points(160, 20.3, "Sign in to continue") - 17) < 1)
        // A short label stretched across a full-width frame is still one line.
        #expect(abs(points(343, 20.3, "Sign in to continue") - 17) < 1)
    }

    @Test func wrappedParagraphEstimate() {
        let paragraph = String(repeating: "word ", count: 24)
        #expect(abs(points(343, 61, paragraph) - 17) < 1.5)
    }

    @Test func smallTextIsStandard() {
        // 13pt footnote.
        #expect(size(200, 15.5, "Terms apply") == .standard)
    }

    @Test func bodyTextIsLargeOnlyIfBold() {
        // 14 to 18pt: large only when bold, which the hierarchy cannot tell.
        #expect(size(160, 20.3, "Sign in to continue") == .possiblyLarge)
    }

    @Test func titleIsLarge() {
        #expect(size(200, 34, "Settings") == .large)
    }

    @Test func midSizeIsPossiblyLarge() {
        #expect(size(200, 19, "Subheading") == .possiblyLarge)
    }

    @Test func textFieldsAreAlwaysStandard() {
        let frame = CGRect(x: 0, y: 0, width: 300, height: 44)
        #expect(TextSizeEstimate.classify(frame: frame, text: "Email", role: .textField) == .standard)
    }
}

@MainActor
@Suite("Action safety")
struct ActionSafetyTests {

    private func explore(_ label: String, _ identifier: String = "") -> Bool {
        ActionSafety.isSafeToExplore(makeNode(label: label, identifier: identifier))
    }

    @Test func blocksIrreversibleActions() {
        #expect(!explore("Pay now"))
        #expect(!explore("Confirm transfer"))
        #expect(!explore("Sign Out"))
        #expect(!explore("", "btnTrash"))
        #expect(!explore("Send"))
    }

    @Test func matchesWholeWordsOnly() {
        #expect(explore("Display settings"))
        #expect(explore("Credit card"))
        #expect(explore("Saved items"))
        #expect(explore("Clearance sale"))
    }

    @Test func probesMaySignInButCrawlerMayNot() {
        let signIn = makeNode(label: "Sign in")
        #expect(ActionSafety.isSafeToActivate(signIn))
        #expect(!ActionSafety.isSafeToExplore(signIn))
    }

    @Test func dismissPrefersCancelAndNeverAccepts() {
        let buttons = [makeNode(label: "Submit anyway"), makeNode(label: "Cancel")]
        #expect(ActionSafety.dismissButton(in: buttons)?.label == "Cancel")

        let permission = [makeNode(label: "Allow"), makeNode(label: "Don't Allow")]
        #expect(ActionSafety.dismissButton(in: permission)?.label == "Don't Allow")

        #expect(ActionSafety.dismissButton(in: [makeNode(label: "Delete")]) == nil)
    }
}

@MainActor
@Suite("Scan notes and settings")
struct ScanNotesTests {

    @Test func groupsOccurrencesWithExamples() {
        let notes = ScanNotes()
        notes.record(.tapFailed, example: "Help")
        notes.record(.tapFailed, example: "Share")
        notes.record(.tapFailed, example: "Help")
        #expect(notes.summaries.count == 1)
        #expect(notes.summaries[0].hasPrefix("3 actions could not be tapped"))
        #expect(notes.summaries[0].contains("Help, Share"))
    }

    @Test func emptyWhenNothingWentWrong() {
        #expect(ScanNotes().isEmpty)
        #expect(ScanNotes().summaries.isEmpty)
    }

    @Test func appiumURLValidation() {
        #expect(ScannerSettings.validAppiumURL("http://127.0.0.1:4723") != nil)
        #expect(ScannerSettings.validAppiumURL("https://grid.example.com/wd/hub") != nil)
        #expect(ScannerSettings.validAppiumURL("127.0.0.1:4723") == nil)
        #expect(ScannerSettings.validAppiumURL("") == nil)
    }
}

@Suite("Process runner")
struct ProcessRunnerTests {

    @Test func largeOutputDoesNotDeadlock() throws {
        let output = try ProcessRunner.run(
            "/bin/sh",
            ["-c", "head -c 300000 /dev/zero | tr '\\0' a; head -c 200000 /dev/zero | tr '\\0' b 1>&2"],
            timeout: 20
        )
        #expect(output.status == 0)
        #expect(output.stdout.count == 300_000)
        #expect(output.stderr.count == 200_000)
    }

    @Test func hungCommandIsStopped() {
        let started = Date()
        #expect(throws: ProcessRunner.RunnerError.self) {
            _ = try ProcessRunner.run("/bin/sleep", ["30"], timeout: 1)
        }
        #expect(Date().timeIntervalSince(started) < 10)
    }
}

@MainActor
@Suite("Report building")
struct ReportBuildingTests {

    @Test func mergeReplacesSameElementAndAppendsNew() {
        let button = makeNode(label: "Save")
        let other = makeNode(label: "Help", frame: CGRect(x: 0, y: 100, width: 100, height: 44))
        let base = [makeEvaluation(ruleID: "r", status: .validate, node: button)]
        let additions = [
            makeEvaluation(ruleID: "r", status: .fail, node: button),
            makeEvaluation(ruleID: "r", status: .pass, node: other)
        ]
        let merged = ScreenResultBuilder.mergeEvaluations(base, additions)
        #expect(merged.map(\.status) == [.fail, .pass])
    }

    @Test func consistencyNotesFlagContradictions() {
        let node = makeNode(label: "Save")
        let screen = ScreenScanResult(
            name: "Screen 1",
            signature: "s",
            elementCount: 1,
            evaluations: [
                makeEvaluation(ruleID: "touch-target-size-24", status: .pass, node: node),
                makeEvaluation(ruleID: "touch-target-size-24", status: .fail, node: node)
            ],
            transitions: [],
            screenshot: nil,
            annotations: [],
            viewportScreenshots: []
        )
        let report = AccessibilityScanResult(
            applicationName: "App", bundleID: "a.b", deviceName: "Phone", deviceUDID: "x",
            startedAt: Date(), finishedAt: Date(), screens: [screen], rulesExecuted: 1
        )
        let notes = AccessibilityReportIntegrity.consistencyNotes(report)
        #expect(notes.contains { $0.contains("touch-target-size-24 both passed and failed") })
        #expect(notes.contains { $0.contains("no screenshot") })
    }
}

@Suite("Device discovery")
struct DeviceDiscoveryTests {

    /// Runs against this Mac's simulators; passes trivially where none exist.
    @Test func simulatorsParseFromJSON() throws {
        let devices = try DeviceDiscoveryService().discoverDevices()
        for simulator in devices where simulator.isSimulator {
            #expect(simulator.udid.count == 36, "\(simulator.name) has UDID \(simulator.udid)")
            #expect(!simulator.name.isEmpty)
        }
    }
}

@MainActor
@Suite("Rule availability")
struct RuleAvailabilityTests {

    @Test func platformRuleSetsNameRealRules() {
        let catalogued = Set(AccessibilityRuleCatalog.allMetadata.map(\.ruleID))
        let named = AccessibilityRuleCatalog.notAutomatable
            .union(AccessibilityRuleCatalog.notAutomatableOnIOS)
            .union(AccessibilityRuleCatalog.reviewOnly)
        #expect(named.subtracting(catalogued).isEmpty, "Unknown rule IDs: \(named.subtracting(catalogued).sorted())")
    }

    @Test func iOSCountsExcludeRulesThatCannotRun() {
        let total = AccessibilityRuleCatalog.ruleCount
        let iOS = AccessibilityRuleCatalog.verdictCapableRuleCount(on: .ios)
        let android = AccessibilityRuleCatalog.verdictCapableRuleCount(on: .android)
        #expect(iOS == total - AccessibilityRuleCatalog.cannotRun(on: .ios).count - AccessibilityRuleCatalog.reviewOnly.count)
        #expect(android > iOS)
    }
}
