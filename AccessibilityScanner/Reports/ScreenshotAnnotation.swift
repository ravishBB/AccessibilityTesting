//
//  ScreenshotAnnotation.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 25/09/26.
//

import Foundation
import CoreGraphics

struct ScreenshotAnnotation: Identifiable, Codable {
    let id: UUID
    let number: Int
    let ruleID: String
    let ruleName: String
    let severity: AccessibilityFinding.Severity
    let message: String
    let remediation: String
    let elementType: String
    let elementLabel: String
    let frameX: Double
    let frameY: Double
    let frameWidth: Double
    let frameHeight: Double

    init(
        number: Int,
        evaluation: AccessibilityRuleEvaluation
    ) {
        self.id = UUID()
        self.number = number
        self.ruleID = evaluation.ruleID
        self.ruleName = evaluation.ruleName
        self.severity = evaluation.severity
        self.message = evaluation.message
        self.remediation = evaluation.remediation
        self.elementType = evaluation.elementType
        self.elementLabel = evaluation.elementLabel
        self.frameX = evaluation.frameX
        self.frameY = evaluation.frameY
        self.frameWidth = evaluation.frameWidth
        self.frameHeight = evaluation.frameHeight
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
