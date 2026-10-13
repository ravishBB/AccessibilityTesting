//
//  BBIssueCatalog.swift
//  AccessibilityScanner
//
//  Maps scanner results to BarrierBreak (BB) issue IDs. A rule can produce
//  several BB issues: the pass, fail and manual-review results of one rule
//  usually have different BB IDs, and some rules split further by element
//  role or label (missing vs non-descriptive name, button vs link).
//
//  BB rows marked Dropped, Delete or N/A in the BB sheet are intentionally
//  not mapped. Not-tested results never get a BB ID.
//

import Foundation

struct BBIssue: Codable, Hashable {
    let id: String
    let title: String
}

enum BBIssueCatalog {

    /// Bump whenever a mapping is added, removed or changed.
    static let version = "2026.10.2"

    // MARK: - Lookup

    static func issue(for evaluation: AccessibilityRuleEvaluation) -> BBIssue? {
        guard let id = issueID(for: evaluation) else { return nil }
        return BBIssue(id: id, title: titles[id] ?? id)
    }

    static func title(for id: String) -> String? {
        titles[id]
    }

    private enum Outcome {
        case pass, fail, review
    }

    private static func issueID(for evaluation: AccessibilityRuleEvaluation) -> String? {
        let outcome: Outcome
        switch evaluation.status {
        case .pass: outcome = .pass
        case .fail, .warning: outcome = .fail
        case .validate: outcome = .review
        case .notTested: return nil
        }

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
        case ("accessible-name", .fail): return role == .segmentedControl ? "BB40038" : nil
        case ("interactive-name-descriptive", .fail):
            if role == .segmentedControl { return missingName ? "BB40038" : "BB40037" }
            return "BB40124"
        case ("interactive-name-descriptive", .pass): return "BB40125"
        case ("interactive-name-descriptive", .review): return "BB40051"
        case ("duplicate-interactive-name", .fail): return "BB40090"

        // Colour and contrast
        case ("contrast-standard-text-4-5", .fail): return "BB40018"
        case ("contrast-standard-text-4-5", .pass): return "BB40024"
        case ("contrast-standard-text-4-5", .review): return "BB40008"
        case ("contrast-large-text-3", .fail): return "BB40020"
        case ("contrast-large-text-3", .pass): return "BB40022"
        case ("contrast-large-text-3", .review): return "BB40009"
        case ("contrast-standard-text-7", .fail): return "BB40019"
        case ("contrast-standard-text-7", .pass): return "BB40025"
        case ("contrast-large-text-4-5", .fail): return "BB40021"
        case ("contrast-large-text-4-5", .pass): return "BB40023"
        case ("contrast-text-over-image", .fail): return largeText ? "BB40020" : "BB40018"
        case ("contrast-text-over-image", .pass): return largeText ? "BB40022" : "BB40024"
        case ("contrast-text-over-image", .review): return largeText ? "BB40014" : "BB40010"
        case ("contrast-opacity", .fail): return largeText ? "BB40020" : "BB40018"
        case ("contrast-opacity", .pass): return largeText ? "BB40022" : "BB40024"
        case ("contrast-opacity", .review): return largeText ? "BB40016" : "BB40011"
        case ("link-color-differentiation", _): return "BB40306"
        case ("non-text-contrast", .fail): return "BB40060"
        case ("non-text-contrast", .pass): return "BB40061"
        case ("form-border-contrast", .fail): return "BB40062"
        case ("form-border-contrast", .pass): return "BB40063"
        case ("loading-indicator-contrast", .fail): return "BB40064"
        case ("loading-indicator-contrast", .pass): return "BB40065"
        case ("focus-indicator", .fail): return "BB40073"
        case ("focus-indicator", .pass): return "BB40074"

        // Target size
        case ("touch-target-size-24", .fail): return "BB40030"
        case ("touch-target-size-24", .pass): return "BB40028"
        case ("interactive-target-overlap", .fail): return "BB40180"
        case ("interactive-target-overlap", .pass): return "BB40181"

        // Text size
        case ("text-resize", .fail): return "BB40031"
        case ("text-resize", .pass): return "BB40032"
        case ("text-clipping", .fail): return "BB40033"
        case ("text-clipping", .pass): return "BB40034"

        // Role and state
        case ("heading-quality", .fail): return "BB40128"
        case ("heading-quality", .review): return "BB40040"
        case ("text-link-role", .fail): return "BB40042"
        case ("text-button-role", .fail): return "BB40043"
        case ("role-trait-consistency", .fail): return "BB40274"
        case ("role-trait-consistency", .pass): return "BB40275"
        case ("state-trait-consistency", .fail): return "BB40276"
        case ("state-trait-consistency", .pass): return "BB40277"
        case ("button-disabled-state", .fail): return "BB40079"
        case ("adjustable-accessibility-value", .fail): return "BB40278"
        case ("adjustable-accessibility-value", .pass): return "BB40279"
        case ("state-updates-after-interaction", .fail): return "BB40070"
        case ("state-updates-after-interaction", .review): return "BB40068"

        // Images
        case ("image-accessible-label", .fail): return "BB40086"
        case ("image-accessible-label", .pass): return "BB40085"
        case ("image-name-descriptive", .review): return "BB40045"
        case ("decorative-image", _): return "BB40044"
        case ("map-text-alternative", .fail): return "BB40140"
        case ("map-text-alternative", .pass): return "BB40141"

        // Hidden content
        case ("interactive-screen-reader-hidden", .fail): return role == .button ? "BB40078" : "BB40057"
        case ("interactive-screen-reader-hidden", .pass): return "BB40058"
        case ("interactive-screen-reader-hidden", .review): return "BB40046"
        case ("screen-reader-content", .fail): return "BB40057"
        case ("screen-reader-content", .pass): return "BB40058"
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
            return evaluation.message.contains("locked") ? "BB40056" : "BB40055"
        case ("orientation-support", .review): return "BB40055"

        // Language
        case ("language", .fail): return "BB40105"
        case ("language", .pass): return "BB40106"
        case ("language-change", .fail): return "BB40107"

        // Modal
        case ("modal-focus-containment", .pass): return "BB40245"

        // Live region and timing
        case ("live-region", .fail): return "BB40103"
        case ("live-region", .pass): return "BB40104"
        case ("time-limited-ui", .pass), ("time-limited-ui", .review): return "BB40111"

        // Keyboard
        case ("keyboard-focus", .fail): return "BB40066"
        case ("keyboard-focus-hidden-content", .fail): return "BB41015"
        case ("keyboard-focus-noninteractive", .fail): return "BB41005"
        case ("keyboard-activation", .fail): return role == .link ? "BB41067" : "BB41035"
        case ("gesture-keyboard-operable", .fail): return "BB40071"
        case ("gesture-keyboard-operable", .pass): return "BB40072"

        // Gestures and pointer
        case ("complex-gesture-alternative", .fail),
             ("multi-point-gesture-alternative", .fail),
             ("path-based-gesture-alternative", .fail): return "BB40190"
        case ("complex-gesture-alternative", .pass),
             ("multi-point-gesture-alternative", .pass),
             ("path-based-gesture-alternative", .pass): return "BB40191"
        case ("touch-up-cancellation", .fail): return "BB40136"
        case ("touch-up-cancellation", .pass): return "BB40137"
        case ("motion-alternative", .pass): return "BB40102"

        // Forms and errors
        case ("form-visual-label", .fail), ("visual-label", .fail): return "BB40093"
        case ("form-visual-label", .pass), ("visual-label", .pass): return "BB40094"
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

    // MARK: - Titles (from the BB issue sheet)

    private static let titles: [String: String] = [
        "BB40002": "Verify if accessible name for button is descriptive",
        "BB40003": "Missing accessible name for button",
        "BB40004": "Missing accessible name for image button",
        "BB40008": "Verify if color contrast for standard text with its background is sufficient",
        "BB40009": "Verify if color contrast for large text with its background is sufficient",
        "BB40010": "Check if the contrast ratio of standard text between the foreground and background image is 4.5:1",
        "BB40011": "Check if the contrast ratio of standard text between the foreground and background with opacity is 4.5:1",
        "BB40014": "Check if the contrast ratio of large text between the foreground and background image is 3:1",
        "BB40016": "Check if the contrast ratio of large text between the foreground and background with opacity is 3:1",
        "BB40018": "Insufficient color contrast for standard text",
        "BB40019": "Standard text does not have enhanced contrast with its background",
        "BB40020": "Insufficient color contrast for large text",
        "BB40021": "Large text does not have enhanced contrast with its background",
        "BB40022": "Large text meets the required 3:1 contrast ratio between the foreground and background color",
        "BB40023": "Large text meets the required 4.5:1 contrast ratio between the foreground and background color",
        "BB40024": "Standard text meets the required 4.5:1 contrast ratio between the foreground and background color",
        "BB40025": "Standard text meets the required 7:1 contrast ratio between the foreground and background color",
        "BB40028": "Interactive controls meet the minimum target size (24pt) requirement",
        "BB40030": "Interactive control doesn't meet minimum target size requirements",
        "BB40031": "Text fails to resize",
        "BB40032": "Text can be resized",
        "BB40033": "Text getting clipped",
        "BB40034": "Text displays correctly",
        "BB40035": "Check if segmented controls needs to be interactive",
        "BB40036": "Check if tab control needs to be hidden for screen reader user",
        "BB40037": "Check if segment control name is descriptive",
        "BB40038": "Missing accessible name for segment control button",
        "BB40040": "Check if Provided headings should be marked as heading",
        "BB40042": "Text functions as a link but is missing role link",
        "BB40043": "Text functions as a button but is missing role button",
        "BB40044": "Check if Image should be marked as decorative",
        "BB40045": "Check if image has correct textual description",
        "BB40046": "Check if interactive control needs to be hidden for screen reader user",
        "BB40051": "Check if interactive control name is descriptive",
        "BB40053": "Check if focus order is correct on the screen",
        "BB40054": "Screen has correct focus order",
        "BB40055": "Check if all the content is available when the device orientation is changed to landscape or portrait mode",
        "BB40056": "Screen is locked in orientation",
        "BB40057": "Content hidden from screen reader user",
        "BB40058": "Content can be accessed by screen reader user",
        "BB40060": "Insufficient color contrast for non-text element",
        "BB40061": "Non-text element has sufficient contrast with its background",
        "BB40062": "Insufficient color contrast for border of form controls",
        "BB40063": "Border of form controls has sufficient contrast with its background",
        "BB40064": "Insufficient color contrast for loading indicator",
        "BB40065": "Loading indicator has sufficient contrast with its background",
        "BB40066": "Interactive control cannot receive keyboard focus",
        "BB40068": "Verify if the state for interactive control gets updated on user interaction",
        "BB40070": "State does not get updated on user interaction",
        "BB40071": "Gesture-only control not operable with keyboard",
        "BB40072": "Gesture-only control is operable with keyboard",
        "BB40073": "Focus indicator is not visible",
        "BB40074": "Focus indicator is clearly visible",
        "BB40078": "Button hidden from screen reader users",
        "BB40079": "Disabled state of button not defined",
        "BB40085": "Image has label",
        "BB40086": "Missing accessible label for image",
        "BB40090": "Interactive elements have identical accessible name",
        "BB40091": "Missing autocomplete information for form field",
        "BB40092": "Autocomplete information is specified for form field",
        "BB40093": "Missing visual label for form control",
        "BB40094": "Visual label is specified for form control",
        "BB40095": "Error message not announced by screen reader",
        "BB40096": "Check if error message includes a suggestion to fix it",
        "BB40097": "Error message is accessible and includes a suggestion to fix it",
        "BB40099": "Title is specified for screen",
        "BB40102": "Accessible alternative control is available for motion-based action",
        "BB40103": "Live region not defined for dynamic content",
        "BB40104": "Live region is defined for dynamic content",
        "BB40105": "Missing app language",
        "BB40106": "App language is defined",
        "BB40107": "Change in language not defined correctly",
        "BB40111": "Time-limited UI has a visible user control",
        "BB40124": "Non-descriptive accessible name for interactive element",
        "BB40125": "Accessible name for interactive element is descriptive",
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
        "BB40274": "Accessibility role trait does not match element type",
        "BB40275": "Accessibility role trait correctly matches element type",
        "BB40276": "Accessibility state trait does not match element's actual state",
        "BB40277": "Accessibility state trait correctly reflects element's actual state",
        "BB40278": "Adjustable element missing accessibilityValue",
        "BB40279": "Adjustable element exposes accessibilityValue",
        "BB40306": "Link color differentiation check",
        "BB41005": "Non-interactive element receives keyboard focus",
        "BB41015": "Hidden content receives keyboard focus",
        "BB41035": "Button not operable with keyboard",
        "BB41067": "Link not keyboard operable"
    ]
}
