//
//  AccessibilityRuleCatalog.swift
//  AccessibilityScanner
//
//  Single source of truth for rule metadata: WCAG 2.2 mapping, user impact,
//  who is affected, and how a tester verifies the result by hand.
//  Keyed by `AccessibilityRule.id` / `AccessibilityRuleEvaluation.ruleID`.
//

import Foundation

/// How badly a confirmed failure of a rule affects users. This is independent
/// of the per-evaluation `AccessibilityFinding.Severity`, which describes the
/// scanner's confidence/priority for one concrete element.
enum AccessibilityImpact: String, Codable, CaseIterable {
    case critical   // blocks a task for some users
    case serious    // causes major difficulty
    case moderate   // causes difficulty or annoyance
    case minor      // polish / best practice

    var displayName: String { rawValue.capitalized }

    /// Lower is more important. Used for sorting.
    var rank: Int {
        switch self {
        case .critical: return 0
        case .serious: return 1
        case .moderate: return 2
        case .minor: return 3
        }
    }
}

struct AccessibilityRuleMetadata: Codable, Hashable {
    let ruleID: String
    /// WCAG 2.2 success criterion number, e.g. "4.1.2". Nil when no criterion applies.
    let wcagCriterion: String?
    let wcagTitle: String?
    /// "A", "AA" or "AAA".
    let wcagLevel: String?
    let impact: AccessibilityImpact
    let affectedUsers: String
    let howToTest: String

    var wcagLabel: String? {
        guard let wcagCriterion else { return nil }
        if let wcagLevel {
            return "WCAG \(wcagCriterion) (\(wcagLevel))"
        }
        return "WCAG \(wcagCriterion)"
    }
}

enum AccessibilityRuleCatalog {

    /// Bump whenever a rule is added, removed, re-mapped or its logic changes.
    static let version = "2026.10.1"

    static func metadata(for ruleID: String) -> AccessibilityRuleMetadata {
        if let known = table[ruleID] { return known }
        return AccessibilityRuleMetadata(
            ruleID: ruleID,
            wcagCriterion: nil,
            wcagTitle: nil,
            wcagLevel: nil,
            impact: .moderate,
            affectedUsers: "Users of assistive technology",
            howToTest: "Reproduce the finding on the device with VoiceOver/TalkBack enabled and confirm the behaviour described."
        )
    }

    static var allMetadata: [AccessibilityRuleMetadata] {
        table.values.sorted { $0.ruleID < $1.ruleID }
    }

    static var ruleCount: Int { table.count }

    // MARK: - Table

    private static func e(
        _ id: String,
        _ criterion: String?,
        _ title: String?,
        _ level: String?,
        _ impact: AccessibilityImpact,
        _ users: String,
        _ test: String
    ) -> (String, AccessibilityRuleMetadata) {
        (
            id,
            AccessibilityRuleMetadata(
                ruleID: id,
                wcagCriterion: criterion,
                wcagTitle: title,
                wcagLevel: level,
                impact: impact,
                affectedUsers: users,
                howToTest: test
            )
        )
    }

    private static let sr = "Screen reader users"
    private static let nameTest = "Move VoiceOver/TalkBack focus to the control and confirm the announced name describes its purpose."
    private static let contrastTest = "Inspect the element at normal brightness and confirm the text is clearly readable against its background."
    private static let targetTest = "Activate the control near its edges and confirm it is easy to hit without touching neighbouring controls."

