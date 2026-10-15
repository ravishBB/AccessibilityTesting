//
//  BBIssueCatalogTests.swift
//  AccessibilityScannerTests
//

import Testing
import CoreGraphics
@testable import AccessibilityScanner

@MainActor
@Suite("BB issue mapping")
struct BBIssueCatalogTests {

    private func bb(_ ruleID: String, _ status: RuleResultStatus, _ node: AccessibilityNode, message: String = "") -> String? {
        BBIssueCatalog.issue(for: makeEvaluation(ruleID: ruleID, status: status, node: node, message: message))?.id
    }

    @Test func buttonNameSplitsMissingFromGeneric() {
        #expect(bb("button-name-descriptive", .fail, makeNode(label: "")) == "BB40003")
        #expect(bb("button-name-descriptive", .fail, makeNode(label: "Button")) == "BB40124")
        #expect(bb("button-name-descriptive", .pass, makeNode(label: "Save draft")) == "BB40125")
    }

    @Test func keyboardActivationSplitsByRole() {
        #expect(bb("keyboard-activation", .fail, makeNode(type: "XCUIElementTypeButton", label: "Go")) == "BB41035")
        #expect(bb("keyboard-activation", .fail, makeNode(type: "XCUIElementTypeLink", label: "Terms")) == "BB41067")
    }

    @Test func contrastOverImageUsesLargeTextCodesForLargeText() {
        let standard = makeNode(type: "XCUIElementTypeStaticText", label: "Body copy", frame: CGRect(x: 0, y: 0, width: 120, height: 20))
        let large = makeNode(type: "XCUIElementTypeStaticText", label: "Title", frame: CGRect(x: 0, y: 0, width: 300, height: 34))
        #expect(bb("contrast-text-over-image", .fail, standard) == "BB40018")
        #expect(bb("contrast-text-over-image", .fail, large) == "BB40020")
        #expect(bb("contrast-text-over-image", .validate, large) == "BB40014")
    }

    @Test func orientationLockedVersusMissingContent() {
        let root = makeNode(type: "XCUIElementTypeApplication")
        #expect(bb("orientation-support", .fail, root, message: "The screen is locked in one orientation.") == "BB40056")
        #expect(bb("orientation-support", .fail, root, message: "3 of 10 labels are not exposed") == "BB40055")
    }

    @Test func warningsBecomeValidateWithTheirBBCode() {
        let link = makeNode(type: "XCUIElementTypeStaticText", label: "Privacy link")
        let evaluation = makeEvaluation(ruleID: "text-link-role", status: .warning, node: link)
        #expect(evaluation.status == .validate)
        #expect(BBIssueCatalog.issue(for: evaluation)?.id == "BB40042")
    }

    @Test func placeholderAndTextDisplayShareBB40034() {
        let field = makeNode(type: "XCUIElementTypeTextField")
        let text = makeNode(type: "XCUIElementTypeStaticText", label: "Hello")
        let placeholder = BBIssueCatalog.issue(for: makeEvaluation(ruleID: "placeholder-only-name", status: .fail, node: field))
        let displays = BBIssueCatalog.issue(for: makeEvaluation(ruleID: "text-clipping", status: .pass, node: text))
        #expect(placeholder?.wcag == "3.3.2")
        #expect(placeholder?.title.hasPrefix("Placeholder") == true)
        #expect(displays?.wcag == "1.4.10")
        #expect(displays?.title == "Text displays correctly")
    }

    @Test func notTestedNeverMaps() {
        #expect(bb("keyboard-focus", .notTested, makeNode()) == nil)
        #expect(bb("text-resize", .notTested, makeNode()) == nil)
    }

    @Test func sheetRenumberingIsApplied() {
        // 13 Oct 2026 sheet: enhanced target size is back, state and role
        // codes were renumbered, missing names on other controls got BB30548.
        #expect(bb("state-updates-after-interaction", .fail, makeNode()) == "BB40280")
        #expect(bb("role-trait-consistency", .fail, makeNode()) == "BB40281")
        #expect(bb("state-trait-consistency", .fail, makeNode()) == "BB40069")
        #expect(bb("accessible-name", .fail, makeNode(type: "XCUIElementTypeSwitch")) == "BB30548")
        #expect(bb("keyboard-activation", .fail, makeNode(type: "XCUIElementTypeSwitch")) == "BB40283")
        #expect(bb("placeholder-only-name", .fail, makeNode(type: "XCUIElementTypeTextField")) == "BB40034")
        #expect(bb("time-limited-ui", .validate, makeNode()) == nil)
    }

    @Test func everyMappedIDHasATitle() {
        let rules = AccessibilityRules.all.map(\.id)
        let statuses: [RuleResultStatus] = [.pass, .fail, .warning, .validate]
        let nodes = [makeNode(label: ""), makeNode(label: "Name"), makeNode(type: "XCUIElementTypeLink", label: "x")]
        for rule in rules {
            for status in statuses {
                for node in nodes {
                    if let issue = BBIssueCatalog.issue(for: makeEvaluation(ruleID: rule, status: status, node: node)) {
                        #expect(issue.title != issue.id, "\(issue.id) has no title")
                        #expect(issue.wcag != nil || issue.id == "BB40307", "\(issue.id) has no WCAG criterion")
                    }
                }
            }
        }
    }
}
