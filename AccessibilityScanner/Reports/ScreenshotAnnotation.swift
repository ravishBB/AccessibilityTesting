//
//  ScreenshotAnnotation.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 24/09/26.
//

import Foundation
import CoreGraphics

nonisolated struct ScreenshotAnnotation: Identifiable, Codable {
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
    /// nil in reports saved before the screenshot filter existed, which held
    /// failures only.
    let status: RuleResultStatus?
    let bbIssueID: String?
    /// Validate only: the Fail code to log if the tester confirms it.
    var bbIfConfirmedID: String? = nil
    /// The BB sheet's issue text for the code above (status-specific for
    /// BB40034, which is both a Pass and a Fail row).
    var bbIssueTitle: String? = nil

    /// A result about the whole screen (runtime check): listed with the
    /// others but not highlighted on the screenshot. nil in older reports.
    var screenLevel: Bool? = nil

    var isScreenLevel: Bool { screenLevel == true }

    /// The BB sheet's issue text, else the rule name. Codes are not shown.
    var displayTitle: String {
        if let bbIssueTitle { return bbIssueTitle }
        if let id = bbIfConfirmedID, let title = BBIssueCatalog.title(for: id) { return title }
        return ruleName
    }

    /// "Validate: record as a failure if confirmed" for results whose sheet
    /// issue is a failure; nil otherwise.
    var displayDescription: String? {
        bbIssueTitle == nil && bbIfConfirmedID != nil ? "Validate: record as a failure if confirmed" : nil
    }

    var displayStatus: RuleResultStatus { status ?? .fail }

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
        self.status = evaluation.status
        let issue = BBIssueCatalog.issue(for: evaluation)
        self.bbIssueID = issue?.id
        self.bbIssueTitle = issue?.title
        self.bbIfConfirmedID = BBIssueCatalog.ifConfirmed(for: evaluation)?.id
    }

    var frame: CGRect {
        CGRect(
            x: frameX,
            y: frameY,
            width: frameWidth,
            height: frameHeight
        )
    }

    func renumbered(_ newNumber: Int) -> ScreenshotAnnotation {
        return ScreenshotAnnotation(
            id: id,
            number: newNumber,
            ruleID: ruleID,
            ruleName: ruleName,
            severity: severity,
            message: message,
            remediation: remediation,
            elementType: elementType,
            elementLabel: elementLabel,
            frameX: frameX,
            frameY: frameY,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            status: status,
            bbIssueID: bbIssueID,
            bbIfConfirmedID: bbIfConfirmedID,
            bbIssueTitle: bbIssueTitle,
            screenLevel: screenLevel
        )
    }

    private init(
        id: UUID,
        number: Int,
        ruleID: String,
        ruleName: String,
        severity: AccessibilityFinding.Severity,
        message: String,
        remediation: String,
        elementType: String,
        elementLabel: String,
        frameX: Double,
        frameY: Double,
        frameWidth: Double,
        frameHeight: Double,
        status: RuleResultStatus?,
        bbIssueID: String?,
        bbIfConfirmedID: String?,
        bbIssueTitle: String?,
        screenLevel: Bool?
    ) {
        self.id = id
        self.number = number
        self.ruleID = ruleID
        self.ruleName = ruleName
        self.severity = severity
        self.message = message
        self.remediation = remediation
        self.elementType = elementType
        self.elementLabel = elementLabel
        self.frameX = frameX
        self.frameY = frameY
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.status = status
        self.bbIssueID = bbIssueID
        self.bbIfConfirmedID = bbIfConfirmedID
        self.bbIssueTitle = bbIssueTitle
        self.screenLevel = screenLevel
    }

    /// A result about the whole screen (a runtime probe such as larger text,
    /// orientation or keyboard traversal): no single component to mark.
    static func isScreenLevel(_ evaluation: AccessibilityRuleEvaluation) -> Bool {
        evaluation.frameWidth <= 0 || evaluation.frameHeight <= 0 ||
            evaluation.elementType == "hierarchy" || evaluation.elementRole == .application
    }

    // MARK: - Stable Screenshot Ordering

    /// Creates annotations in deterministic visual order for one screenshot.
    ///
    /// The previous implementation used the rule/evaluation array order. That
    /// order can change as rules are added, merged, or evaluated recursively.
    /// Screenshot numbers must instead follow the visual layout:
    /// top-to-bottom, then left-to-right. Exact ties are resolved by rule ID,
    /// rule name, message, and element type so the result remains deterministic.
    /// Whole-screen results as list entries (no highlight), Fail first.
    static func makeScreenLevelAnnotations(
        from evaluations: [AccessibilityRuleEvaluation],
        statuses: Set<RuleResultStatus>
    ) -> [ScreenshotAnnotation] {
        var seen = Set<String>()
        return evaluations
            .filter { statuses.contains($0.status) && isScreenLevel($0) }
            .filter { seen.insert($0.ruleID + "|" + $0.status.rawValue + "|" + $0.message).inserted }
            .enumerated()
            .map { index, evaluation in
                var annotation = ScreenshotAnnotation(number: index + 1, evaluation: evaluation)
                annotation.screenLevel = true
                return annotation
            }
    }

    static func makeAnnotations(
        from evaluations: [AccessibilityRuleEvaluation],
        statuses: Set<RuleResultStatus> = [.fail]
    ) -> [ScreenshotAnnotation] {
        // The annotated screenshot image marks failures only; the report view
        // filters the other statuses on demand. Screen-level checks (the
        // whole hierarchy) have no single component to point at.
        let relevant = evaluations.filter {
            statuses.contains($0.status) && !isScreenLevel($0)
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

/// The report's screenshot filter: the three BB outcomes. Warnings in
/// reports saved before Warning became Validate are shown under Validate.
nonisolated enum ScreenshotCheckFilter: String, CaseIterable, Identifiable, Hashable {
    case fail
    case validate
    case pass

    var id: String { rawValue }

    init(_ status: RuleResultStatus) {
        switch status {
        case .pass: self = .pass
        case .validate, .notTested: self = .validate
        case .fail: self = .fail
        case .warning: self = .validate
        }
    }

    var title: String {
        switch self {
        case .fail: return "Fail"
        case .validate: return "Validate"
        case .pass: return "Pass"
        }
    }
}
