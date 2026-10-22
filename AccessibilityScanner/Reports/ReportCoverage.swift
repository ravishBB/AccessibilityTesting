//
//  ReportCoverage.swift
//  AccessibilityScanner


import Foundation

// MARK: - WCAG 2.2 reference (Level A and AA)

nonisolated struct WCAGCriterionReference: Hashable {
    let number: String
    let title: String
    let level: String
}

nonisolated enum WCAGReference {

    /// Every WCAG 2.2 Level A and AA success criterion, in numeric order.
    /// (4.1.1 Parsing was removed in WCAG 2.2.)
    static let criteria: [WCAGCriterionReference] = [
        c("1.1.1", "Non-text Content", "A"),
        c("1.2.1", "Audio-only and Video-only (Prerecorded)", "A"),
        c("1.2.2", "Captions (Prerecorded)", "A"),
        c("1.2.3", "Audio Description or Media Alternative (Prerecorded)", "A"),
        c("1.2.4", "Captions (Live)", "AA"),
        c("1.2.5", "Audio Description (Prerecorded)", "AA"),
        c("1.3.1", "Info and Relationships", "A"),
        c("1.3.2", "Meaningful Sequence", "A"),
        c("1.3.3", "Sensory Characteristics", "A"),
        c("1.3.4", "Orientation", "AA"),
        c("1.3.5", "Identify Input Purpose", "AA"),
        c("1.4.1", "Use of Color", "A"),
        c("1.4.2", "Audio Control", "A"),
        c("1.4.3", "Contrast (Minimum)", "AA"),
        c("1.4.4", "Resize Text", "AA"),
        c("1.4.5", "Images of Text", "AA"),
        c("1.4.10", "Reflow", "AA"),
        c("1.4.11", "Non-text Contrast", "AA"),
        c("1.4.12", "Text Spacing", "AA"),
        c("1.4.13", "Content on Hover or Focus", "AA"),
        c("2.1.1", "Keyboard", "A"),
        c("2.1.2", "No Keyboard Trap", "A"),
        c("2.1.4", "Character Key Shortcuts", "A"),
        c("2.2.1", "Timing Adjustable", "A"),
        c("2.2.2", "Pause, Stop, Hide", "A"),
        c("2.3.1", "Three Flashes or Below Threshold", "A"),
        c("2.4.1", "Bypass Blocks", "A"),
        c("2.4.2", "Page Titled", "A"),
        c("2.4.3", "Focus Order", "A"),
        c("2.4.4", "Link Purpose (In Context)", "A"),
        c("2.4.5", "Multiple Ways", "AA"),
        c("2.4.6", "Headings and Labels", "AA"),
        c("2.4.7", "Focus Visible", "AA"),
        c("2.4.11", "Focus Not Obscured (Minimum)", "AA"),
        c("2.5.1", "Pointer Gestures", "A"),
        c("2.5.2", "Pointer Cancellation", "A"),
        c("2.5.3", "Label in Name", "A"),
        c("2.5.4", "Motion Actuation", "A"),
        c("2.5.7", "Dragging Movements", "AA"),
        c("2.5.8", "Target Size (Minimum)", "AA"),
        c("3.1.1", "Language of Page", "A"),
        c("3.1.2", "Language of Parts", "AA"),
        c("3.2.1", "On Focus", "A"),
        c("3.2.2", "On Input", "A"),
        c("3.2.3", "Consistent Navigation", "AA"),
        c("3.2.4", "Consistent Identification", "AA"),
        c("3.2.6", "Consistent Help", "A"),
        c("3.3.1", "Error Identification", "A"),
        c("3.3.2", "Labels or Instructions", "A"),
        c("3.3.3", "Error Suggestion", "AA"),
        c("3.3.4", "Error Prevention (Legal, Financial, Data)", "AA"),
        c("3.3.7", "Redundant Entry", "A"),
        c("3.3.8", "Accessible Authentication (Minimum)", "AA"),
        c("4.1.2", "Name, Role, Value", "A"),
        c("4.1.3", "Status Messages", "AA")
    ]


    private static func c(_ number: String, _ title: String, _ level: String) -> WCAGCriterionReference {
        WCAGCriterionReference(number: number, title: title, level: level)
    }
}

// MARK: - Per-rule outcome

nonisolated enum RuleCoverageOutcome: String, Codable {
    /// The rule produced at least one pass, fail or warning.
    case automatedVerdict
    /// The rule only produced manual-review items.
    case manualReviewOnly
    /// The rule could not be exercised through the portable Appium API.
    case notTested
    /// The rule ran but found nothing applicable on the scanned screens.
    case noApplicableContent

    var title: String {
        switch self {
        case .automatedVerdict: return "Automated result"
        case .manualReviewOnly: return "Manual review only"
        case .notTested: return "Not tested"
        case .noApplicableContent: return "No applicable content"
        }
    }

    var cssClass: String {
        switch self {
        case .automatedVerdict: return "pass"
        case .manualReviewOnly: return "validate"
        case .notTested: return "nottested"
        case .noApplicableContent: return "neutral"
        }
    }

    /// Lower sorts first.
    var rank: Int {
        switch self {
        case .automatedVerdict: return 0
        case .manualReviewOnly: return 1
        case .notTested: return 2
        case .noApplicableContent: return 3
        }
    }
}

