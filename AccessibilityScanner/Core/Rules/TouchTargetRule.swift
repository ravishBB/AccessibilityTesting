//
//  TouchTargetRule.swift
//  AccessibilityScannerDemo
//
//  Created by Ravish Kumar on 21/09/26.
//

import Foundation
import CoreGraphics

struct TouchTargetRule: AccessibilityRule {

    let id = "touch-target-size"

    let title = "Touch Target Size"

    let description =
        "Interactive controls should provide a minimum 44×44 point touch target."

    private let minimumSize: CGFloat = 44

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

        let width = node.frame.width
        let height = node.frame.height

        guard width >= minimumSize,
              height >= minimumSize else {

            return AccessibilityRuleEvaluation(
                ruleID: id,
                ruleName: title,
                ruleDescription: description,
                status: .fail,
                severity: .error,
                message:
                    "Interactive element is smaller than 44×44 points.",
                remediation:
                    "Increase the interactive area to at least 44×44 points.",
                node: node
            )
        }

        return AccessibilityRuleEvaluation(
            ruleID: id,
            ruleName: title,
            ruleDescription: description,
            status: .pass,
            severity: .error,
            message:
                "Interactive element meets the minimum touch target size.",
            remediation: "",
            node: node
        )
    }
}
