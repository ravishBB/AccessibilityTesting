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

    var testerAction: String {
        switch ruleID {
        case "accessible-name", "descriptive-button-name", "image-button-name", "descriptive-interactive-name":
            return "Move VoiceOver/TalkBack focus to this control and confirm its announced name identifies its purpose."
        case "interactive-screen-reader-hidden", "screen-reader-content":
            return "Navigate the screen with VoiceOver/TalkBack and confirm this content/control is reachable and announced."
        case "focus-order", "reading-order":
            return "Navigate through the screen sequentially and confirm focus follows the intended visual/reading order."
        case "keyboard-focus", "gesture-keyboard", "complex-gesture":
            return "Use hardware-keyboard Tab/Shift-Tab and verify the control can receive focus and be operated without the gesture."
        case "modal-accessibility", "modal-focus-containment":
            return "Open the dialog, verify focus enters it, stays within it as required, and returns correctly after dismissal."
        case "form-label", "visual-label":
            return "Focus the field and confirm the announced name matches the visible field label."
        case "error-message-accessibility":
            return "Trigger the validation error and verify the error is announced and explains how to recover."
        case "touch-target-size-44", "touch-target-size-24":
            return "Try activating the control near its edges and confirm the full target is easy to hit without touching adjacent controls."
        case "orientation-support":
            return "Rotate the device and confirm content, controls, focus order, and actions remain available."
        case "text-resize", "text-spacing":
            return "Increase accessibility text/spacing settings and confirm text remains readable without clipping, overlap, or loss of controls."
        case "language", "language-change":
            return "Use VoiceOver/TalkBack on the affected content and verify pronunciation matches the content language."
        case "motion-alternative":
            return "Perform the motion interaction and confirm an equivalent non-motion control is available."
        case "live-region":
            return "Trigger the dynamic update and confirm assistive technology announces the change when it needs user attention."
        case "time-limited-ui":
            return "Allow the timer to approach expiry and confirm the user can extend or disable the time limit when required."
        case "focus-indicator", "non-text-contrast", "form-border-contrast", "loading-indicator-contrast":
            return "Inspect the rendered UI at normal and focused states and verify the visual distinction is clear and sufficient."
        default:
            return status == .validate
                ? "Perform the manual verification described above and record the result before sign-off."
                : "Confirm the finding on the device and retest after the fix."
        }
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
