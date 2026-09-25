//
//  AccessibilityScanResult.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 24/09/26.
//

import Foundation

struct AccessibilityScanResult: Identifiable, Codable {

    let id: UUID

    let applicationName: String
    let bundleID: String

    let deviceName: String
    let deviceUDID: String

    let startedAt: Date
    let finishedAt: Date

    let screens: [ScreenScanResult]

    let rulesExecuted: Int

    init(
        applicationName: String,
        bundleID: String,
        deviceName: String,
        deviceUDID: String,
        startedAt: Date,
        finishedAt: Date,
        screens: [ScreenScanResult],
        rulesExecuted: Int
    ) {
        self.id = UUID()

        self.applicationName = applicationName
        self.bundleID = bundleID

        self.deviceName = deviceName
        self.deviceUDID = deviceUDID

        self.startedAt = startedAt
        self.finishedAt = finishedAt

        self.screens = screens
        self.rulesExecuted = rulesExecuted
    }

    var totalElementsTested: Int {
        screens.reduce(0) {
            $0 + $1.elementCount
        }
    }

    var totalFailures: Int {
        screens.reduce(0) {
            $0 + $1.failures
        }
    }

    var totalWarnings: Int {
        screens.reduce(0) {
            $0 + $1.warnings
        }
    }

    var totalValidations: Int {
        screens.reduce(0) {
            $0 + $1.validations
        }
    }

    var totalPasses: Int {
        screens.reduce(0) {
            $0 + $1.passes
        }
    }

    var totalIssues: Int {
        totalFailures + totalWarnings
    }

    var overallStatus: RuleResultStatus {

        if totalFailures > 0 {
            return .fail
        }

        if totalWarnings > 0 {
            return .warning
        }

        if totalValidations > 0 {
            return .validate
        }

        return .pass
    }

    var allEvaluations: [AccessibilityRuleEvaluation] {
        screens.flatMap {
            $0.evaluations
        }
    }

    var issueEvaluations: [AccessibilityRuleEvaluation] {
        allEvaluations.filter {
            $0.status == .fail ||
            $0.status == .warning ||
            $0.status == .validate
        }
    }

    var passEvaluations: [AccessibilityRuleEvaluation] {
        allEvaluations.filter {
            $0.status == .pass
        }
    }

    var ruleSummaries: [RuleSummary] {

        let grouped = Dictionary(
            grouping: allEvaluations,
            by: { $0.ruleID }
        )

        return grouped
            .compactMap { _, evaluations in

                guard let first = evaluations.first else {
                    return nil
                }

                return RuleSummary(
                    ruleID: first.ruleID,
                    ruleName: first.ruleName,
                    severity: first.severity,
                    evaluations: evaluations
                )
            }
            .sorted {
                $0.ruleName.localizedCaseInsensitiveCompare(
                    $1.ruleName
                ) == .orderedAscending
            }
    }
}
