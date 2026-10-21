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
    static let version = "2026.10.21"

    // MARK: - Lookup

    static func issue(for evaluation: AccessibilityRuleEvaluation) -> BBIssue? {
        guard let id = issueID(for: evaluation) else { return nil }
        var criterion = wcag[id]
        if id == "BB40034" {
            criterion = evaluation.status == .pass ? "1.4.10" : "3.3.2"
        }
        let title = id == "BB40034" && evaluation.status != .pass
            ? "Placeholder text used as the only accessible name — no visible label present"
            : titles[id] ?? id
        return BBIssue(id: id, title: title, wcag: criterion)
    }

    static func title(for id: String) -> String? {
        titles[id]
    }

    /// How a result is headed in reports: the BB code, with the sheet's
    /// issue text as its description. A Validate result whose check only has
    /// a Fail code shows the code to log if confirmed. Results with no BB
    /// code keep the scanner's rule name.
    /// The sheet's issue text is the heading; codes are not shown in the
    /// report (they stay in the JSON export).
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

    /// The code a result is reported under. Its Type in the BB sheet always
    /// equals the result's status: a Validate result never shows a Fail code.
    private static func issueID(for evaluation: AccessibilityRuleEvaluation) -> String? {
        mappedID(for: evaluation)
    }

    /// For a Validate result whose check has only a Fail code in the sheet:
    /// the code the tester logs if the issue is confirmed.
    static func ifConfirmed(for evaluation: AccessibilityRuleEvaluation) -> BBIssue? {
        guard evaluation.status == .validate, mappedID(for: evaluation) == nil,
              let id = mappedID(for: evaluation, outcomeOverride: .fail)
        else { return nil }
        return BBIssue(id: id, title: titles[id] ?? id, wcag: wcag[id])
    }

    private static func mappedID(for evaluation: AccessibilityRuleEvaluation, outcomeOverride: Outcome? = nil) -> String? {
        var outcome: Outcome
        switch evaluation.status {
        case .pass: outcome = .pass
        case .fail, .warning: outcome = .fail
        case .validate: outcome = .review
        case .notTested: return nil
        }
        if let outcomeOverride { outcome = outcomeOverride }

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
        case ("name-via-hint", .fail): return "BB40049"
        case ("label-in-name", .fail): return role == .button ? "BB40088" : "BB40121"
        case ("label-in-name", .pass): return "BB40089"
        case ("interactive-name-descriptive", .fail): return "BB40124"
        case ("interactive-name-descriptive", .pass): return "BB40125"
        case ("interactive-name-descriptive", .review): return role == .segmentedControl ? "BB40037" : "BB40051"
        case ("duplicate-interactive-name", .fail): return "BB40090"
        case ("placeholder-only-name", .fail): return "BB40034"

        // Colour and contrast
        case ("contrast-standard-text-4-5", .fail): return "BB40018"
        case ("contrast-standard-text-4-5", .pass): return "BB40024"
        case ("contrast-standard-text-4-5", .review): return "BB40008"
        case ("contrast-large-text-3", .fail): return "BB40020"
        case ("contrast-large-text-3", .pass): return "BB40022"
        case ("contrast-large-text-3", .review): return "BB40009"
        case ("contrast-text-over-image", .fail): return largeText ? "BB40020" : "BB40018"
        case ("contrast-text-over-image", .pass): return largeText ? "BB40022" : "BB40024"
        case ("contrast-text-over-image", .review): return largeText ? "BB40014" : "BB40010"
        case ("contrast-opacity", .fail): return largeText ? "BB40020" : "BB40018"
        case ("contrast-opacity", .pass): return largeText ? "BB40022" : "BB40024"
        case ("contrast-opacity", .review): return largeText ? "BB40016" : "BB40011"
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

        // Target size
        case ("touch-target-size-24", .fail): return "BB40030"
        case ("touch-target-size-24", .pass): return "BB40028"

        // Text size
        case ("text-resize", .fail): return "BB40031"
        case ("text-resize", .pass): return "BB40032"
        case ("text-clipping", .fail): return "BB40033"
        case ("text-clipping", .pass): return "BB40034"
        case ("text-truncation", .fail), ("text-overlap", .fail): return "BB40033"
        case ("text-truncation", .pass), ("text-overlap", .pass): return "BB40034"
        case ("focus-indicator-color-only", .fail): return "BB40119"
        case ("focus-indicator-color-only", .pass): return "BB40120"

        // Role
        case ("heading-quality", .fail): return "BB40128"
        case ("heading-quality", .review): return "BB40040"
        case ("heading-candidate", .review): return "BB40041"
        case ("missing-role", .fail): return "BB40282"
        case ("icon-control-role", .fail), ("row-role", .fail): return "BB40282"
        case ("missing-role", .pass): return "BB40275"
        case ("text-link-role", .fail): return "BB40042"
        case ("text-button-role", .fail): return "BB40043"
        case ("role-trait-consistency", .fail): return "BB40281"
        case ("role-trait-consistency", .pass): return "BB40275"

        // State and value
        case ("button-disabled-state", .fail): return "BB40079"
        case ("state-trait-consistency", .fail): return "BB40069"
        case ("state-trait-consistency", .pass): return "BB40277"
        case ("adjustable-accessibility-value", .fail): return "BB40278"
        case ("adjustable-accessibility-value", .pass): return "BB40279"
        case ("state-updates-after-interaction", .fail): return "BB40280"
        case ("state-updates-after-interaction", .review): return "BB40068"

        // Images
        case ("image-accessible-label", .pass): return "BB40085"
        case ("image-name-descriptive", .fail): return "BB40126"
        case ("image-name-descriptive", .review): return "BB40045"
        case ("decorative-image", .review): return "BB40044"
        case ("map-text-alternative", .fail): return "BB40140"
        case ("map-text-alternative", .pass): return "BB40141"

        // Hidden content
        case ("interactive-screen-reader-hidden", .fail): return role == .button ? "BB40078" : "BB40046"
        case ("interactive-screen-reader-hidden", .pass): return "BB40058"
        case ("interactive-screen-reader-hidden", .review): return "BB40307"
        case ("screen-reader-content", .fail): return "BB40057"
        case ("screen-reader-content", .pass): return "BB40058"
        case ("screen-reader-content", .review): return "BB40307"
        case ("segmented-control-interactive", .review): return "BB40035"
        case ("tab-accessibility", .review): return "BB40036"

        // Focus and reading order
        case ("focus-order", .fail), ("screen-reader-focus-order", .fail): return "BB40053"
        case ("focus-order", .review), ("screen-reader-focus-order", .review): return "BB40053"
        case ("focus-order", .pass), ("screen-reader-focus-order", .pass): return "BB40054"
        case ("reading-order", .fail): return "BB40134"
        case ("reading-order", .pass): return "BB40135"

        // Orientation
        case ("orientation-support", .fail):
            return evaluation.message.contains("locked") ? "BB40056" : nil
        case ("orientation-support", .review): return "BB40055"

        // Language
        case ("language", .fail): return "BB40105"
        case ("language", .pass): return "BB40106"
        case ("language-change", .fail): return "BB40107"
        case ("language-change", .pass): return "BB40108"

        // Modal
        case ("modal-focus-containment", .pass): return "BB40245"
        case ("modal-closable", .pass): return "BB40114"
        case ("modal-focus-containment", .fail):
            return evaluation.message.contains("no keyboard-focusable") ? "BB40244" : nil

        // Live region
        case ("live-region", .fail): return "BB40103"
        case ("live-region", .pass): return "BB40104"

        // Keyboard
        case ("keyboard-focus", .fail): return "BB40066"
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
        case ("error-message-suggestion", .pass): return "BB40097"

        // Screen
        case ("screen-title", .pass): return "BB40099"

        default: return nil
        }
    }

    private static let wcag: [String: String] = [
        "BB40114": "2.1.1",
        "BB40075": "2.4.11",
        "BB40118": "1.4.11",
        "BB40117": "1.4.11",
        "BB40282": "4.1.2",
        "BB40244": "2.1.1",
        "BB40121": "2.5.3",
        "BB40089": "2.5.3",
        "BB40088": "2.5.3",
        "BB40049": "4.1.2",
        "BB40041": "1.3.1",
        "BB40039": "1.1.1",
        "BB30548": "4.1.2",
        "BB40002": "2.4.6",
        "BB40003": "4.1.2",
        "BB40004": "1.1.1",
        "BB40008": "1.4.3",
        "BB40009": "1.4.3",
        "BB40010": "1.4.3",
        "BB40011": "1.4.3",
        "BB40014": "1.4.3",
        "BB40016": "1.4.3",
        "BB40018": "1.4.3",
        "BB40019": "1.4.6",
        "BB40020": "1.4.3",
        "BB40021": "1.4.6",
        "BB40022": "1.4.3",
        "BB40023": "1.4.3",
        "BB40024": "1.4.3",
        "BB40025": "1.4.3",
        "BB40027": "2.5.5",
        "BB40028": "2.5.8",
        "BB40029": "2.5.5",
        "BB40030": "2.5.8",
        "BB40031": "1.4.4",
        "BB40032": "1.4.4",
        "BB40033": "1.4.4",
        "BB40119": "1.4.1",
        "BB40120": "1.4.1",
        "BB40035": "2.1.1",
        "BB40036": "4.1.2",
        "BB40037": "4.1.2",
        "BB40038": "4.1.2",
        "BB40040": "1.3.1",
        "BB40042": "4.1.2",
        "BB40043": "4.1.2",
        "BB40044": "1.1.1",
        "BB40045": "1.1.1",
        "BB40046": "4.1.2",
        "BB40051": "2.4.6",
        "BB40052": "2.5.4",
        "BB40053": "2.4.3",
        "BB40054": "2.4.3",
        "BB40055": "1.3.4",
        "BB40056": "1.3.4",
        "BB40057": "1.3.1",
        "BB40058": "1.3.1",
        "BB40060": "1.4.11",
        "BB40061": "1.4.11",
        "BB40062": "1.4.11",
        "BB40063": "1.4.11",
        "BB40064": "1.4.11",
        "BB40065": "1.4.11",
        "BB40066": "2.1.1",
        "BB40068": "4.1.2",
        "BB40069": "4.1.2",
        "BB40071": "2.1.1",
        "BB40072": "2.1.1",
        "BB40073": "2.4.7",
        "BB40074": "2.4.7",
        "BB40078": "1.3.1",
        "BB40079": "4.1.2",
        "BB40085": "1.1.1",
        "BB40086": "1.1.1",
        "BB40090": "4.1.2",
        "BB40091": "1.3.5",
        "BB40092": "1.3.5",
        "BB40093": "3.3.2",
        "BB40094": "3.3.2",
        "BB40095": "4.1.3",
        "BB40096": "3.3.1",
        "BB40097": "3.3.3",
        "BB40099": "2.4.2",
        "BB40102": "2.5.4",
        "BB40103": "4.1.3",
        "BB40104": "4.1.3",
        "BB40105": "3.1.1",
        "BB40106": "3.1.1",
        "BB40107": "3.1.2",
        "BB40108": "3.1.2",
        "BB40124": "4.1.2",
        "BB40125": "2.4.6",
        "BB40126": "1.1.1",
        "BB40128": "2.4.6",
        "BB40134": "1.3.2",
        "BB40135": "1.3.2",
        "BB40136": "2.5.2",
        "BB40137": "2.5.2",
        "BB40140": "1.1.1",
        "BB40141": "1.1.1",
        "BB40180": "2.5.8",
        "BB40181": "2.5.8",
        "BB40190": "2.1.1",
        "BB40191": "2.1.1",
        "BB40245": "2.1.1",
        "BB40275": "4.1.2",
        "BB40277": "4.1.2",
        "BB40278": "4.1.2",
        "BB40279": "4.1.2",
        "BB40280": "4.1.2",
        "BB40281": "4.1.2",
        "BB40283": "2.1.1",
        "BB40306": "1.4.1",
        "BB41005": "2.4.3",
        "BB41015": "2.4.3",
        "BB41035": "2.1.1",
        "BB41067": "2.1.1"
    ]

    // MARK: - Titles
    private static let titles: [String: String] = [
        "BB40114": "Modal dialog can be closed",
        "BB40075": "Check if focus indicator is obscured by another element",
        "BB40118": "Focus indicator has sufficient contrast with its background",
        "BB40117": "Insufficient color contrast for focus indicator",
        "BB40282": "Missing role for interactive element",
        "BB40244": "Modal has no keyboard-focusable interactive controls",
        "BB40121": "Accessible name for interactive control and its visual label don't match",
        "BB40089": "Accessible name for button matches its visual label",
        "BB40088": "Accessible name for button and its visual label don't match",
        "BB40049": "Accessible name for button incorrectly specified using hint",
        "BB40041": "Check if the text should be a heading",
        "BB40039": "Missing accessible name for image segmented control",
        "BB30548": "Missing accessible name for interactive control",
        "BB40002": "Verify if accessible name specified for button is descriptive",
        "BB40003": "Missing accessible name for button",
        "BB40004": "Missing accessible name for image button",
        "BB40008": "Check if color contrast for standard text with its background is sufficient",
        "BB40009": "Check if color contrast for large text with its background is sufficient",
        "BB40010": "Check if color contrast for standard text displayed on background image is sufficient",
        "BB40011": "Check if color contrast for standard text and its background with opacity is sufficient",
        "BB40014": "Check if color contrast for large text displayed on background image is sufficient",
        "BB40016": "Check if color contrast for large text and its background with opacity is sufficient",
        "BB40018": "Insufficient color contrast for standard text",
        "BB40019": "Standard text does not have enhanced contrast with its background",
        "BB40020": "Insufficient color contrast for large text",
        "BB40021": "Large text does not have enhanced contrast with its background",
        "BB40022": "Large text has sufficient contrast with its background",
        "BB40023": "Large text meets the required 4.5:1 contrast ratio between the foreground and background color",
        "BB40024": "Standard text has sufficient contrast with its background",
        "BB40025": "Standard text meets the required 7:1 contrast ratio between the foreground and background color",
        "BB40027": "Interactive controls meet the enhanced target size (44pt) requirement",
        "BB40028": "Interactive controls meet the minimum target size requirement",
        "BB40029": "Interactive control doesn't meet enhanced target size requirements",
        "BB40030": "Interactive control doesn't meet minimum target size requirements",
        "BB40031": "Text fails to resize",
        "BB40032": "Text can be resized",
        "BB40033": "Text content is clipped at larger font sizes",
        "BB40119": "Color alone used to indicate focus",
        "BB40120": "Focus indicator uses more than color alone",
        "BB40034": "Text displays correctly",
        "BB40035": "Check if segmented controls needs to be interactive",
        "BB40036": "Check if the tab control needs to be hidden from screen reader users",
        "BB40037": "Verify if accessible name specified for segmented control is descriptive",
        "BB40038": "Missing accessible name for segmented control",
        "BB40040": "Check if provided headings should be marked as heading",
        "BB40042": "Text functions as a link but is missing role link",
        "BB40043": "Text functions as a button but is missing role button",
        "BB40044": "Verify if the image is decorative",
        "BB40045": "Verify if the image has an accurate textual description",
        "BB40046": "Interactive controls hidden for screen reader user",
        "BB40051": "Verify if accessible name specified for interactive control is descriptive",
        "BB40052": "Missing alternative control for motion-based action",
        "BB40053": "Check if the focus order on the screen is correct",
        "BB40054": "Screen has correct focus order",
        "BB40055": "Check if content is available in portrait and landscape orientations",
        "BB40056": "Screen orientation is locked at portrait or landscape mode",
        "BB40057": "Content not available for screen reader users",
        "BB40058": "Content can be accessed by screen reader user",
        "BB40060": "Insufficient color contrast for non-text element",
        "BB40061": "Non-text element has sufficient contrast with its background",
        "BB40062": "Insufficient color contrast for border of form controls",
        "BB40063": "Border of form controls has sufficient contrast with its background",
        "BB40064": "Insufficient color contrast for loading indicator",
        "BB40065": "Loading indicator has sufficient contrast with its background",
        "BB40066": "Interactive control fails to receive keyboard focus",
        "BB40068": "Check if state of the interactive control gets updated on user interaction",
        "BB40069": "Incorrect state provided for interactive control",
        "BB40071": "Gesture-only control not operable with keyboard",
        "BB40072": "Gesture-only control is operable with keyboard",
        "BB40073": "Focus indicator is not visible",
        "BB40074": "Focus indicator is visible",
        "BB40078": "Button hidden from screen reader users",
        "BB40079": "Disabled state of button not defined",
        "BB40085": "Image has label",
        "BB40086": "Missing accessible label for image",
        "BB40090": "Interactive controls with identical accessible name",
        "BB40091": "Missing autocomplete information for form field",
        "BB40092": "Autocomplete information is specified for form field",
        "BB40093": "Missing visual label for form control",
        "BB40094": "Visual label is specified for form control",
        "BB40095": "Error message not announced for screen reader users",
        "BB40096": "Check if error message for form field is descriptive",
        "BB40097": "Error message is accessible and includes a suggestion to fix it",
        "BB40099": "Title is specified for screen",
        "BB40102": "Accessible alternative control is available for motion-based action",
        "BB40103": "Live region not defined for dynamic content",
        "BB40104": "Live region is defined for dynamic content",
        "BB40105": "Missing app language",
        "BB40106": "App language is defined",
        "BB40107": "Change in language not defined correctly",
        "BB40108": "Change in language is defined correctly",
        "BB40124": "Non-descriptive accessible name for interactive control",
        "BB40125": "Accessible name for interactive element is descriptive",
        "BB40126": "Non-descriptive textual description provided for image",
        "BB40128": "Non-descriptive heading text",
        "BB40134": "Inaccurate reading order",
        "BB40135": "Reading order is accurate",
        "BB40136": "Action fires on touch down instead of touch up",
        "BB40137": "Action fires on touch up, allowing cancellation",
        "BB40140": "Missing textual description for map",
        "BB40141": "Map view has a text alternative",
        "BB40180": "Target size or spacing too small",
        "BB40181": "Target size and spacing adequate",
        "BB40190": "Complex gesture has no accessibility alternative",
        "BB40191": "Custom action present for gesture",
        "BB40245": "Modal contains keyboard-focusable controls — keyboard focus can be contained",
        "BB40275": "Correct role provided for interactive element",
        "BB40277": "Accessibility state trait correctly reflects element's actual state",
        "BB40278": "Missing value for adjustable control",
        "BB40279": "Value is provided for adjustable control",
        "BB40280": "State of interactive control does not get updated on user interaction",
        "BB40281": "Incorrect role provided for interactive element",
        "BB40283": "Interactive control not operable with keyboard",
        "BB40306": "Check if color alone is used to distinguish link",
        "BB40307": "Check if content needs to be hidden from screen reader user",
        "BB41005": "Non-interactive element receives keyboard focus",
        "BB41015": "Hidden content receives keyboard focus",
        "BB41035": "Button not operable with keyboard",
        "BB41067": "Link not operable with keyboard"
    ]
}
