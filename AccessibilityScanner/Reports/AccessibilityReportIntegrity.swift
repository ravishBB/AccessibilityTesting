//
//  AccessibilityReportIntegrity.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 01/10/26.
//

import Foundation

struct AccessibilityReportIntegrityIssue: Identifiable, Hashable {
    let id = UUID()
    let message: String
}

struct AccessibilityReportIntegrity {

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
