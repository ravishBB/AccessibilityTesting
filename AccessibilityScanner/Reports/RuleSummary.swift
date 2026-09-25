//
//  RuleSummary.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 24/09/26.
//

import Foundation

struct RuleSummary: Identifiable, Codable {

    let id: String

    let ruleID: String
    let ruleName: String

    let severity: AccessibilityFinding.Severity

    let failures: Int
    let warnings: Int
    let validations: Int
    let passes: Int

    init(
        ruleID: String,
        ruleName: String,
        severity: AccessibilityFinding.Severity,
        evaluations: [AccessibilityRuleEvaluation]
    ) {
        self.id = ruleID

        self.ruleID = ruleID
        self.ruleName = ruleName
        self.severity = severity

        self.failures = evaluations.filter {
            $0.status == .fail
        }.count

        self.warnings = evaluations.filter {
            $0.status == .warning
        }.count

        self.validations = evaluations.filter {
            $0.status == .validate
        }.count

        self.passes = evaluations.filter {
            $0.status == .pass
        }.count
    }

    var totalEvaluations: Int {
        failures + warnings + validations + passes
    }
}
