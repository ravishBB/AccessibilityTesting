//
//  ScreenshotAnnotation.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 24/09/26.
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

    // MARK: - Stable Screenshot Ordering

    /// Creates annotations in deterministic visual order for one screenshot.
    ///
    /// The previous implementation used the rule/evaluation array order. That
    /// order can change as rules are added, merged, or evaluated recursively.
    /// Screenshot numbers must instead follow the visual layout:
    /// top-to-bottom, then left-to-right. Exact ties are resolved by rule ID,
    /// rule name, message, and element type so the result remains deterministic.
    static func makeAnnotations(
        from evaluations: [AccessibilityRuleEvaluation]
    ) -> [ScreenshotAnnotation] {
        let relevant = evaluations.filter {
            $0.status == .fail ||
            $0.status == .warning ||
            $0.status == .validate
        }

        let sorted = relevant.sorted { lhs, rhs in
            let yDifference = lhs.frameY - rhs.frameY
            if abs(yDifference) > 0.5 {
                return lhs.frameY < rhs.frameY
            }

            let xDifference = lhs.frameX - rhs.frameX
            if abs(xDifference) > 0.5 {
                return lhs.frameX < rhs.frameX
            }

            if lhs.frameHeight != rhs.frameHeight {
                return lhs.frameHeight > rhs.frameHeight
            }

            if lhs.frameWidth != rhs.frameWidth {
                return lhs.frameWidth > rhs.frameWidth
            }

            if lhs.ruleID != rhs.ruleID {
                return lhs.ruleID < rhs.ruleID
            }

            if lhs.ruleName != rhs.ruleName {
                return lhs.ruleName < rhs.ruleName
            }

            if lhs.elementType != rhs.elementType {
                return lhs.elementType < rhs.elementType
            }

            if lhs.elementLabel != rhs.elementLabel {
                return lhs.elementLabel < rhs.elementLabel
            }

            return lhs.message < rhs.message
        }

        return sorted.enumerated().map { index, evaluation in
            ScreenshotAnnotation(
                number: index + 1,
                evaluation: evaluation
            )
        }
    }
}
