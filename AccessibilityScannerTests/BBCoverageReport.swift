//
//  BBCoverageReport.swift
//  AccessibilityScannerTests
//
//  Lists every BB ID the scanner can actually produce, for comparing with the
//  BB sheet. Written to $BB_COVERAGE_OUT when set; otherwise only checked.
//

import Testing
import Foundation
import CoreGraphics
@testable import AccessibilityScanner

@MainActor
@Suite("BB coverage")
struct BBCoverageReport {

    /// Outcomes each rule can really emit, from the static rules and the
    /// runtime probes. Rules that only return Not tested are absent.
    static let producible: [String: [RuleResultStatus]] = [
        "accessible-name": [.fail, .pass],
        "adjustable-accessibility-value": [.fail, .pass, .validate],
        "button-disabled-state": [.pass],
        "button-name-descriptive": [.fail, .pass],
        "contrast-large-text-3": [.fail, .pass, .validate],
        "contrast-large-text-4-5": [.warning, .pass, .validate],
        "contrast-standard-text-4-5": [.fail, .pass, .validate],
        "contrast-standard-text-7": [.warning, .pass, .validate],
        "contrast-text-over-image": [.fail, .pass, .validate],
        "decorative-image": [.validate],
        "duplicate-interactive-name": [.warning],
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
        "image-name-descriptive": [.fail, .pass],
        "interactive-name-descriptive": [.fail, .pass],
        "interactive-screen-reader-hidden": [.fail, .pass, .validate],
        "interactive-target-overlap": [.warning],
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
        "reading-order": [.pass, .warning],
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
        "text-link-role": [.pass, .warning],
        "text-resize": [.pass, .fail, .validate],
        "text-spacing": [.validate],
        "time-limited-ui": [.validate],
        "touch-target-size-24": [.fail, .pass],
        "touch-target-size-44": [.pass, .warning]
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
                    }
                }
            }
        }
        #expect(!produced.isEmpty)

        // Every BB ID the ruleset says the scanner checks must be producible.
        for rule in BBRuleset.rules {
            let claimed: Set<BBCapability> = [.automated, .runtime, .partial]
            guard claimed.contains(rule.ios) || claimed.contains(rule.android) else { continue }
            let producedHere = produced[rule.id] != nil || rule.coveredBy.contains { produced[$0] != nil }
            #expect(producedHere, "\(rule.id) is marked as checked but no rule produces it")
        }

        if let path = ProcessInfo.processInfo.environment["BB_COVERAGE_OUT"] {
            let lines = produced.keys.sorted().map { "\($0)\t\(produced[$0]!.sorted().joined(separator: ","))" }
            try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
