//
//  AccessibleNameRule.swift
//  AccessibilityScannerDemo
//
//  Created by Ravish Kumar on 21/09/26.

import Foundation

struct AccessibleNameRule: AccessibilityRule {

    let id = "accessible-name"

    let title = "Accessible Name"

    let description =
        "Interactive controls must expose a meaningful accessible name."

    private let interactiveTypes: Set<String> = [
        "XCUIElementTypeButton",
        "XCUIElementTypeTextField",
        "XCUIElementTypeSecureTextField",
        "XCUIElementTypeSlider",
        "XCUIElementTypeSwitch"
    ]

    func evaluate(
        node: AccessibilityNode
    ) -> AccessibilityRuleEvaluation? {

        guard interactiveTypes.contains(node.type) else {
            return nil
        }

        guard node.visible,
              node.enabled else {
            return nil
        }

        let label = node.label.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if label.isEmpty {

            return AccessibilityRuleEvaluation(
                ruleID: id,
                ruleName: title,
                ruleDescription: description,
                status: .fail,
                severity: .error,
                message: "Interactive element has no accessible name.",
                remediation: "Provide a meaningful accessibility label.",
                node: node
            )
        }

        return AccessibilityRuleEvaluation(
            ruleID: id,
            ruleName: title,
            ruleDescription: description,
            status: .pass,
            severity: .error,
            message: "Interactive element has an accessible name.",
            remediation: "",
            node: node
        )
    }
}
