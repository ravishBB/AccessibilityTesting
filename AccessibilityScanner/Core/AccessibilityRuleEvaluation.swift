//
//  AccessibilityRuleEvaluation.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 24/09/26.
//

import Foundation
import CoreGraphics

struct AccessibilityRuleEvaluation: Identifiable, Codable {

    let id: UUID

    let ruleID: String
    let ruleName: String
    let ruleDescription: String

    let status: RuleResultStatus
    let severity: AccessibilityFinding.Severity

    let message: String
    let remediation: String

    let elementType: String
    let elementRole: AccessibilityRole
    let elementLabel: String
    let identifier: String
    let value: String?

    let frameX: Double
    let frameY: Double
    let frameWidth: Double
    let frameHeight: Double

    init(
        ruleID: String,
        ruleName: String,
        ruleDescription: String,
        status: RuleResultStatus,
        severity: AccessibilityFinding.Severity,
        message: String,
        remediation: String,
        node: AccessibilityNode
    ) {
        self.id = UUID()

        self.ruleID = ruleID
        self.ruleName = ruleName
        self.ruleDescription = ruleDescription

        self.status = status
        self.severity = severity

        self.message = message
        self.remediation = remediation

        self.elementType = node.type
        self.elementRole = node.role
        self.elementLabel = node.label
        self.identifier = node.identifier
        self.value = node.value

        self.frameX = node.frame.origin.x
        self.frameY = node.frame.origin.y
        self.frameWidth = node.frame.width
        self.frameHeight = node.frame.height
    }

    /// Platform the evaluated element was captured on.
    var platform: MobilePlatform {
        MobilePlatform.infer(fromElementType: elementType)
    }

    var frame: CGRect {
        CGRect(
            x: frameX,
            y: frameY,
            width: frameWidth,
            height: frameHeight
        )
    }
}
