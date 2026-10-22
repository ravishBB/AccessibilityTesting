//
//  AccessibilityScanResult.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 24/09/26.
//

import Foundation

nonisolated struct AccessibilityScanResult: Identifiable, Codable {

    let id: UUID

    let applicationName: String
    let bundleID: String

    let deviceName: String
    let deviceUDID: String

    let startedAt: Date
    let finishedAt: Date

    let screens: [ScreenScanResult]

    let rulesExecuted: Int

    /// Device, OS, app and scanner versions. Optional so baselines saved by
    /// earlier versions still decode.
    var environment: ScanEnvironment? = nil

    /// What the scan could not do (failed taps, lost navigation, moving
    /// screens). Optional for the same reason.
    var scanNotes: [String]? = nil

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

    init(
        id: UUID,
        applicationName: String,
        bundleID: String,
        deviceName: String,
        deviceUDID: String,
        startedAt: Date,
        finishedAt: Date,
        screens: [ScreenScanResult],
        rulesExecuted: Int
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

    var totalNotTested: Int {
        screens.reduce(0) { $0 + $1.evaluations.filter { $0.status == .notTested }.count }
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

        if totalNotTested > 0 {
            return .notTested
        }

        return .pass
    }

    var allEvaluations: [AccessibilityRuleEvaluation] {
        screens.flatMap {
            $0.evaluations
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
                if $0.failures != $1.failures { return $0.failures > $1.failures }
                if $0.warnings != $1.warnings { return $0.warnings > $1.warnings }
                if $0.validations != $1.validations { return $0.validations > $1.validations }
                return $0.ruleName.localizedCaseInsensitiveCompare(
                    $1.ruleName
                ) == .orderedAscending
            }
    }

}
