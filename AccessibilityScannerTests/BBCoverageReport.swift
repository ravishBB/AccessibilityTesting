//
//  BBCoverageReport.swift
//  AccessibilityScannerTests
//

import Testing
import Foundation
import CoreGraphics
@testable import AccessibilityScanner

@MainActor
@Suite("BB coverage")
struct BBCoverageReport {

    static let producible: [String: [RuleResultStatus]] = [
        "accessible-name": [.fail, .pass],
        "adjustable-accessibility-value": [.fail, .pass, .validate],
        "button-disabled-state": [.pass],
        "button-name-descriptive": [.fail, .pass, .validate],
        "contrast-large-text-3": [.fail, .pass, .validate, .notTested],
        "contrast-standard-text-4-5": [.fail, .pass, .validate, .notTested],
        "contrast-text-over-image": [.fail, .pass, .validate, .notTested],
        "decorative-image": [.validate],
        "duplicate-interactive-name": [.fail],
        "error-message-accessibility": [.pass, .warning],
        "error-message-suggestion": [.pass, .warning],
        "focus-indicator": [.pass, .fail],
        "focus-order": [.pass, .warning],
        "form-border-contrast": [.fail, .pass, .validate],
        "form-visual-label": [.pass, .validate, .fail],
        "heading-quality": [.fail, .pass, .validate],
        "heading-candidate": [.validate],
        "missing-role": [.fail],
        "name-via-hint": [.fail],
        "label-in-name": [.fail, .pass, .warning],
        "focus-indicator-contrast": [.pass, .fail],
        "focus-not-obscured": [.validate],
        "touch-up-cancellation": [.pass, .fail],
        "complex-gesture-alternative": [.pass],
        "modal-closable": [.pass, .validate],
        "live-region": [.pass, .warning],
        "image-accessible-label": [.fail, .pass],
        "image-button-name": [.fail],
        "image-name-descriptive": [.fail, .validate],
        "interactive-name-descriptive": [.fail, .pass],
        "interactive-screen-reader-hidden": [.fail, .pass, .validate],
        "keyboard-activation": [.pass, .fail, .validate],
        "keyboard-focus": [.pass, .fail],
        "keyboard-focus-context-change": [.pass, .fail],
        "keyboard-focus-hidden-content": [.pass, .fail],
        "keyboard-focus-noninteractive": [.pass, .warning],
        "link-color-differentiation": [.fail, .pass, .validate],
        "loading-indicator-contrast": [.fail, .pass, .validate],
        "map-text-alternative": [.fail, .pass, .validate],
        "modal-accessibility": [.pass, .fail],
        "modal-focus-containment": [.pass, .fail],
        "non-text-contrast": [.fail, .pass, .validate, .warning],
        "orientation-support": [.pass, .warning, .fail],
        "placeholder-only-name": [.fail],
        "reading-order": [.pass, .warning, .notTested],
        "role-trait-consistency": [.fail, .pass, .warning],
        "screen-reader-content": [.fail, .pass, .validate],
        "screen-reader-focus-order": [.validate],
        "screen-title": [.fail, .pass],
        "form-autocomplete": [.pass, .warning],
        "segmented-control-interactive": [.validate],
        "state-trait-consistency": [.fail, .pass, .warning],
        "state-updates-after-interaction": [.pass, .fail],
        "tab-accessibility": [.validate],
        "text-button-role": [.pass, .warning],
        "text-clipping": [.fail, .pass],
        "text-truncation": [.pass, .fail, .notTested],
        "icon-control-role": [.validate],
        "row-role": [.validate, .fail],
        "motion-alternative": [.validate, .notTested],
        "language-change": [.validate],
        "text-overlap": [.pass, .fail, .notTested],
        "focus-indicator-color-only": [.pass, .fail],
        "text-in-image": [.validate],
        "image-role": [.validate],
        "list-items-navigable": [.validate],
        "text-link-role": [.pass, .warning],
        "text-resize": [.pass, .fail, .validate],
        "text-spacing": [.validate],
        "time-limited-ui": [.validate],
        "touch-target-size-24": [.fail, .pass]
    ]