nonisolated struct RuleCoverageEntry: Identifiable, Codable {
    var id: String { ruleID }

    let ruleID: String
    let ruleName: String
    let outcome: RuleCoverageOutcome

    /// Unique rule results (one rule on one element on one screen).
    let failures: Int
    let warnings: Int
    let validations: Int
    let passes: Int

    /// Raw count of "not tested" records (one per screen the stub fired on).
    let notTestedRecords: Int
}

// MARK: - Per-criterion coverage

nonisolated enum CriterionCoverageState: String, Codable {
    case failed
    case warning
    /// Every mapped rule that ran passed, and nothing is left unresolved.
    case passed
    /// Some mapped rules passed, others still need manual review or could not be tested.
    case partial
    case manualReview
    case notTested
    case noApplicableContent
    /// No rule maps to this criterion yet.
    case noRule

    var title: String {
        switch self {
        case .failed: return "Failed"
        case .warning: return "Warnings"
        case .passed: return "Passed (automated)"
        case .partial: return "Partly verified"
        case .manualReview: return "Manual review needed"
        case .notTested: return "Not tested"
        case .noApplicableContent: return "No applicable content"
        case .noRule: return "No rule yet"
        }
    }

    var cssClass: String {
        switch self {
        case .failed: return "fail"
        case .warning: return "warning"
        case .passed: return "pass"
        case .partial, .manualReview: return "validate"
        case .notTested: return "nottested"
        case .noApplicableContent: return "neutral"
        case .noRule: return "norule"
        }
    }

    /// True when at least one automated rule produced a real verdict.
    var hasAutomatedVerdict: Bool {
        switch self {
        case .failed, .warning, .passed, .partial: return true
        default: return false
        }
    }
}

nonisolated struct CriterionCoverage: Identifiable, Codable {
    var id: String { number }

    let number: String
    let title: String
    let level: String
    let state: CriterionCoverageState
    let ruleIDs: [String]

    let failures: Int
    let warnings: Int
    let validations: Int
    let passes: Int
}

// MARK: - Report coverage

