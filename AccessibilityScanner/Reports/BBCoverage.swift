//
//  BBCoverage.swift
//  AccessibilityScanner
//
//  Accounts for every BB ID in the ruleset on one scan: found, passed, needs
//  review, checked with nothing applicable, or why it could not be checked
//  on the scanned platform. A BB ID never silently disappears from a report.
//

import Foundation

nonisolated struct BBCoverageEntry: Codable, Hashable {

    enum Outcome: String, Codable {
        case found, passed, review
        /// Reported under a sibling code (a verdict instead of a review).
        case coveredBySibling
        case nothingApplicable
        case manual, unavailable, onHold

        var title: String {
            switch self {
            case .found: return "Found"
            case .passed: return "Passed"
            case .review: return "Review"
            case .coveredBySibling: return "Covered"
            case .nothingApplicable: return "Checked"
            case .manual: return "Manual check"
            case .unavailable: return "Not testable"
            case .onHold: return "On hold"
            }
        }

        var cssClass: String {
            switch self {
            case .found: return "fail"
            case .passed: return "pass"
            case .review: return "validate"
            case .coveredBySibling: return "pass"
            case .nothingApplicable: return "neutral"
            case .manual: return "nottested"
            case .unavailable, .onHold: return "norule"
            }
        }
    }

    let id: String
    let issue: String
    let type: String
    let wcag: String
    let severity: String
    let outcome: Outcome
    let count: Int
    let detail: String
}

nonisolated enum BBCoverage {

    static func entries(for report: AccessibilityScanResult) -> [BBCoverageEntry] {
        let platform = platform(of: report)
        let platformName = platform == .android ? "Android" : "iOS"

        // Results per BB ID, by outcome.
        var fails: [String: Int] = [:], passes: [String: Int] = [:], reviews: [String: Int] = [:]
        for evaluation in report.allEvaluations {
            guard let id = BBIssueCatalog.issue(for: evaluation)?.id else { continue }
            switch evaluation.status {
            case .fail, .warning: fails[id, default: 0] += 1
            case .pass: passes[id, default: 0] += 1
            case .validate: reviews[id, default: 0] += 1
            case .notTested: break
            }
        }

        return BBRuleset.rules.map { rule in
            let count: Int
            let outcome: BBCoverageEntry.Outcome
            switch rule.type {
            case .fail:
                count = fails[rule.id] ?? 0
                outcome = .found
            case .pass:
                count = passes[rule.id] ?? 0
                outcome = .passed
            case .validate:
                // Review codes are also used for heuristic warnings.
                count = (reviews[rule.id] ?? 0) + (fails[rule.id] ?? 0) + (passes[rule.id] ?? 0)
                outcome = .review
            }

            if count > 0 {
                return entry(rule, outcome, count, "\(count) result\(count == 1 ? "" : "s") on the scanned screens.")
            }

            let siblingCount = rule.coveredBy.reduce(0) { total, id in
                total + (fails[id] ?? 0) + (passes[id] ?? 0) + (reviews[id] ?? 0)
            }
            if siblingCount > 0 {
                return entry(rule, .coveredBySibling, siblingCount,
                             "Checked; reported as \(rule.coveredBy.joined(separator: " / ")) (\(siblingCount) result\(siblingCount == 1 ? "" : "s")).")
            }

            let note = rule.note.isEmpty ? "" : " \(rule.note)"
            switch rule.capability(on: platform) {
            case .automated, .partial:
                return entry(rule, .nothingApplicable, 0, "Checked; nothing applicable on the scanned screens.")
            case .runtime:
                return entry(rule, .nothingApplicable, 0, "Runtime check (Limited and Full App scans); no result on the scanned screens.")
            case .manual:
                return entry(rule, .manual, 0, "Needs a manual check.\(note)")
            case .unavailable:
                return entry(rule, .unavailable, 0, "Not testable on \(platformName) through Appium.\(note)")
            case .onHold:
                return entry(rule, .onHold, 0, "On hold in the ruleset (AAA).")
            }
        }
    }

    private static func entry(_ rule: BBRule, _ outcome: BBCoverageEntry.Outcome, _ count: Int, _ detail: String) -> BBCoverageEntry {
        BBCoverageEntry(
            id: rule.id,
            issue: rule.issue,
            type: rule.type.rawValue,
            wcag: rule.wcag,
            severity: rule.severity,
            outcome: outcome,
            count: count,
            detail: detail
        )
    }

    static func platform(of report: AccessibilityScanResult) -> MobilePlatform {
        if let name = report.environment?.platform, let platform = MobilePlatform(rawValue: name) {
            return platform
        }
        return report.allEvaluations.first?.platform ?? .ios
    }
}