    @Test func producibleIDs() throws {
        let nodes: [AccessibilityNode] = [
            makeNode(type: "XCUIElementTypeButton", label: ""),
            makeNode(type: "XCUIElementTypeButton", label: "Save"),
            makeNode(type: "XCUIElementTypeLink", label: "Terms"),
            makeNode(type: "XCUIElementTypeSwitch", label: "Wi-Fi"),
            makeNode(type: "XCUIElementTypeSegmentedControl", label: ""),
            makeNode(type: "XCUIElementTypeTextField", label: ""),
            makeNode(type: "XCUIElementTypeStaticText", label: "Body", frame: CGRect(x: 0, y: 0, width: 120, height: 15)),
            makeNode(type: "XCUIElementTypeStaticText", label: "Title", frame: CGRect(x: 0, y: 0, width: 300, height: 34))
        ]
        var produced: [String: Set<String>] = [:]
        for (rule, statuses) in Self.producible {
            for status in statuses {
                for node in nodes {
                    for message in [
                        "",
                        "The screen is locked in one orientation.",
                        "Image segmented control has no accessible name.",
                        "The modal has no keyboard-focusable interactive controls, so keyboard users cannot act on it or close it."
                    ] {
                        let evaluation = makeEvaluation(ruleID: rule, status: status, node: node, message: message)
                        if let id = BBIssueCatalog.issue(for: evaluation)?.id {
                            produced[id, default: []].insert("\(rule):\(status.rawValue)")
                        }
                        if let id = BBIssueCatalog.ifConfirmed(for: evaluation)?.id {
                            produced[id, default: []].insert("\(rule):\(status.rawValue) if confirmed")
                        }
                    }
                }
            }
        }
        #expect(!produced.isEmpty)

        // Every BB ID the ruleset says the scanner checks must be producible.
        for rule in BBRuleset.rules {
            let claimed: Set<BBCapability> = [.automated, .runtime, .partial]
            guard claimed.contains(rule.ios) || claimed.contains(rule.android),
                  rule.level.uppercased() != "AAA" else { continue }
            let producedHere = produced[rule.id] != nil || rule.coveredBy.contains { produced[$0] != nil }
            #expect(producedHere, "\(rule.id) is marked as checked but no rule produces it")
        }

        if let path = ProcessInfo.processInfo.environment["BB_COVERAGE_OUT"] {
            let lines = produced.keys.sorted().map { "\($0)\t\(produced[$0]!.sorted().joined(separator: ","))" }
            try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// Every result carries a BB code whose sheet Type is the result's own
    /// status: a Fail result never shows a Validate code, a Validate result
    /// never shows a Fail code.
    @Test func resultStatusMatchesSheetType() {
        let types = Dictionary(BBRuleset.rules.map { ($0.id, $0.type) }, uniquingKeysWith: { first, _ in first })
        let nodes = [makeNode(label: ""), makeNode(label: "Name"), makeNode(type: "XCUIElementTypeLink", label: "x"),
                     makeNode(type: "XCUIElementTypeStaticText", label: "Body", frame: CGRect(x: 0, y: 0, width: 300, height: 40)),
                     makeNode(type: "XCUIElementTypeSegmentedControl", label: "")]
        let messages = ["", "The screen is locked in one orientation.", "Image segmented control has no accessible name.",
                        "The modal has no keyboard-focusable interactive controls, so keyboard users cannot act on it or close it."]
        var mismatches: [String] = []
        for (rule, statuses) in Self.producible {
            for status in statuses where status != .notTested {
                for node in nodes {
                    for message in messages {
                        let evaluation = makeEvaluation(ruleID: rule, status: status, node: node, message: message)
                        // BB40034 is both a Pass row and a Fail row in the sheet.
                        guard let id = BBIssueCatalog.issue(for: evaluation)?.id, id != "BB40034", let type = types[id] else { continue }
                        let expected: BBRuleType = evaluation.status == .pass ? .pass : evaluation.status == .validate ? .validate : .fail
                        if type != expected { mismatches.append("\(rule):\(evaluation.status.rawValue) -> \(id) (\(type.rawValue))") }
                    }
                }
            }
        }
        #expect(Set(mismatches).isEmpty, "\(Set(mismatches).sorted())")
    }
}