nonisolated struct ReportCoverage: Codable {

    let ruleSetVersion: String

    let rulesInRuleSet: Int
    let rulesWithAutomatedVerdict: Int
    let rulesManualReviewOnly: Int
    let rulesNotTested: Int
    let rulesNoApplicableContent: Int

    /// Number of WCAG 2.2 Level A and AA criteria (the denominator below).
    let criteriaTotalAAndAA: Int
    let criteriaWithAutomatedVerdict: Int
    let criteriaManualReviewOnly: Int
    let criteriaNotTested: Int
    let criteriaNoApplicableContent: Int
    let criteriaWithoutRule: Int

    let rules: [RuleCoverageEntry]
    /// All Level A and AA criteria, followed by any AAA criteria a rule maps to.
    let criteria: [CriterionCoverage]

    init(report: AccessibilityScanResult, grouping: FindingGrouping) {

        let evaluationsByRule = Dictionary(grouping: report.allEvaluations, by: { $0.ruleID })
        let titleByRule = Dictionary(
            AccessibilityRules.all.map { ($0.id, $0.title) },
            uniquingKeysWith: { first, _ in first }
        )

        var failuresByRule: [String: Int] = [:]
        var warningsByRule: [String: Int] = [:]
        var validationsByRule: [String: Int] = [:]
        for group in grouping.groups {
            switch group.status {
            case .fail: failuresByRule[group.ruleID, default: 0] += group.count
            case .warning: warningsByRule[group.ruleID, default: 0] += group.count
            case .validate: validationsByRule[group.ruleID, default: 0] += group.count
            default: break
            }
        }

        // One entry per catalog rule, including rules that produced nothing.
        var entries: [RuleCoverageEntry] = []
        for metadata in AccessibilityRuleCatalog.allMetadata {
            let ruleID = metadata.ruleID
            let evaluations = evaluationsByRule[ruleID] ?? []

            let failures = failuresByRule[ruleID] ?? 0
            let warnings = warningsByRule[ruleID] ?? 0
            let validations = validationsByRule[ruleID] ?? 0
            let passes = grouping.passesByRule[ruleID] ?? 0
            let notTestedRecords = evaluations.filter { $0.status == .notTested }.count

            let outcome: RuleCoverageOutcome
            if failures + warnings + passes > 0 {
                outcome = .automatedVerdict
            } else if validations > 0 {
                outcome = .manualReviewOnly
            } else if notTestedRecords > 0 {
                outcome = .notTested
            } else {
                outcome = .noApplicableContent
            }

            entries.append(
                RuleCoverageEntry(
                    ruleID: ruleID,
                    ruleName: evaluations.first?.ruleName ?? titleByRule[ruleID] ?? ruleID,
                    outcome: outcome,
                    failures: failures,
                    warnings: warnings,
                    validations: validations,
                    passes: passes,
                    notTestedRecords: notTestedRecords
                )
            )
        }

        // Roll rules up to WCAG criteria.
        var entriesByCriterion: [String: [RuleCoverageEntry]] = [:]
        var metadataByCriterion: [String: AccessibilityRuleMetadata] = [:]
        let entryByRule = Dictionary(uniqueKeysWithValues: entries.map { ($0.ruleID, $0) })
        for metadata in AccessibilityRuleCatalog.allMetadata {
            guard let criterion = metadata.wcagCriterion,
                  let entry = entryByRule[metadata.ruleID] else { continue }
            entriesByCriterion[criterion, default: []].append(entry)
            if metadataByCriterion[criterion] == nil {
                metadataByCriterion[criterion] = metadata
            }
        }

        func coverage(
            number: String,
            title: String,
            level: String
        ) -> CriterionCoverage {
            let mapped = (entriesByCriterion[number] ?? []).sorted { $0.ruleID < $1.ruleID }
            return CriterionCoverage(
                number: number,
                title: title,
                level: level,
                state: ReportCoverage.state(for: mapped),
                ruleIDs: mapped.map(\.ruleID),
                failures: mapped.reduce(0) { $0 + $1.failures },
                warnings: mapped.reduce(0) { $0 + $1.warnings },
                validations: mapped.reduce(0) { $0 + $1.validations },
                passes: mapped.reduce(0) { $0 + $1.passes }
            )
        }

        var criteria = WCAGReference.criteria.map {
            coverage(number: $0.number, title: $0.title, level: $0.level)
        }
        let aAndAA = criteria

        // AAA criteria (and anything else) that rules map to, listed after A/AA.
        let referenceNumbers = Set(WCAGReference.criteria.map(\.number))
        let extraNumbers = entriesByCriterion.keys
            .filter { !referenceNumbers.contains($0) }
            .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
        for number in extraNumbers {
            let metadata = metadataByCriterion[number]
            criteria.append(
                coverage(
                    number: number,
                    title: metadata?.wcagTitle ?? number,
                    level: metadata?.wcagLevel ?? "AAA"
                )
            )
        }

        self.ruleSetVersion = AccessibilityRuleCatalog.version

        self.rulesInRuleSet = entries.count
        self.rulesWithAutomatedVerdict = entries.filter { $0.outcome == .automatedVerdict }.count
        self.rulesManualReviewOnly = entries.filter { $0.outcome == .manualReviewOnly }.count
        self.rulesNotTested = entries.filter { $0.outcome == .notTested }.count
        self.rulesNoApplicableContent = entries.filter { $0.outcome == .noApplicableContent }.count

        self.criteriaTotalAAndAA = aAndAA.count
        self.criteriaWithAutomatedVerdict = aAndAA.filter { $0.state.hasAutomatedVerdict }.count
        self.criteriaManualReviewOnly = aAndAA.filter { $0.state == .manualReview }.count
        self.criteriaNotTested = aAndAA.filter { $0.state == .notTested }.count
        self.criteriaNoApplicableContent = aAndAA.filter { $0.state == .noApplicableContent }.count
        self.criteriaWithoutRule = aAndAA.filter { $0.state == .noRule }.count

        self.rules = entries
        self.criteria = criteria
    }

    /// Decides a criterion's state from the rules mapped to it.
    private static func state(for mapped: [RuleCoverageEntry]) -> CriterionCoverageState {
        if mapped.isEmpty { return .noRule }
        if mapped.contains(where: { $0.failures > 0 }) { return .failed }
        if mapped.contains(where: { $0.warnings > 0 }) { return .warning }

        let verified = mapped.filter { $0.outcome == .automatedVerdict }
        let manual = mapped.filter { $0.outcome == .manualReviewOnly }
        let notTested = mapped.filter { $0.outcome == .notTested }

        if !verified.isEmpty {
            return (manual.isEmpty && notTested.isEmpty) ? .passed : .partial
        }
        if !manual.isEmpty { return .manualReview }
        if !notTested.isEmpty { return .notTested }
        return .noApplicableContent
    }

}

// MARK: - Cheap helper for list rows and headers

nonisolated extension AccessibilityScanResult {
    var verdictCapableRuleCount: Int {
        AccessibilityRuleCatalog.verdictCapableRuleCount(on: BBCoverage.platform(of: self))
    }

    var platformName: String {
        BBCoverage.platform(of: self) == .android ? "Android" : "iOS"
    }

    var automatedVerdictRuleCount: Int {
        Set(
            allEvaluations
                .filter { $0.status == .pass || $0.status == .fail || $0.status == .warning }
                .map(\.ruleID)
        ).count
    }
}
