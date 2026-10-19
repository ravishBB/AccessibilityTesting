//
//  TestSupport.swift
//  AccessibilityScannerTests
//

import Foundation
import CoreGraphics
@testable import AccessibilityScanner

@MainActor
func makeNode(
    type: String = "XCUIElementTypeButton",
    label: String = "",
    identifier: String = "",
    frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 44),
    enabled: Bool = true,
    accessible: Bool = true,
    children: [AccessibilityNode] = []
) -> AccessibilityNode {
    AccessibilityNode(
        type: type,
        identifier: identifier,
        label: label,
        value: nil,
        placeholderValue: nil,
        traits: "",
        frame: frame,
        exists: true,
        hittable: true,
        enabled: enabled,
        visible: true,
        accessible: accessible,
        focused: false,
        children: children
    )
}

@MainActor
func makeEvaluation(
    ruleID: String,
    status: RuleResultStatus,
    node: AccessibilityNode,
    message: String = ""
) -> AccessibilityRuleEvaluation {
    AccessibilityRuleEvaluation(
        ruleID: ruleID,
        ruleName: ruleID,
        ruleDescription: "",
        status: status,
        severity: status == .fail ? .error : .warning,
        message: message,
        remediation: "",
        node: node
    )
}
