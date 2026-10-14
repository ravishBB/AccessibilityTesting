//
//  AccessibilityReportIntegrity.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 01/10/26.
//

import Foundation

nonisolated struct AccessibilityReportIntegrityIssue: Identifiable, Hashable {
    let id = UUID()
    let message: String
}

nonisolated struct AccessibilityReportIntegrity {

    static func validate(_ report: AccessibilityScanResult) -> [AccessibilityReportIntegrityIssue] {
        var issues: [AccessibilityReportIntegrityIssue] = []

        let screenEvaluations = report.screens.flatMap(\.evaluations)
        let evaluationCounts = (
            failures: screenEvaluations.filter { $0.status == .fail }.count,
            warnings: screenEvaluations.filter { $0.status == .warning }.count,
            validations: screenEvaluations.filter { $0.status == .validate }.count,
            passes: screenEvaluations.filter { $0.status == .pass }.count
        )

        if report.totalFailures != evaluationCounts.failures {
            issues.append(.init(message: "Failure total does not match screen-level evaluations."))
        }
        if report.totalWarnings != evaluationCounts.warnings {
            issues.append(.init(message: "Warning total does not match screen-level evaluations."))
        }
        if report.totalValidations != evaluationCounts.validations {
            issues.append(.init(message: "Validation total does not match screen-level evaluations."))
        }
        if report.totalPasses != evaluationCounts.passes {
            issues.append(.init(message: "Pass total does not match screen-level evaluations."))
        }

        let duplicateEvaluationIDs = duplicates(in: screenEvaluations.map(\.id))
        if !duplicateEvaluationIDs.isEmpty {
            issues.append(.init(message: "The report contains duplicate evaluation identifiers."))
        }

        let duplicateScreenIDs = duplicates(in: report.screens.map(\.id))
        if !duplicateScreenIDs.isEmpty {
            issues.append(.init(message: "The report contains duplicate screen identifiers."))
        }

        let invalidScreens = report.screens.filter {
            $0.elementCount < 0 ||
            $0.failures < 0 ||
            $0.warnings < 0 ||
            $0.validations < 0 ||
            $0.passes < 0
        }
        if !invalidScreens.isEmpty {
            issues.append(.init(message: "One or more screens contain invalid negative counts."))
        }

        if report.finishedAt < report.startedAt {
            issues.append(.init(message: "Report completion time precedes scan start time."))
        }

        return issues
    }

    /// Checks that can actually catch a scanner defect, unlike the totals
    /// above, which are computed from the same evaluations. They do not block
    /// the report: each problem becomes a note the reader can see.
    static func consistencyNotes(_ report: AccessibilityScanResult) -> [String] {
        var notes: [String] = []
        let catalogued = Set(AccessibilityRuleCatalog.allMetadata.map(\.ruleID))

        // 1. Every result comes from a catalogued rule, so it has WCAG
        //    mapping, impact and test steps in the report.
        let uncatalogued = Set(report.allEvaluations.map(\.ruleID)).subtracting(catalogued)
        if !uncatalogued.isEmpty {
            notes.append("Self-check: results from \(uncatalogued.count) rule\(uncatalogued.count == 1 ? "" : "s") without WCAG mapping (\(uncatalogued.sorted().joined(separator: ", "))).")
        }

        // 2. No rule both passes and fails the same element on one screen.
        var contradictions = Set<String>()
        for screen in report.screens {
            var outcomes: [String: Set<RuleResultStatus>] = [:]
            for evaluation in screen.evaluations where evaluation.status == .pass || evaluation.status == .fail {
                let key = [
                    evaluation.ruleID, evaluation.elementType, evaluation.identifier, evaluation.elementLabel,
                    "\(Int(evaluation.frameX)),\(Int(evaluation.frameY)),\(Int(evaluation.frameWidth)),\(Int(evaluation.frameHeight))"
                ].joined(separator: "|")
                outcomes[key, default: []].insert(evaluation.status)
            }
            for (key, statuses) in outcomes where statuses.count > 1 {
                contradictions.insert(String(key.prefix { $0 != "|" }))
            }
        }
        if !contradictions.isEmpty {
            notes.append("Self-check: \(contradictions.sorted().joined(separator: ", ")) both passed and failed the same element (usually from two scroll positions); check those results manually.")
        }

        // 3. Every screen has a screenshot to back its findings.
        let withoutScreenshot = report.screens.filter { $0.screenshot == nil }.count
        if withoutScreenshot > 0 {
            notes.append("Self-check: \(withoutScreenshot) screen\(withoutScreenshot == 1 ? " has" : "s have") no screenshot, so contrast and visual checks could not run there.")
        }

        return notes
    }

    private static func duplicates<T: Hashable>(in values: [T]) -> Set<T> {
        var seen: Set<T> = []
        var duplicate: Set<T> = []
        for value in values {
            if !seen.insert(value).inserted {
                duplicate.insert(value)
            }
        }
        return duplicate
    }
}
