//
//  BBIssueCatalog.swift
//  AccessibilityScanner


import Foundation

nonisolated struct BBIssue: Codable, Hashable {
    let id: String
    let title: String
    /// WCAG criterion from the BB sheet, e.g. "2.4.6".
    let wcag: String?
}

nonisolated enum BBIssueCatalog {

    /// Bump whenever a mapping is added, removed or changed.
    static let version = "2026.11.27"

    // MARK: - Lookup

    static func issue(for evaluation: AccessibilityRuleEvaluation) -> BBIssue? {
        guard let id = issueID(for: evaluation) else { return nil }
        return sheetIssue(id, platform: evaluation.platform)
    }

    static func title(for id: String, platform: MobilePlatform) -> String? {
        sheet(platform)[id]?.issue
    }

    static func heading(issue: BBIssue?, ifConfirmed: BBIssue?, ruleName: String) -> (title: String, description: String?) {
        if let issue { return (issue.title, nil) }
        if let ifConfirmed { return (ifConfirmed.title, "Validate: record as a failure if confirmed") }
        return (ruleName, nil)
    }

    static func heading(for evaluation: AccessibilityRuleEvaluation) -> (title: String, description: String?) {
        heading(issue: issue(for: evaluation), ifConfirmed: ifConfirmed(for: evaluation), ruleName: evaluation.ruleName)
    }

    private enum Outcome {
        case pass, fail, review
    }

    private static func issueID(for evaluation: AccessibilityRuleEvaluation) -> String? {
        mappedID(for: evaluation)
    }

    /// Every BB ID this evaluation's rule can report, whatever its result:
    /// the codes a run of the rule settles, or leaves untested when it
    /// could not run.
    static func candidateIDs(for evaluation: AccessibilityRuleEvaluation) -> Set<String> {
        var ids = Set([Outcome.pass, .fail, .review].compactMap { mappedID(for: evaluation, outcomeOverride: $0) })
        let related = evaluation.platform == .android ? androidRelatedIDs : relatedIDs
        ids.formUnion(related[evaluation.ruleID] ?? [])
        return ids
    }

    /// Codes a rule reports that depend on the element or message, so one
    /// evaluation does not name them all.
    private static let relatedIDs: [String: Set<String>] = [
        "keyboard-focus": ["BB40066", "BB41054", "BB41015", "BB41005"],
        "keyboard-activation": ["BB41035", "BB41067", "BB40283"],
        "focus-indicator": ["BB40073", "BB40074", "BB40117", "BB40118", "BB40119", "BB40120", "BB40075"],
        "orientation-support": ["BB40055", "BB40056", "BB41001"],
        "modal-focus-containment": ["BB40244", "BB40245", "BB41024"],
        "interactive-screen-reader-hidden": ["BB40046", "BB40078"],
        "duplicate-interactive-name": ["BB40090", "BB41036", "BB41056"],
        "placeholder-only-name": ["BB41053", "BB40093"],
        "name-via-hint": ["BB40049", "BB30549"],
        "contrast-text-over-image": ["BB41028", "BB41029"],
    ]

    private static let androidRelatedIDs: [String: Set<String>] = [
        "keyboard-focus": ["BB30024", "BB30025", "BB30026", "BB30027", "BB30028", "BB30029", "BB30030", "BB30031",
                           "BB30036", "BB30037", "BB30061", "BB30062", "BB30063", "BB30064", "BB30077", "BB30078",
                           "BB30124", "BB30125", "BB40015", "BB40005"],
        "keyboard-activation": ["BB30025", "BB30027", "BB30031", "BB30037", "BB30062", "BB30064", "BB30077",
                                "BB30125", "BB40058"],
        "focus-indicator": ["BB40012", "BB40024"],
        "orientation-support": ["BB30080", "BB40001", "BB40002"],
        "accessible-name": ["BB30010", "BB30014", "BB30018", "BB30022", "BB30040", "BB30043", "BB30054", "BB30075", "BB30082"],
        "interactive-name-descriptive": ["BB30006", "BB30011", "BB30015", "BB30019", "BB30023", "BB30038", "BB30041",
                                         "BB30044", "BB30073", "BB30083"],
        "button-name-descriptive": ["BB30003", "BB30004", "BB30005", "BB30006", "BB30010", "BB30011", "BB30038"],
        "interactive-screen-reader-hidden": ["BB30052", "BB30001", "BB30012", "BB30016", "BB30020", "BB30008"],
        "duplicate-interactive-name": ["BB40036", "BB40054", "BB30069"],
        "state-updates-after-interaction": ["BB30048", "BB30049", "BB30050", "BB30051", "BB30059", "BB30060", "BB30087", "BB30088"],
        "contrast-text-over-image": ["BB40027", "BB40028"],
        "screen-reader-content": ["BB30116", "BB40010"],
        "missing-role": ["BB40004", "BB30065"],
    ]

    static func ifConfirmed(for evaluation: AccessibilityRuleEvaluation) -> BBIssue? {
        guard evaluation.status == .validate, mappedID(for: evaluation) == nil,
              let id = mappedID(for: evaluation, outcomeOverride: .fail)
        else { return nil }
        return sheetIssue(id, platform: evaluation.platform)
    }

    private static func mappedID(for evaluation: AccessibilityRuleEvaluation, outcomeOverride: Outcome? = nil) -> String? {
        let outcome: Outcome
        if let outcomeOverride {
            outcome = outcomeOverride
        } else {
            switch evaluation.status {
            case .pass: outcome = .pass
            case .fail, .warning: outcome = .fail
            case .validate: outcome = .review
            case .notTested: return nil
            }
        }

        return evaluation.platform == .android
            ? androidID(for: evaluation, outcome: outcome)
            : iosID(for: evaluation, outcome: outcome)
    }

    // MARK: - iOS sheet

    private static func iosID(for evaluation: AccessibilityRuleEvaluation, outcome: Outcome) -> String? {
        let role = evaluation.elementRole
        let missingName = evaluation.elementLabel
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let largeText = TextSizeEstimate.classify(evaluation) == .large

        switch (evaluation.ruleID, outcome) {

        // Name
        case ("button-name-descriptive", .fail): return missingName ? "BB40003" : "BB40124"
        case ("button-name-descriptive", .pass): return "BB40125"
        case ("button-name-descriptive", .review): return "BB40002"
        case ("image-button-name", .fail): return "BB40004"
        case ("accessible-name", .fail):
            guard role == .segmentedControl else { return "BB30548" }
            return evaluation.message.hasPrefix("Image segmented") ? "BB40039" : "BB40038"
        case ("name-via-hint", .fail): return role == .button ? "BB40049" : "BB30549"
        case ("label-in-name", .fail): return role == .button ? "BB40088" : "BB40121"
        case ("label-in-name", .pass): return role == .button ? "BB40089" : nil
        case ("interactive-name-descriptive", .fail): return "BB40124"
        case ("interactive-name-descriptive", .pass): return "BB40125"
        case ("interactive-name-descriptive", .review): return role == .segmentedControl ? "BB40037" : "BB40051"
        case ("duplicate-interactive-name", .fail):
            switch role {
            case .button: return "BB41036"
            case .toggle: return "BB41056"
            default: return "BB40090"
            }
        case ("placeholder-only-name", .fail):
            return evaluation.message.hasPrefix(PlaceholderOnlyNameRule.unassociatedPrefix) ? "BB41053" : "BB40093"

        // Colour and contrast
        case ("contrast-standard-text-4-5", .fail): return "BB40018"
        case ("contrast-standard-text-4-5", .pass): return "BB40024"
        case ("contrast-standard-text-4-5", .review): return "BB40008"
        case ("contrast-large-text-3", .fail): return "BB40020"
        case ("contrast-large-text-3", .pass): return "BB40022"
        case ("contrast-large-text-3", .review): return "BB40009"
        case ("contrast-text-over-image", .fail): return largeText ? "BB41029" : "BB41028"
        case ("contrast-text-over-image", .pass): return largeText ? "BB40022" : "BB40024"
        case ("contrast-text-over-image", .review): return largeText ? "BB40014" : "BB40010"
        case ("link-color-differentiation", .fail): return "BB41017"
        case ("link-color-differentiation", .review): return "BB40306"
        case ("non-text-contrast", .fail): return "BB40060"
        case ("non-text-contrast", .pass): return "BB40061"
        case ("form-border-contrast", .fail): return "BB40062"
        case ("form-border-contrast", .pass): return "BB40063"
        case ("loading-indicator-contrast", .fail): return "BB40064"
        case ("loading-indicator-contrast", .pass): return "BB40065"
        case ("focus-indicator", .fail): return "BB40073"
        case ("focus-indicator", .pass): return "BB40074"
        case ("focus-indicator-contrast", .fail): return "BB40117"
        case ("focus-indicator-contrast", .pass): return "BB40118"
        case ("focus-not-obscured", .review): return "BB40075"
        case ("focus-indicator-color-only", .fail): return "BB40119"
        case ("focus-indicator-color-only", .pass): return "BB40120"

        // Target size
        case ("touch-target-size-24", .fail): return "BB40030"
        case ("touch-target-size-24", .pass): return "BB40028"

        // Text size (all from the 200% text-size layout)
        case ("text-resize", .fail): return "BB40031"
        case ("text-resize", .pass): return "BB40032"
        case ("text-clipping", .fail), ("text-truncation", .fail), ("text-overlap", .fail): return "BB40033"
        case ("text-clipping", .pass), ("text-truncation", .pass), ("text-overlap", .pass): return "BB40034"

        // Role
        case ("heading-quality", .review): return "BB40040"
        case ("heading-candidate", .review): return "BB40041"
        case ("missing-role", .fail): return "BB40282"
        case ("icon-control-role", .fail), ("row-role", .fail): return "BB40282"
        case ("missing-role", .pass): return "BB40275"
        case ("text-link-role", .fail): return "BB40042"
        case ("text-button-role", .fail): return "BB40043"
        case ("role-trait-consistency", .fail): return "BB40281"
        case ("role-trait-consistency", .pass): return "BB40275"
        case ("segmented-control-interactive", .review): return "BB40035"
        case ("tab-accessibility", .review): return "BB40036"

        // State and value
        case ("adjustable-accessibility-value", .fail): return "BB40278"
        case ("adjustable-accessibility-value", .pass): return "BB40279"
        case ("state-updates-after-interaction", .fail): return "BB40280"
        case ("state-updates-after-interaction", .review): return "BB40068"

        // Images
        case ("image-accessible-label", .fail): return "BB41038"
        case ("image-name-descriptive", .fail): return "BB40126"
        case ("image-name-descriptive", .review): return "BB40045"
        case ("decorative-image", .review): return "BB40044"
        case ("map-text-alternative", .review): return "BB40140"
        case ("map-text-alternative", .pass): return "BB40141"

        // Hidden content
        case ("interactive-screen-reader-hidden", .fail): return role == .button ? "BB40078" : nil
        case ("interactive-screen-reader-hidden", .review): return "BB40046"
        case ("screen-reader-content", .fail): return "BB41010"
        case ("screen-reader-content", .pass): return "BB40058"
        case ("screen-reader-content", .review): return "BB40057"

        // Focus and reading order
        case ("focus-order", .fail), ("screen-reader-focus-order", .fail): return "BB41084"
        case ("focus-order", .review), ("screen-reader-focus-order", .review): return "BB40053"
        case ("focus-order", .pass), ("screen-reader-focus-order", .pass): return "BB40054"
        case ("reading-order", .fail): return "BB40134"
        case ("reading-order", .pass): return "BB40135"

        // Orientation
        case ("orientation-support", .fail):
            if evaluation.message.contains("refused to rotate") { return "BB40056" }
            if evaluation.message.contains("stayed in") { return "BB41001" }
            return nil
        case ("orientation-support", .review): return "BB40055"

        // Language
        case ("language", .fail): return "BB40105"
        case ("language", .pass): return "BB40106"
        case ("content-language", .fail): return "BB40109"
        case ("content-language", .pass): return "BB40112"
        case ("language-change", .fail): return "BB40111"

        // Modal
        case ("modal-focus-containment", .pass): return "BB40245"
        case ("modal-closable", .pass): return "BB40114"
        case ("modal-focus-containment", .fail):
            return evaluation.message.contains("no keyboard-focusable") ? "BB40244" : "BB41024"

        // Live region
        case ("live-region", .fail): return "BB40103"
        case ("live-region", .pass): return "BB40104"

        // Keyboard
        case ("keyboard-focus", .fail): return role == .toggle ? "BB41054" : "BB40066"
        case ("keyboard-focus-hidden-content", .fail): return "BB41015"
        case ("keyboard-focus-noninteractive", .fail): return "BB41005"
        case ("keyboard-activation", .fail):
            switch role {
            case .button: return "BB41035"
            case .link: return "BB41067"
            default: return "BB40283"
            }
        case ("gesture-keyboard-operable", .fail): return "BB40071"
        case ("gesture-keyboard-operable", .pass): return "BB40072"

        // Gestures, pointer and motion
        case ("complex-gesture-alternative", .fail),
             ("multi-point-gesture-alternative", .fail),
             ("path-based-gesture-alternative", .fail): return "BB40190"
        case ("complex-gesture-alternative", .pass),
             ("multi-point-gesture-alternative", .pass),
             ("path-based-gesture-alternative", .pass): return "BB40191"
        case ("touch-up-cancellation", .fail): return "BB40136"
        case ("touch-up-cancellation", .pass): return "BB40137"
        case ("motion-alternative", .fail): return "BB40052"
        case ("motion-alternative", .pass): return "BB40102"

        // Forms and errors
        case ("form-visual-label", .fail): return "BB40093"
        case ("form-visual-label", .pass): return "BB40094"
        case ("form-autocomplete", .fail): return "BB40091"
        case ("form-autocomplete", .pass): return "BB40092"
        case ("error-message-accessibility", .fail): return "BB40095"
        case ("error-message-suggestion", .fail): return "BB40096"

        // Screen
        case ("screen-title", .pass): return "BB40099"

        default: return nil
        }
    }

    // MARK: - Android sheet

    /// The control as the Android sheet names it. The sheet has separate codes
    /// for chips, toggle buttons, tabs and image buttons, which share roles
    /// with buttons and switches, so the class name decides.
    private enum AndroidKind {
        case button, imageButton, chip, tab, toggleButton, switchControl, checkBox, radio, slider, dropdown, textField, link, image, text, other
    }

    private static func androidKind(_ evaluation: AccessibilityRuleEvaluation) -> AndroidKind {
        let simple = evaluation.elementType.split(separator: ".").last.map(String.init) ?? evaluation.elementType
        if simple.contains("TabView") || simple.hasSuffix("$Tab") { return .tab }
        if simple.hasSuffix("ImageButton") || simple.contains("FloatingActionButton") { return .imageButton }
        if simple.hasSuffix("Chip") { return .chip }
        if simple.hasSuffix("ToggleButton") { return .toggleButton }
        switch evaluation.elementRole {
        case .toggle: return .switchControl
        case .checkBox: return .checkBox
        case .radioButton: return .radio
        case .slider: return .slider
        case .picker: return .dropdown
        case .textField, .secureTextField, .textView: return .textField
        case .link: return .link
        case .image: return .image
        case .button: return .button
        case .staticText: return .text
        default: return .other
        }
    }

    private static func androidID(for evaluation: AccessibilityRuleEvaluation, outcome: Outcome) -> String? {
        let kind = androidKind(evaluation)
        let missingName = evaluation.elementLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let largeText = TextSizeEstimate.classify(evaluation) == .large

        switch (evaluation.ruleID, outcome) {

        // Name
        case ("button-name-descriptive", .fail):
            guard missingName else { return nil }
            switch kind {
            case .tab: return "BB30010"
            case .imageButton: return "BB30004"
            case .chip: return "BB30054"
            default: return "BB30003"
            }
        case ("button-name-descriptive", .review):
            switch kind {
            case .tab: return "BB30011"
            case .imageButton: return "BB30005"
            case .chip: return "BB30038"
            default: return "BB30006"
            }
        case ("image-button-name", .fail): return "BB30004"
        case ("accessible-name", .fail):
            switch kind {
            case .switchControl: return "BB30022"
            case .checkBox: return "BB30014"
            case .radio: return "BB30018"
            case .slider: return "BB30040"
            case .dropdown: return "BB30043"
            case .textField: return "BB30075"
            case .toggleButton: return "BB30082"
            case .chip: return "BB30054"
            case .tab: return "BB30010"
            default: return nil
            }
        case ("interactive-name-descriptive", .review):
            switch kind {
            case .switchControl: return "BB30023"
            case .checkBox: return "BB30015"
            case .radio: return "BB30019"
            case .slider: return "BB30041"
            case .dropdown: return "BB30044"
            case .textField: return "BB30073"
            case .toggleButton: return "BB30083"
            case .chip: return "BB30038"
            case .tab: return "BB30011"
            default: return nil
            }
        case ("name-via-hint", .fail): return "BB30112"
        case ("duplicate-interactive-name", .fail):
            switch kind {
            case .button, .imageButton: return "BB40036"
            case .switchControl: return "BB40054"
            default: return "BB30069"
            }
        case ("placeholder-only-name", .fail): return "BB40051"

        // Colour and contrast
        case ("contrast-standard-text-4-5", .fail): return "BB30094"
        case ("contrast-standard-text-4-5", .pass): return "BB30096"
        case ("contrast-standard-text-4-5", .review): return "BB30095"
        case ("contrast-large-text-3", .fail): return "BB30126"
        case ("contrast-large-text-3", .pass): return "BB30127"
        case ("contrast-text-over-image", .fail): return largeText ? "BB40028" : "BB40027"
        case ("contrast-text-over-image", .pass): return largeText ? "BB30127" : "BB30096"
        case ("link-color-differentiation", .fail): return "BB40018"
        case ("non-text-contrast", .fail), ("loading-indicator-contrast", .fail): return "BB30117"
        case ("non-text-contrast", .pass), ("loading-indicator-contrast", .pass): return "BB30119"
        case ("non-text-contrast", .review), ("loading-indicator-contrast", .review): return "BB30118"
        case ("form-border-contrast", .fail): return "BB40026"
        case ("focus-indicator", .fail): return "BB40012"
        case ("focus-indicator-contrast", .fail): return "BB40024"

        // Target size
        case ("touch-target-size-24", .fail): return "BB30058"
        case ("touch-target-size-24", .pass): return "BB30056"

        // Text size (font scale 2.0 layout)
        case ("text-resize", .fail): return "BB40017"
        case ("text-resize", .review): return "BB30123"
        case ("text-clipping", .fail), ("text-truncation", .fail), ("text-overlap", .fail): return "BB30122"

        // Role
        case ("heading-quality", .review), ("heading-candidate", .review): return "BB30079"
        case ("missing-role", .fail): return evaluation.elementRole == .button ? "BB40004" : "BB30065"
        case ("role-trait-consistency", .fail), ("text-button-role", .fail): return "BB40004"
        case ("text-link-role", .fail): return "BB40057"
        case ("tab-accessibility", .review): return "BB30008"

        // State and value
        case ("adjustable-accessibility-value", .review): return "BB30111"
        case ("state-updates-after-interaction", .fail):
            switch kind {
            case .radio: return "BB30051"
            case .tab: return "BB30049"
            default: return nil
            }
        case ("state-updates-after-interaction", .review):
            switch kind {
            case .tab: return "BB30048"
            case .radio: return "BB30050"
            case .checkBox: return "BB30059"
            case .switchControl: return "BB30060"
            case .chip: return "BB30087"
            case .toggleButton: return "BB30088"
            default: return nil
            }

        // Images
        case ("image-accessible-label", .fail): return "BB30034"
        case ("image-name-descriptive", .fail): return "BB30071"
        case ("image-name-descriptive", .review): return "BB30035"
        case ("decorative-image", .review): return "BB30032"

        // Hidden content
        case ("interactive-screen-reader-hidden", .fail): return "BB30052"
        case ("interactive-screen-reader-hidden", .review):
            switch kind {
            case .button, .imageButton: return "BB30001"
            case .checkBox: return "BB30012"
            case .radio: return "BB30016"
            case .switchControl: return "BB30020"
            case .tab: return "BB30008"
            default: return nil
            }
        case ("screen-reader-content", .fail): return kind == .text ? "BB30116" : "BB40010"

        // Order
        case ("focus-order", .fail): return "BB40076"
        case ("reading-order", .review): return "BB30089"
        case ("reading-order", .fail): return "BB30101"

        // Orientation
        case ("orientation-support", .fail):
            if evaluation.message.contains("refused to rotate") { return "BB40002" }
            if evaluation.message.contains("stayed in") { return "BB40001" }
            return nil
        case ("orientation-support", .review): return "BB30080"

        // Dialogs, live regions, errors
        case ("modal-closable", .review): return "BB30106"
        case ("live-region", .fail): return "BB30099"
        case ("live-region", .review): return "BB30100"
        case ("error-message-suggestion", .review): return "BB30098"

        // Keyboard
        case ("keyboard-focus", .fail), ("keyboard-activation", .fail):
            switch kind {
            case .switchControl: return "BB30031"
            case .checkBox: return "BB30027"
            case .radio: return evaluation.ruleID == "keyboard-activation" ? "BB40058" : "BB30029"
            case .toggleButton: return "BB30125"
            case .slider: return "BB30062"
            case .dropdown: return "BB30064"
            case .textField: return "BB30077"
            case .tab: return "BB30025"
            case .button, .imageButton, .chip: return "BB30037"
            default: return nil
            }
        case ("keyboard-focus", .pass):
            switch kind {
            case .switchControl: return "BB30030"
            case .checkBox: return "BB30026"
            case .radio: return "BB30028"
            case .toggleButton: return "BB30124"
            case .slider: return "BB30061"
            case .dropdown: return "BB30063"
            case .textField: return "BB30078"
            case .tab: return "BB30024"
            case .button, .imageButton, .chip: return "BB30036"
            default: return nil
            }
        case ("keyboard-focus-hidden-content", .fail): return "BB40015"
        case ("keyboard-focus-noninteractive", .fail): return "BB40005"

        default: return nil
        }
    }

    // MARK: - Sheet text
    //
    // Titles and WCAG criteria come from BBRuleset, which is generated from
    // each platform's BB sheet, so a mapped ID reads exactly as that sheet does.

    private static let iosSheet: [String: BBRule] =
        Dictionary(BBRuleset.ios.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    private static let androidSheet: [String: BBRule] =
        Dictionary(BBRuleset.android.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    private static func sheet(_ platform: MobilePlatform) -> [String: BBRule] {
        platform == .android ? androidSheet : iosSheet
    }

    private static func sheetIssue(_ id: String, platform: MobilePlatform) -> BBIssue {
        let rule = sheet(platform)[id]
        let wcag = rule?.wcag ?? ""
        return BBIssue(id: id, title: rule?.issue ?? id, wcag: wcag.isEmpty ? nil : wcag)
    }
}