    private static let entries: [(String, AccessibilityRuleMetadata)] = [

        // Name, role, value
        e("accessible-name", "4.1.2", "Name, Role, Value", "A", .critical, "\(sr), voice control users", nameTest),
        e("button-name-descriptive", "4.1.2", "Name, Role, Value", "A", .serious, "\(sr), voice control users", nameTest),
        e("image-button-name", "4.1.2", "Name, Role, Value", "A", .critical, "\(sr), voice control users", nameTest),
        e("interactive-name-descriptive", "4.1.2", "Name, Role, Value", "A", .serious, "\(sr), voice control users", nameTest),
        e("placeholder-only-name", "3.3.2", "Labels or Instructions", "A", .serious, "\(sr), users with cognitive disabilities", "Focus the field once it contains text and confirm VoiceOver/TalkBack still announces a name for it."),
        e("adjustable-accessibility-value", "4.1.2", "Name, Role, Value", "A", .serious, sr, "Adjust the control with swipe up/down and confirm the new value is announced."),
        e("button-disabled-state", "4.1.2", "Name, Role, Value", "A", .moderate, sr, "Focus the disabled control and confirm it is announced as dimmed/disabled."),
        e("role-trait-consistency", "4.1.2", "Name, Role, Value", "A", .serious, sr, "Focus the element and confirm the announced role (button, link, header...) matches how it behaves."),
        e("state-trait-consistency", "4.1.2", "Name, Role, Value", "A", .serious, sr, "Toggle the control and confirm the selected/checked/expanded state is announced."),
        e("text-link-role", "4.1.2", "Name, Role, Value", "A", .moderate, sr, "Focus the link text and confirm it is announced as a link."),
        e("text-button-role", "4.1.2", "Name, Role, Value", "A", .moderate, sr, "Focus the tappable text and confirm it is announced as a button."),
        e("interactive-screen-reader-hidden", "4.1.2", "Name, Role, Value", "A", .critical, sr, "Swipe through the screen with VoiceOver/TalkBack and confirm this control can be reached."),
        e("segmented-control-interactive", "4.1.2", "Name, Role, Value", "A", .serious, sr, "Move focus across the segments and confirm each is announced with its selected state."),
        e("tab-accessibility", "4.1.2", "Name, Role, Value", "A", .serious, sr, "Move focus across the tabs and confirm each is announced as a tab with its selected state and position."),

        // Non-text content
        e("image-accessible-label", "1.1.1", "Non-text Content", "A", .serious, sr, "Focus the image and confirm the announced text conveys the same information."),
        e("image-name-descriptive", "1.1.1", "Non-text Content", "A", .moderate, sr, "Focus the image and confirm the label is meaningful and not a file name."),
        e("decorative-image", "1.1.1", "Non-text Content", "A", .minor, sr, "Swipe through the screen and confirm purely decorative images are skipped."),
        e("map-text-alternative", "1.1.1", "Non-text Content", "A", .serious, "\(sr), users who cannot see the map", "Confirm the same information shown on the map is available as text or a list."),

        // Info and relationships / sequence
        e("heading-quality", "1.3.1", "Info and Relationships", "A", .moderate, sr, "Use the rotor/headings navigation and confirm headings are marked and describe their sections."),
        e("screen-reader-content", "1.3.1", "Info and Relationships", "A", .serious, sr, "Navigate the screen with VoiceOver/TalkBack and confirm all visible content is announced."),
        e("reading-order", "1.3.2", "Meaningful Sequence", "A", .serious, "\(sr), keyboard users", "Swipe through the screen sequentially and confirm focus follows the intended reading order."),
        e("orientation-support", "1.3.4", "Orientation", "AA", .moderate, "Users with a mounted device", "Rotate the device and confirm content and controls remain available."),
        e("form-autocomplete", "1.3.5", "Identify Input Purpose", "AA", .minor, "Users with cognitive or motor disabilities", "Focus personal-data fields and confirm autofill suggestions are offered."),

        // Colour and contrast
        e("link-color-differentiation", "1.4.1", "Use of Color", "A", .moderate, "Users with colour blindness", "View the link text in greyscale and confirm links are distinguishable from surrounding text."),
        e("contrast-standard-text-4-5", "1.4.3", "Contrast (Minimum)", "AA", .serious, "Low-vision and colour-blind users", contrastTest),
        e("contrast-large-text-3", "1.4.3", "Contrast (Minimum)", "AA", .serious, "Low-vision and colour-blind users", contrastTest),
        e("contrast-text-over-image", "1.4.3", "Contrast (Minimum)", "AA", .serious, "Low-vision users", contrastTest),
        e("contrast-opacity", "1.4.3", "Contrast (Minimum)", "AA", .moderate, "Low-vision users", contrastTest),
        e("contrast-standard-text-7", "1.4.6", "Contrast (Enhanced)", "AAA", .minor, "Low-vision users", contrastTest),
        e("contrast-large-text-4-5", "1.4.6", "Contrast (Enhanced)", "AAA", .minor, "Low-vision users", contrastTest),
        e("non-text-contrast", "1.4.11", "Non-text Contrast", "AA", .serious, "Low-vision users", "Inspect icons and control boundaries and confirm they are clearly distinguishable."),
        e("form-border-contrast", "1.4.11", "Non-text Contrast", "AA", .moderate, "Low-vision users", "Inspect the field border and confirm it is clearly visible against the background."),
        e("loading-indicator-contrast", "1.4.11", "Non-text Contrast", "AA", .minor, "Low-vision users", "Inspect the loading indicator and confirm it is clearly visible."),

        // Text resizing and spacing
        e("text-resize", "1.4.4", "Resize Text", "AA", .serious, "Low-vision users", "Increase the system text size to the maximum and confirm text stays readable without clipping or overlap."),
        e("text-clipping", "1.4.4", "Resize Text", "AA", .serious, "Low-vision users", "Increase the system text size and confirm no text is cut off or truncated."),
        e("text-spacing", "1.4.12", "Text Spacing", "AA", .moderate, "Users with dyslexia or low vision", "Increase text spacing settings and confirm content does not overlap or get cut off."),

        // Keyboard / focus / gestures
        e("keyboard-focus", "2.1.1", "Keyboard", "A", .critical, "Keyboard and switch-control users", "Use a hardware keyboard Tab/Shift-Tab and confirm the control can receive focus and be activated."),
        e("gesture-keyboard-operable", "2.1.1", "Keyboard", "A", .critical, "Keyboard and switch-control users", "Confirm the gesture action can also be performed with the keyboard or a simple control."),
        e("modal-accessibility", "2.1.2", "No Keyboard Trap", "A", .serious, "\(sr), keyboard users", "Open the dialog, confirm focus moves into it and can leave it, and returns correctly on dismissal."),
        e("modal-focus-containment", "2.4.3", "Focus Order", "A", .serious, "\(sr), keyboard users", "Open the dialog and confirm focus stays inside until it is dismissed."),
        e("focus-order", "2.4.3", "Focus Order", "A", .serious, "\(sr), keyboard users", "Move focus sequentially and confirm the order is logical."),
        e("focus-indicator", "2.4.7", "Focus Visible", "AA", .serious, "Keyboard users", "Tab through the screen and confirm the focused element has a visible indicator."),
        e("complex-gesture-alternative", "2.5.1", "Pointer Gestures", "A", .serious, "Users with motor disabilities", "Confirm multi-finger or path gestures have a single-tap alternative."),
        e("touch-up-cancellation", "2.5.2", "Pointer Cancellation", "A", .moderate, "Users with motor disabilities", "Press on the control, slide away and release; confirm the action does not fire."),
        e("motion-alternative", "2.5.4", "Motion Actuation", "A", .moderate, "Users with motor disabilities", "Perform the motion interaction and confirm an equivalent non-motion control exists."),
        e("visual-label", "2.5.3", "Label in Name", "A", .serious, "Voice control users", "Say the visible label aloud with Voice Control and confirm the control activates."),
        e("form-visual-label", "3.3.2", "Labels or Instructions", "A", .serious, "\(sr), users with cognitive disabilities", "Focus the field and confirm the announced name matches the visible label."),

        // Target size
        e("target-size-minimum-24", "2.5.8", "Target Size (Minimum)", "AA", .moderate, "Users with motor disabilities", targetTest),
        e("touch-target-size-24", "2.5.8", "Target Size (Minimum)", "AA", .moderate, "Users with motor disabilities", targetTest),
        e("interactive-target-overlap", "2.5.8", "Target Size (Minimum)", "AA", .serious, "Users with motor disabilities", "Try activating each overlapping control and confirm the intended one responds."),
        e("target-size-enhanced-44", "2.5.5", "Target Size (Enhanced)", "AAA", .minor, "Users with motor disabilities", targetTest),
        e("touch-target-size-44", "2.5.5", "Target Size (Enhanced)", "AAA", .minor, "Users with motor disabilities", targetTest),

        // Navigation / labels
        e("screen-title", "2.4.2", "Page Titled / Screen Title", "A", .moderate, sr, "Open the screen and confirm a title that identifies it is announced."),
        e("duplicate-interactive-name", "2.4.6", "Headings and Labels", "AA", .moderate, "\(sr), voice control users", "Move through the controls and confirm identical names are distinguishable by context."),

        // Language and timing
        e("language", "3.1.1", "Language of Page / App", "A", .moderate, sr, "Use VoiceOver/TalkBack on the content and confirm pronunciation matches the language."),
        e("language-change", "3.1.2", "Language of Parts", "AA", .minor, sr, "Focus content in a different language and confirm it is pronounced correctly."),
        e("time-limited-ui", "2.2.1", "Timing Adjustable", "A", .serious, "Users who need more time", "Let the timer approach expiry and confirm the user can extend or disable the limit."),

        // Errors and status
        e("error-message-accessibility", "3.3.1", "Error Identification", "A", .serious, "\(sr), users with cognitive disabilities", "Trigger the validation error and confirm it is announced and explains how to recover."),
        e("live-region", "4.1.3", "Status Messages", "AA", .moderate, sr, "Trigger the dynamic update and confirm assistive technology announces it."),
        e("state-updates-after-interaction", "4.1.3", "Status Messages", "AA", .moderate, sr, "Interact with the control and confirm the resulting state change is announced.")
    ]

    private static let table: [String: AccessibilityRuleMetadata] = Dictionary(
        uniqueKeysWithValues: entries
    )
}
