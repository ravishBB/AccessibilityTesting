import Foundation

// Tester-focused interpretation of a rule result. This layer deliberately
// uses only evidence already present in the scan; it never upgrades a
// VALIDATE result into PASS/FAIL.
extension AccessibilityRuleEvaluation {

    enum TesterPriority: String {
        case critical = "Critical"
        case high = "High"
        case medium = "Medium"
        case review = "Review"
    }

    var testerPriority: TesterPriority {
        switch severity {
        case .error: return .critical
        case .warning: return .high
        case .info: return .review
        }
    }

    var targetDescription: String {
        let name = elementLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        if !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return identifier }
        return elementRole.rawValue
    }

    /// Manual verification steps, sourced from the rule catalog so they always
    /// match the rule IDs the scanner actually emits.
    var testerAction: String {
        AccessibilityRuleCatalog.metadata(for: ruleID).howToTest
    }

    var evidenceSummary: String {
        switch status {
        case .fail:
            return "Automated evidence indicates a problem in the captured accessibility hierarchy or rendered evidence."
        case .warning:
            return "The scanner detected a condition that may require tester confirmation."
        case .validate:
            return "The scanner could not prove PASS or FAIL from the available black-box evidence. Manual verification is required."
        case .pass:
            return "The captured evidence satisfies this automated check."
        }
    }

    var isTesterActionable: Bool {
        status != .pass
    }
}
