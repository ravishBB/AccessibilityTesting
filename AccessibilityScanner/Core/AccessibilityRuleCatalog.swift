//
//  AccessibilityRuleCatalog.swift
//  AccessibilityScanner


import Foundation

nonisolated enum AccessibilityImpact: String, Codable, CaseIterable {
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

nonisolated struct AccessibilityRuleMetadata: Codable, Hashable {
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

nonisolated enum AccessibilityRuleCatalog {

    /// Bump whenever a rule is added, removed, re-mapped or its logic changes.
    static let version = "2026.10.19"

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

    // MARK: - What can run where

    /// Rules Appium cannot give a result for on any platform: the evidence
    /// (language, opacity, gestures, assistive-technology behaviour) is not
    /// exposed. They are reported as Not tested.
    static let notAutomatable: Set<String> = [
        "language", "language-change", "contrast-opacity",
        "accessibility-interface-operable", "cancel-undo-mechanism", "input-context-change",
        "screen-reader-modal-focus", "screen-reader-trap", "screen-reader-focus-context-change",
        "motion-alternative", "multi-point-gesture-alternative", "path-based-gesture-alternative",
        "gesture-keyboard-operable"
    ]

    /// Rules that also cannot run on iOS: WebDriverAgent does not report
    /// keyboard focus, live regions, input types, hints or missing roles.
    static let notAutomatableOnIOS: Set<String> = [
        "live-region", "form-autocomplete", "missing-role", "name-via-hint",
        "keyboard-focus", "keyboard-activation", "keyboard-focus-hidden-content",
        "keyboard-focus-noninteractive", "keyboard-focus-context-change",
        "focus-indicator", "focus-order", "focus-indicator-contrast", "focus-not-obscured", "focus-indicator-color-only",
        "modal-accessibility", "modal-focus-containment"
    ]

    /// Rules that by design only raise manual-review items, never pass/fail.
    static let reviewOnly: Set<String> = [
        "decorative-image", "segmented-control-interactive", "tab-accessibility",
        "screen-reader-focus-order", "text-spacing", "time-limited-ui", "heading-candidate",
        "text-in-image", "image-role", "list-items-navigable"
    ]

    static func cannotRun(on platform: MobilePlatform) -> Set<String> {
        platform == .ios ? notAutomatable.union(notAutomatableOnIOS) : notAutomatable
    }

    /// Rules that can give a pass or fail on this platform.
    static func verdictCapableRuleCount(on platform: MobilePlatform) -> Int {
        Set(table.keys).subtracting(cannotRun(on: platform)).subtracting(reviewOnly).count
    }

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
        e("image-button-name", "1.1.1", "Non-text Content", "A", .critical, "\(sr), voice control users", nameTest),
        e("interactive-name-descriptive", "4.1.2", "Name, Role, Value", "A", .serious, "\(sr), voice control users", nameTest),
        e("placeholder-only-name", "3.3.2", "Labels or Instructions", "A", .serious, "\(sr), users with cognitive disabilities", "Focus the field once it contains text and confirm VoiceOver/TalkBack still announces a name for it."),
        e("adjustable-accessibility-value", "4.1.2", "Name, Role, Value", "A", .serious, sr, "Adjust the control with swipe up/down and confirm the new value is announced."),
        e("button-disabled-state", "4.1.2", "Name, Role, Value", "A", .moderate, sr, "Focus the disabled control and confirm it is announced as dimmed/disabled."),
        e("role-trait-consistency", "4.1.2", "Name, Role, Value", "A", .serious, sr, "Focus the element and confirm the announced role (button, link, header...) matches how it behaves."),
        e("state-trait-consistency", "4.1.2", "Name, Role, Value", "A", .serious, sr, "Toggle the control and confirm the selected/checked/expanded state is announced."),
        e("text-link-role", "4.1.2", "Name, Role, Value", "A", .moderate, sr, "Focus the link text and confirm it is announced as a link."),
        e("text-button-role", "4.1.2", "Name, Role, Value", "A", .moderate, sr, "Focus the tappable text and confirm it is announced as a button."),
        e("interactive-screen-reader-hidden", "4.1.2", "Name, Role, Value", "A", .critical, sr, "Swipe through the screen with VoiceOver/TalkBack and confirm this control can be reached."),
        e("segmented-control-interactive", "2.1.1", "Keyboard", "A", .serious, sr, "Move focus across the segments and confirm each is announced with its selected state."),
        e("tab-accessibility", "4.1.2", "Name, Role, Value", "A", .serious, sr, "Move focus across the tabs and confirm each is announced as a tab with its selected state and position."),

        // Non-text content
        e("image-accessible-label", "1.1.1", "Non-text Content", "A", .serious, sr, "Focus the image and confirm the announced text conveys the same information."),
        e("image-name-descriptive", "1.1.1", "Non-text Content", "A", .moderate, sr, "Focus the image and confirm the label is meaningful and not a file name."),
        e("decorative-image", "1.1.1", "Non-text Content", "A", .minor, sr, "Swipe through the screen and confirm purely decorative images are skipped."),
        e("text-in-image", "1.4.5", "Images of Text", "AA", .moderate, "Low-vision users", "Find images that show words and confirm the text is real text, unless it is a logo or essential."),
        e("image-role", "4.1.2", "Name, Role, Value", "A", .moderate, sr, "Move VoiceOver/TalkBack to each picture and confirm it is announced as an image."),
        e("list-items-navigable", "1.3.1", "Info and Relationships", "A", .moderate, sr, "Swipe through lists with VoiceOver/TalkBack and confirm each item is a separate stop."),
        e("map-text-alternative", "1.1.1", "Non-text Content", "A", .serious, "\(sr), users who cannot see the map", "Confirm the same information shown on the map is available as text or a list."),

        // Info and relationships / sequence
        e("heading-quality", "2.4.6", "Headings and Labels", "AA", .moderate, sr, "Use the rotor/headings navigation and confirm headings are marked and describe their sections."),
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
        e("non-text-contrast", "1.4.11", "Non-text Contrast", "AA", .serious, "Low-vision users", "Inspect icons and control boundaries and confirm they are clearly distinguishable."),
        e("form-border-contrast", "1.4.11", "Non-text Contrast", "AA", .moderate, "Low-vision users", "Inspect the field border and confirm it is clearly visible against the background."),
        e("loading-indicator-contrast", "1.4.11", "Non-text Contrast", "AA", .minor, "Low-vision users", "Inspect the loading indicator and confirm it is clearly visible."),

        // Text resizing and spacing
        e("text-resize", "1.4.4", "Resize Text", "AA", .serious, "Low-vision users", "Increase the system text size to the maximum and confirm text stays readable without clipping or overlap."),
        e("text-clipping", "1.4.4", "Resize Text", "AA", .serious, "Low-vision users", "Increase the system text size and confirm no text is cut off or truncated."),
        e("text-truncation", "1.4.4", "Resize Text", "AA", .serious, "Low-vision users", "Set the largest text size and confirm no text is shortened with an ellipsis (…)."),
        e("text-overlap", "1.4.4", "Resize Text", "AA", .serious, "Low-vision users", "Set the largest text size and confirm no text overlaps other text."),
        e("text-spacing", "1.4.12", "Text Spacing", "AA", .moderate, "Users with dyslexia or low vision", "Increase text spacing settings and confirm content does not overlap or get cut off."),

        // Keyboard / focus / gestures
        e("keyboard-focus", "2.1.1", "Keyboard", "A", .critical, "Keyboard and switch-control users", "Use a hardware keyboard Tab/Shift-Tab and confirm the control can receive focus and be activated."),
        e("accessibility-interface-operable", "2.1.1", "Keyboard", "A", .critical, "Screen reader and switch-control users", "Confirm interactive controls can be activated through the platform accessibility interface."),
        e("screen-reader-focus-order", "2.4.3", "Focus Order", "A", .serious, "Screen reader users", "Use VoiceOver/TalkBack sequential navigation and confirm focus follows the intended order."),
        e("screen-reader-modal-focus", "2.4.3", "Focus Order", "A", .serious, "Screen reader users", "Open each modal with VoiceOver/TalkBack and verify focus enters, remains within, and returns correctly."),
        e("screen-reader-trap", "2.1.2", "No Keyboard Trap", "A", .serious, "Screen reader users", "Verify VoiceOver/TalkBack focus can leave every component and modal when appropriate."),
        e("screen-reader-focus-context-change", "3.2.1", "On Focus", "A", .moderate, "Screen reader users", "Verify receiving screen-reader focus does not unexpectedly change context."),
        e("keyboard-focus-context-change", "3.2.1", "On Focus", "A", .moderate, "Keyboard users", "Verify receiving external-keyboard focus does not unexpectedly change context."),
        e("keyboard-activation", "2.1.1", "Keyboard", "A", .critical, "Keyboard and switch-control users", "Tab to each button and link with a hardware keyboard and press Space/Enter; confirm it activates."),
        e("keyboard-focus-hidden-content", "2.4.3", "Focus Order", "A", .serious, "Keyboard users", "Tab through the screen and confirm focus never lands on hidden or off-screen content."),
        e("keyboard-focus-noninteractive", "2.4.3", "Focus Order", "A", .moderate, "Keyboard users", "Tab through the screen and confirm focus only lands on controls the user can act on."),
        e("cancel-undo-mechanism", "3.3.4", "Error Prevention (Legal, Financial, Data)", "AA", .moderate, "Users who need to recover from mistakes", "Exercise consequential actions and confirm an appropriate cancel or undo mechanism is available."),
        e("input-context-change", "3.2.2", "On Input", "A", .moderate, "Users with cognitive and motor disabilities", "Enter or change representative input and confirm context changes occur only when expected."),
        e("gesture-keyboard-operable", "2.1.1", "Keyboard", "A", .critical, "Keyboard and switch-control users", "Confirm the gesture action can also be performed with the keyboard or a simple control."),
        e("modal-accessibility", "2.1.2", "No Keyboard Trap", "A", .serious, "\(sr), keyboard users", "Open the dialog, confirm focus moves into it and can leave it, and returns correctly on dismissal."),
        e("modal-focus-containment", "2.1.1", "Keyboard", "A", .serious, "\(sr), keyboard users", "Open the dialog and confirm focus stays inside until it is dismissed."),
        e("focus-order", "2.4.3", "Focus Order", "A", .serious, "\(sr), keyboard users", "Move focus sequentially and confirm the order is logical."),
        e("focus-indicator", "2.4.7", "Focus Visible", "AA", .serious, "Keyboard users", "Tab through the screen and confirm the focused element has a visible indicator."),
        e("complex-gesture-alternative", "2.1.1", "Keyboard", "A", .serious, "Users with motor disabilities", "Confirm multi-finger or path gestures have a single-tap alternative."),
        e("multi-point-gesture-alternative", "2.1.1", "Keyboard", "A", .serious, "Users with motor disabilities", "Confirm multi-point gestures have an equivalent simple alternative."),
        e("path-based-gesture-alternative", "2.1.1", "Keyboard", "A", .serious, "Users with motor disabilities", "Confirm path-based gestures have an equivalent simple alternative."),
        e("touch-up-cancellation", "2.5.2", "Pointer Cancellation", "A", .moderate, "Users with motor disabilities", "Press on the control, slide away and release; confirm the action does not fire."),
        e("motion-alternative", "2.5.4", "Motion Actuation", "A", .moderate, "Users with motor disabilities", "Perform the motion interaction and confirm an equivalent non-motion control exists."),
        e("focus-indicator-color-only", "1.4.1", "Use of Color", "A", .serious, "Keyboard users with colour-vision deficiency", "Tab to each control and confirm focus is shown by more than a change of colour (an outline, border or clear change in lightness)."),
        e("focus-indicator-contrast", "1.4.11", "Non-text Contrast", "AA", .serious, "Keyboard users with low vision", "Tab to each control and confirm the focus outline is clearly visible against its surroundings."),
        e("focus-not-obscured", "2.4.11", "Focus Not Obscured (Minimum)", "AA", .serious, "Keyboard users", "Tab through the screen and confirm the focused control is never hidden behind a sticky header, footer or banner."),
        e("modal-closable", "2.1.1", "Keyboard", "A", .serious, "\(sr), keyboard users", "Open the dialog and confirm it can be closed with a screen reader and a keyboard."),
        e("missing-role", "4.1.2", "Name, Role, Value", "A", .critical, sr, "Focus the element with TalkBack/VoiceOver and confirm its role (button, checkbox…) is announced."),
        e("name-via-hint", "4.1.2", "Name, Role, Value", "A", .serious, "\(sr), voice control users", "Focus the control and confirm its purpose is announced immediately as its name, not only after a pause as a hint."),
        e("label-in-name", "2.5.3", "Label in Name", "A", .serious, "Voice control users", "Say the visible label with Voice Control/Voice Access and confirm the control activates."),
        e("heading-candidate", "1.3.1", "Info and Relationships", "A", .moderate, sr, "Use heading navigation and confirm text that introduces a section is reachable as a heading."),
        e("form-visual-label", "3.3.2", "Labels or Instructions", "A", .serious, "\(sr), users with cognitive disabilities", "Focus the field and confirm the announced name matches the visible label."),

        // Target size
        e("touch-target-size-24", "2.5.8", "Target Size (Minimum)", "AA", .moderate, "Users with motor disabilities", targetTest),
        e("interactive-target-overlap", "2.5.8", "Target Size (Minimum)", "AA", .serious, "Users with motor disabilities", "Try activating each overlapping control and confirm the intended one responds."),

        // Navigation / labels
        e("screen-title", "2.4.2", "Page Titled / Screen Title", "A", .moderate, sr, "Open the screen and confirm a title that identifies it is announced."),
        e("duplicate-interactive-name", "4.1.2", "Name, Role, Value", "A", .moderate, "\(sr), voice control users", "Move through the controls and confirm identical names are distinguishable by context."),

        // Language and timing
        e("language", "3.1.1", "Language of Page / App", "A", .moderate, sr, "Use VoiceOver/TalkBack on the content and confirm pronunciation matches the language."),
        e("language-change", "3.1.2", "Language of Parts", "AA", .minor, sr, "Focus content in a different language and confirm it is pronounced correctly."),
        e("time-limited-ui", "2.2.1", "Timing Adjustable", "A", .serious, "Users who need more time", "Let the timer approach expiry and confirm the user can extend or disable the limit."),

        // Errors and status
        e("error-message-suggestion", "3.3.1", "Error Identification", "A", .serious, "\(sr), users with cognitive disabilities", "Trigger each validation error and confirm the message says how to correct the input."),
        e("error-message-accessibility", "4.1.3", "Status Messages", "AA", .serious, "\(sr), users with cognitive disabilities", "Trigger the validation error and confirm it is announced and explains how to recover."),
        e("live-region", "4.1.3", "Status Messages", "AA", .moderate, sr, "Trigger the dynamic update and confirm assistive technology announces it."),
        e("state-updates-after-interaction", "4.1.2", "Name, Role, Value", "A", .moderate, sr, "Interact with the control and confirm the resulting state change is announced.")
    ]

    private static let table: [String: AccessibilityRuleMetadata] = Dictionary(
        uniqueKeysWithValues: entries
    )
}
