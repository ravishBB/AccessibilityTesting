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
    let intelligence: AccessibilityIntelligence?

    init(
        applicationName: String,
        bundleID: String,
        deviceName: String,
        deviceUDID: String,
        startedAt: Date,
        finishedAt: Date,
        screens: [ScreenScanResult],
        rulesExecuted: Int,
        intelligence: AccessibilityIntelligence? = nil
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
        self.intelligence = intelligence
    }

    init(
        id: UUID,
        applicationName: String,
        bundleID: String,
        deviceName: String,
        deviceUDID: String,
        startedAt: Date,
        finishedAt: Date,
        screens: [ScreenScanResult],
        rulesExecuted: Int,
        intelligence: AccessibilityIntelligence?
    ) {
        self.id = id
        self.applicationName = applicationName
        self.bundleID = bundleID
        self.deviceName = deviceName
        self.deviceUDID = deviceUDID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.screens = screens
        self.rulesExecuted = rulesExecuted
        self.intelligence = intelligence
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

    var resolvedIntelligence: AccessibilityIntelligence {
        intelligence ?? AccessibilityIntelligenceEngine.analyze(report: self)
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
                if $0.failures != $1.failures { return $0.failures > $1.failures }
                if $0.warnings != $1.warnings { return $0.warnings > $1.warnings }
                if $0.validations != $1.validations { return $0.validations > $1.validations }
                return $0.ruleName.localizedCaseInsensitiveCompare(
                    $1.ruleName
                ) == .orderedAscending
            }
    }

    /// Findings grouped by rule with stable fingerprints. Computing this walks
    /// every evaluation, so callers that need it repeatedly should keep the
    /// result instead of re-reading this property.
    var findingGrouping: FindingGrouping {
        FindingGrouping(report: self)
    }
}
