
import Foundation
import CoreGraphics
import AppKit

// MARK: - Common rule context
struct AccessibilityRuleContext {
    let screenshotData: Data?
    let screenshotWidth: Double
    let screenshotHeight: Double
    let hierarchyWidth: Double
    let hierarchyHeight: Double

    init(
        screenshotData: Data? = nil,
        screenshotWidth: Double = 0,
        screenshotHeight: Double = 0,
        hierarchyWidth: Double = 0,
        hierarchyHeight: Double = 0
    ) {
        self.screenshotData = screenshotData
        self.screenshotWidth = screenshotWidth
        self.screenshotHeight = screenshotHeight
        self.hierarchyWidth = hierarchyWidth
        self.hierarchyHeight = hierarchyHeight
    }
}

protocol ContextualAccessibilityRule {
    func evaluate(
        node: AccessibilityNode,
        context: AccessibilityRuleContext
    ) -> AccessibilityRuleEvaluation?
}


// MARK: - Rule catalog

struct AccessibilityRules {

    static var all: [AccessibilityRule] {
        [
            // Existing / direct element rules
            CommonAccessibleNameRule(),
            DescriptiveButtonNameRule(),
            ImageButtonNameRule(),
            CommonEnhancedTargetSizeRule(),
            CommonMinimumTargetSizeRule(),
            PlaceholderOnlyNameRule(),
            DescriptiveInteractiveNameRule(),
            AccessibleLabelImageRule(),
            DescriptiveImageRule(),
            AdjustableValueRule(),
            DisabledButtonStateRule(),
            RoleTraitConsistencyRule(),
            StateTraitConsistencyRule(),
            TextClippingRule(),
            HeadingQualityRule(),
            SegmentControlRule(),
            TabAccessibilityRule(),
            FormLabelRule(),
            AutocompleteRule(),
            ScreenTitleRule(),
            DuplicateInteractiveNameRule(),
            InteractiveTargetOverlapRule(),

            // Evidence-driven rules. They may return PASS/FAIL when sufficient evidence
            // is available; otherwise they remain VALIDATE or use a runtime probe.
            ContrastStandardTextRule(),
            ContrastLargeTextRule(),
            ContrastEnhancedStandardTextRule(),
            ContrastEnhancedLargeTextRule(),
            ContrastImageBackgroundRule(),
            ContrastOpacityRule(),
            TextResizeRule(),
            LinkRoleRule(),
            ButtonRoleRule(),
            DecorativeImageRule(),
            ScreenReaderHiddenInteractiveRule(),
            MotionAlternativeRule(),
            FocusOrderRule(),
            ScreenReaderFocusOrderRule(),
            OrientationRule(),
            ScreenReaderContentRule(),
            LanguageRule(),
            ModalAccessibilityRule(),
            LoadingIndicatorContrastRule(),
            LiveRegionRule(),
            TimeLimitedUIRule(),
            FocusIndicatorRule(),
            NonTextContrastRule(),
            FormBorderContrastRule(),
            ErrorMessageRule(),
            MapAlternativeRule(),
            GestureKeyboardRule(),
            AccessibilityInterfaceOperabilityRule(),
            TouchPhaseRule(),
            ComplexGestureRule(),
            MultiPointGestureAlternativeRule(),
            PathBasedGestureAlternativeRule(),
            ReadingOrderRule(),
            ScreenReaderModalFocusRule(),
            ScreenReaderTrapRule(),
            ScreenReaderFocusContextChangeRule(),
            KeyboardFocusContextChangeRule(),
            CancelUndoMechanismRule(),
            InputContextChangeRule(),
            KeyboardFocusRule(),
            KeyboardActivationRule(),
            KeyboardHiddenFocusRule(),
            KeyboardNonInteractiveFocusRule(),
            ErrorSuggestionRule(),
            StateUpdateRule(),
            LinkColorRule(),
            VisualLabelRule(),
            LanguageChangeRule(),
            TextSpacingRule(),
            ModalFocusContainmentRule()
        ]
    }
}

// MARK: - Core common rules

struct CommonAccessibleNameRule: AccessibilityRule {
    let id = "accessible-name"
    let title = "Accessible Name"
    let description = "Interactive controls must expose a meaningful accessible name."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.controls.contains(node.role), node.visible, node.enabled else { return nil }
        // Buttons have a dedicated descriptive-name rule. Keeping the common
        // rule off buttons prevents duplicate PASS/FAIL records.
        guard node.role != .button else { return nil }
        if RuleHelper.clean(node.label).isEmpty {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Interactive element has no accessible name.",
                                   remediation: "Provide a meaningful accessibility label.")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Interactive element has an accessible name.")
    }
}

struct CommonEnhancedTargetSizeRule: AccessibilityRule {
    let id = "touch-target-size-44"
    let title = "Interactive controls meet the enhanced target size (44pt) requirement"
    let description = "Interactive controls should provide at least a 44×44 point target."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.controls.contains(node.role), node.visible, node.enabled else { return nil }
        // iOS: 44pt (HIG). Android: 48dp. Android frames are normalised to dp.
        let target = node.platform.recommendedTargetSize
        let unit = node.platform.sizeUnit
        let size = "\(Int(target))×\(Int(target)) \(unit)"
        if node.frame.width < target || node.frame.height < target {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Interactive control does not meet the \(size) target size.",
                                   remediation: "Increase the interactive area to at least \(size).")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Interactive control meets the \(size) target size.")
    }
}

struct CommonMinimumTargetSizeRule: AccessibilityRule {
    let id = "touch-target-size-24"
    let title = "Interactive controls meet the minimum target size (24pt) requirement"
    let description = "Interactive controls should provide at least a 24×24 point target."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.controls.contains(node.role), node.visible, node.enabled else { return nil }
        if node.frame.width < 24 || node.frame.height < 24 {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Interactive control does not meet the 24×24 \(node.platform.sizeUnit) minimum target size.",
                                   remediation: "Increase the interactive area to at least 24×24 \(node.platform.sizeUnit) or provide adequate spacing.")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Interactive control meets the 24×24 \(node.platform.sizeUnit) minimum target size.")
    }
}

// MARK: - Helpers

private enum RuleHelper {

    static let buttons: Set<AccessibilityRole> = [
        .button
    ]

    static let textInputs: Set<AccessibilityRole> =
        AccessibilityRole.textInputs

    static let controls: Set<AccessibilityRole> =
        AccessibilityRole.controls

    static let images: Set<AccessibilityRole> = [
        .image
    ]

    static let headingsTraits = [
        "header",
        "heading"
    ]

    static func clean(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isGenericName(_ value: String) -> Bool {
        let normalized = clean(value).lowercased()
        if normalized.isEmpty { return true }

        let generic = [
            "button", "click", "click here", "tap", "tap here",
            "image", "icon", "more", "next", "ok", "yes", "no",
            "submit", "action", "item", "cell", "link"
        ]

        return generic.contains(normalized)
    }

    static func hasTrait(_ node: AccessibilityNode, _ names: [String]) -> Bool {
        let traits = node.traits.lowercased()
        return names.contains { traits.contains($0) }
    }

    static func isText(_ node: AccessibilityNode) -> Bool {
        node.role == .staticText ||
        node.role == .textView ||
        node.role == .textField ||
        node.role == .secureTextField
    }

    static func isVisible(_ node: AccessibilityNode) -> Bool {
        node.visible && node.exists && node.frame.width > 0 && node.frame.height > 0
    }

    static func isImageLikeButton(_ node: AccessibilityNode) -> Bool {
        guard node.role == .button else { return false }

        let identifier = node.identifier.lowercased()
        let label = clean(node.label)

        // A button that contains an image child is an image button even when
        // the developer did not use an image/icon identifier. This is one of
        // the strongest image-button signals available in the accessibility hierarchy.
        let containsImageChild = node.children.contains { child in
            child.role == .image
        }

        return label.isEmpty && (
            containsImageChild ||
            node.isImageButtonClass ||
            identifier.contains("image") ||
            identifier.contains("icon") ||
            identifier.contains("glyph") ||
            identifier.contains("symbol")
        )
    }

    static func allNodes(_ root: AccessibilityNode) -> [AccessibilityNode] {
        var result: [AccessibilityNode] = []

        func visit(_ node: AccessibilityNode) {
            if node.exists { result.append(node) }
            for child in node.children {
                visit(child)
            }
        }

        visit(root)
        return result
    }

    static func nearbyVisualLabel(for field: AccessibilityNode, in root: AccessibilityNode) -> AccessibilityNode? {
        let labels = allNodes(root).filter { node in
            node.role == .staticText &&
            isVisible(node) &&
            !clean(node.label).isEmpty &&
            !node.frame.intersects(field.frame)
        }

        let candidates = labels.compactMap { label -> (AccessibilityNode, CGFloat)? in
            let verticalGap = max(
                field.frame.minY - label.frame.maxY,
                label.frame.minY - field.frame.maxY,
                0
            )
            let horizontalGap = max(
                field.frame.minX - label.frame.maxX,
                label.frame.minX - field.frame.maxX,
                0
            )

            let horizontalOverlap = max(
                0,
                min(field.frame.maxX, label.frame.maxX) -
                max(field.frame.minX, label.frame.minX)
            )
            let verticalOverlap = max(
                0,
                min(field.frame.maxY, label.frame.maxY) -
                max(field.frame.minY, label.frame.minY)
            )

            let width = max(field.frame.width, label.frame.width, 1)
            let height = max(field.frame.height, label.frame.height, 1)

            // Label above/below the field with meaningful horizontal alignment.
            if verticalGap <= 24 && horizontalOverlap / width >= 0.30 {
                return (label, verticalGap)
            }

            // Label to the left/right of the field with meaningful vertical alignment.
            if horizontalGap <= 32 && verticalOverlap / height >= 0.30 {
                return (label, horizontalGap)
            }

            return nil
        }

        return candidates.min { $0.1 < $1.1 }?.0
    }

    static func visibleInteractiveNodes(_ root: AccessibilityNode) -> [AccessibilityNode] {
        var result: [AccessibilityNode] = []

        func visit(_ node: AccessibilityNode) {
            if node.exists, node.visible, node.enabled, controls.contains(node.role),
               node.frame.width > 0, node.frame.height > 0, !clean(node.label).isEmpty {
                result.append(node)
            }
            for child in node.children {
                visit(child)
            }
        }

        visit(root)
        return result
    }

    static func nodeKey(_ node: AccessibilityNode) -> String {
        [
            node.type,
            node.identifier,
            clean(node.label),
            String(format: "%.1f", node.frame.origin.x),
            String(format: "%.1f", node.frame.origin.y),
            String(format: "%.1f", node.frame.width),
            String(format: "%.1f", node.frame.height)
        ].joined(separator: "|")
    }

    static func warning(
        ruleID: String,
        name: String,
        description: String,
        node: AccessibilityNode,
        message: String,
        remediation: String
    ) -> AccessibilityRuleEvaluation {
        AccessibilityRuleEvaluation(
            ruleID: ruleID,
            ruleName: name,
            ruleDescription: description,
            status: .warning,
            severity: .warning,
            message: message,
            remediation: remediation,
            node: node
        )
    }

    static func validation(
        ruleID: String,
        name: String,
        description: String,
        node: AccessibilityNode,
        message: String,
        remediation: String
    ) -> AccessibilityRuleEvaluation {
        AccessibilityRuleEvaluation(
            ruleID: ruleID,
            ruleName: name,
            ruleDescription: description,
            status: .validate,
            severity: .warning,
            message: message,
            remediation: remediation,
            node: node
        )
    }

    static func notTested(
        ruleID: String,
        name: String,
        description: String,
        node: AccessibilityNode,
        message: String,
        remediation: String
    ) -> AccessibilityRuleEvaluation {
        AccessibilityRuleEvaluation(
            ruleID: ruleID,
            ruleName: name,
            ruleDescription: description,
            status: .notTested,
            severity: .warning,
            message: message,
            remediation: remediation,
            node: node
        )
    }

    static func pass(
        ruleID: String,
        name: String,
        description: String,
        node: AccessibilityNode,
        message: String
    ) -> AccessibilityRuleEvaluation {
        AccessibilityRuleEvaluation(
            ruleID: ruleID,
            ruleName: name,
            ruleDescription: description,
            status: .pass,
            severity: .info,
            message: message,
            remediation: "",
            node: node
        )
    }

    static func fail(
        ruleID: String,
        name: String,
        description: String,
        node: AccessibilityNode,
        message: String,
        remediation: String
    ) -> AccessibilityRuleEvaluation {
        AccessibilityRuleEvaluation(
            ruleID: ruleID,
            ruleName: name,
            ruleDescription: description,
            status: .fail,
            severity: .error,
            message: message,
            remediation: remediation,
            node: node
        )
    }
}

// MARK: - Direct rules
struct DescriptiveButtonNameRule: AccessibilityRule {
    let id = "button-name-descriptive"
    let title = "Accessible name for button is descriptive"
    let description = "Button names should identify the action or purpose."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .button, node.visible else { return nil }
        // Image-only buttons are reported by the image-button-specific rule.
        guard !RuleHelper.isImageLikeButton(node) else { return nil }
        if RuleHelper.isGenericName(node.label) {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Button accessible name is missing or generic.",
                                   remediation: "Provide a concise name describing the button's action or purpose.")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Button has a descriptive-looking accessible name.")
    }
}

struct ImageButtonNameRule: AccessibilityRule {
    let id = "image-button-name"
    let title = "Missing accessible name for image button"
    let description = "Image-only buttons need an accessible name."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .button, node.visible else { return nil }
        let imageLike = RuleHelper.isImageLikeButton(node)
        guard imageLike else { return nil }
        return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                               message: "Image-based button has no accessible name.",
                               remediation: "Provide an accessibility label that describes the action, not only the image appearance.")
    }
}

struct PlaceholderOnlyNameRule: AccessibilityRule {
    let id = "placeholder-only-name"
    let title = "Placeholder text used as the only accessible name — no visible label present"
    let description = "A placeholder should not be the only accessible name for a form control."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.textInputs.contains(node.role), node.visible else { return nil }
        guard RuleHelper.clean(node.label).isEmpty,
              !RuleHelper.clean(node.placeholderValue).isEmpty else { return nil }
        return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                               message: "The form control has a placeholder but no visible/accessibility label.",
                               remediation: "Provide a persistent visible label and an accessible name independent of placeholder text.")
    }
}

struct DescriptiveInteractiveNameRule: AccessibilityRule {
    let id = "interactive-name-descriptive"
    let title = "Accessible name for interactive element is descriptive"
    let description = "Interactive elements should expose meaningful names."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.controls.contains(node.role), node.visible else { return nil }
        guard node.role != .button else { return nil }
        if RuleHelper.isGenericName(node.label) {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Interactive element has a missing or generic accessible name.",
                                   remediation: "Use a name that communicates the control's purpose.")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Interactive element has a descriptive-looking accessible name.")
    }
}

struct AccessibleLabelImageRule: AccessibilityRule {
    let id = "image-accessible-label"
    let title = "Missing accessible label for image"
    let description = "Meaningful images should expose a textual description."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .image, node.visible, node.accessible else { return nil }
        guard RuleHelper.clean(node.label).isEmpty else {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "Image has an accessibility label.")
        }
        return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                               message: "Accessible image has no accessible label.",
                               remediation: "Add a concise textual description, or explicitly make a decorative image inaccessible to assistive technology.")
    }
}

struct DescriptiveImageRule: AccessibilityRule {
    let id = "image-name-descriptive"
    let title = "Non-descriptive accessible name for image"
    let description = "Image labels should communicate meaningful content."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .image, node.visible, node.accessible else { return nil }
        if RuleHelper.isGenericName(node.label) {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Image accessible name is missing or generic.",
                                   remediation: "Describe the meaningful content or purpose of the image.")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Image has a descriptive-looking accessible name.")
    }
}

struct AdjustableValueRule: AccessibilityRule {
    let id = "adjustable-accessibility-value"
    let title = "Adjustable element exposes accessibilityValue"
    let description = "Adjustable controls should expose their current value."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.isAdjustable, node.visible else { return nil }
        if node.platform == .android && !node.hasValue {
            // RangeInfo / stateDescription are not part of the UiAutomator2 dump.
            return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                         message: "Range information is not exposed in the Android hierarchy; verify the current value is announced by TalkBack.",
                                         remediation: "Expose the current value through RangeInfo or stateDescription so TalkBack announces it.")
        }
        guard node.hasValue else {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Adjustable element does not expose an accessibility value.",
                                   remediation: "Expose the current value through the accessibility value.")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Adjustable element exposes an accessibility value.")
    }
}

struct DuplicateInteractiveNameRule: ScreenAccessibilityRule {
    let id = "duplicate-interactive-name"
    let title = "Interactive elements have identical accessible names"
    let description = "Repeated accessible names can make controls indistinguishable to assistive technology."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        nil
    }

    func evaluate(rootNode: AccessibilityNode) -> [AccessibilityRuleEvaluation] {
        let controls = RuleHelper.visibleInteractiveNodes(rootNode)
        let groups = Dictionary(grouping: controls) {
            RuleHelper.clean($0.label).lowercased()
        }

        return groups.values
            .filter { $0.count > 1 }
            .flatMap { group -> [AccessibilityRuleEvaluation] in
                let types = Set(group.map(\.type))
                // Repeated names on the same role can be perfectly legitimate
                // (for example a list of identical cells). Only flag them when
                // the scanner cannot establish that they represent the same role.
                // Mixed roles are a stronger signal of ambiguous naming.
                let shouldWarn = types.count > 1 || group.count <= 5
                guard shouldWarn else { return [] }

                return group.map { node in
                    RuleHelper.warning(
                        ruleID: id,
                        name: title,
                        description: description,
                        node: node,
                        message: "Multiple interactive elements share the accessible name \"\(RuleHelper.clean(node.label))\".",
                        remediation: "If these controls perform different actions, give each a unique or contextual accessible name."
                    )
                }
            }
    }
}

struct InteractiveTargetOverlapRule: ScreenAccessibilityRule {
    let id = "interactive-target-overlap"
    let title = "Interactive targets do not improperly overlap"
    let description = "Interactive controls should not substantially overlap in a way that can make activation ambiguous."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        nil
    }

    func evaluate(rootNode: AccessibilityNode) -> [AccessibilityRuleEvaluation] {
        let controls = RuleHelper.visibleInteractiveNodes(rootNode)
        var results: [AccessibilityRuleEvaluation] = []
        var reported = Set<String>()

        for index in controls.indices {
            for otherIndex in controls.indices where otherIndex > index {
                let first = controls[index]
                let second = controls[otherIndex]
                let intersection = first.frame.intersection(second.frame)

                guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { continue }

                let firstArea = max(first.frame.width * first.frame.height, 1)
                let secondArea = max(second.frame.width * second.frame.height, 1)
                let overlapRatio = max(
                    (intersection.width * intersection.height) / firstArea,
                    (intersection.width * intersection.height) / secondArea
                )

                // Ignore tiny boundary/contact intersections. A 25% overlap of
                // either target is a meaningful black-box warning.
                guard overlapRatio >= 0.25 else { continue }

                let pairKey = [
                    RuleHelper.nodeKey(first),
                    RuleHelper.nodeKey(second)
                ].sorted().joined(separator: "|")
                guard reported.insert(pairKey).inserted else { continue }

                results.append(
                    RuleHelper.warning(
                        ruleID: id,
                        name: title,
                        description: description,
                        node: first,
                        message: "Interactive target overlaps another interactive target by approximately \(Int(overlapRatio * 100))% of one of the affected targets.",
                        remediation: "Ensure interactive hit areas do not overlap unintentionally. If the overlap is intentional, verify that each action remains independently discoverable and operable."
                    )
                )
            }
        }

        return results
    }
}

struct DisabledButtonStateRule: AccessibilityRule {
    let id = "button-disabled-state"
    let title = "Disabled state of button not defined"
    let description = "A disabled button should expose its disabled state consistently."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .button, node.visible else { return nil }
        if !node.enabled {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "Button is exposed as disabled by the accessibility hierarchy.")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Button is exposed as enabled.")
    }
}

struct RoleTraitConsistencyRule: AccessibilityRule {
    let id = "role-trait-consistency"
    let title = "Accessibility role and traits are consistent"
    let description = "Accessibility traits should agree with the exposed element role."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.visible else { return nil }
        let traits = node.traits.lowercased()

        if node.role == .button && traits.contains("statictext") {
            return RuleHelper.fail(
                ruleID: id, name: title, description: description, node: node,
                message: "Button exposes a conflicting static-text trait.",
                remediation: "Expose the correct accessibility role and remove conflicting traits."
            )
        }

        if node.role == .image && (traits.contains("button") || traits.contains("clickable")) {
            return RuleHelper.fail(
                ruleID: id, name: title, description: description, node: node,
                message: "Image exposes button/clickable semantics while its exposed role is image.",
                remediation: "Expose the interactive element as a button, or remove the button semantics if the image is decorative/non-interactive."
            )
        }

        if traits.contains("link") && ![AccessibilityRole.button, .staticText, .link].contains(node.role) {
            return RuleHelper.warning(
                ruleID: id, name: title, description: description, node: node,
                message: "Element exposes link semantics on an unexpected element type.",
                remediation: "Verify the element's role is represented consistently for assistive technology."
            )
        }

        return RuleHelper.pass(
            ruleID: id, name: title, description: description, node: node,
            message: "No obvious role/trait conflict was found in the accessibility hierarchy."
        )
    }
}

struct StateTraitConsistencyRule: AccessibilityRule {
    let id = "state-trait-consistency"
    let title = "Accessibility state is consistent with the current control state"
    let description = "Exposed state information should agree with the control's current state."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.controls.contains(node.role), node.visible else { return nil }
        let traits = node.traits.lowercased()

        if !node.enabled && node.hittable {
            return RuleHelper.fail(
                ruleID: id, name: title, description: description, node: node,
                message: "Control is reported disabled but remains hittable.",
                remediation: "Synchronize the disabled state with the control's interaction behavior."
            )
        }

        if traits.contains("selected") &&
            ![AccessibilityRole.button, .segmentedControl, .picker].contains(node.role) {
            return RuleHelper.warning(
                ruleID: id, name: title, description: description, node: node,
                message: "Selected state is exposed on a control type where selection semantics are not obvious.",
                remediation: "Verify that the selected state represents a real current state and is announced correctly."
            )
        }

        if node.isAdjustable && !node.hasValue && node.platform == .ios {
            return RuleHelper.fail(
                ruleID: id, name: title, description: description, node: node,
                message: "Adjustable control has no current accessibility value.",
                remediation: "Expose the current value so assistive technology can communicate the control's state."
            )
        }

        return RuleHelper.pass(
            ruleID: id, name: title, description: description, node: node,
            message: "Current enabled, hittable, and exposed state information is internally consistent."
        )
    }
}

struct TextClippingRule: ScreenAccessibilityRule {
    let id = "text-clipping"
    let title = "Text is not clipped by layout bounds"
    let description = "Visible text should remain within the screen and its accessible layout bounds."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        nil
    }

    func evaluate(rootNode: AccessibilityNode) -> [AccessibilityRuleEvaluation] {
        let rootBounds = rootNode.frame

        return RuleHelper.allNodes(rootNode).compactMap { node in
            guard RuleHelper.isText(node), node.visible, !RuleHelper.clean(node.label).isEmpty else { return nil }

            if node.frame.width <= 0 || node.frame.height <= 0 {
                return RuleHelper.fail(
                    ruleID: id,
                    name: title,
                    description: description,
                    node: node,
                    message: "Text element has no visible layout bounds.",
                    remediation: "Ensure the text receives sufficient layout space and is not collapsed."
                )
            }

            let visibleIntersection = node.frame.intersection(rootBounds)
            let area = max(node.frame.width * node.frame.height, 1)
            let visibleArea = max(visibleIntersection.width * visibleIntersection.height, 0)
            let visibleRatio = visibleArea / area

            if visibleRatio < 0.80 {
                return RuleHelper.fail(
                    ruleID: id,
                    name: title,
                    description: description,
                    node: node,
                    message: "Text element extends outside the visible screen bounds (approximately \(Int(visibleRatio * 100))% visible).",
                    remediation: "Adjust the layout so the complete text remains visible at the current content size and orientation."
                )
            }

            return RuleHelper.pass(
                ruleID: id,
                name: title,
                description: description,
                node: node,
                message: "Text element is within the current screen bounds; rendered glyph clipping still requires visual validation."
            )
        }
    }
}

struct HeadingQualityRule: AccessibilityRule {
    let id = "heading-quality"
    let title = "Non-descriptive heading text"
    let description = "Headings should provide meaningful section context."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.hasTrait(node, RuleHelper.headingsTraits), node.visible else { return nil }
        if RuleHelper.isGenericName(node.label) {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Heading text is missing or generic.",
                                   remediation: "Use concise text that identifies the section.")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Heading has a meaningful-looking label.")
    }
}

struct SegmentControlRule: AccessibilityRule {
    let id = "segmented-control-interactive"
    let title = "Check if segmented controls needs to be interactive"
    let description = "Segments that represent choices should expose an interactive role."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .segmentedControl, node.visible else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Segmented control detected; verify every selectable segment is operable and stateful.",
                                     remediation: "Test segment selection and selected-state announcements.")
    }
}

struct TabAccessibilityRule: AccessibilityRule {
    let id = "tab-accessibility"
    let title = "Check if tab control needs to be hidden for screen reader user"
    let description = "Tab controls should expose an appropriate tab role and selected state."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .button, node.visible else { return nil }
        let text = (node.label + " " + node.identifier).lowercased()
        guard text.contains("tab") else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Possible tab control detected; verify role, selected state, and screen-reader behavior.",
                                     remediation: "Verify tab semantics and selected-state announcements.")
    }
}

struct FormLabelRule: ScreenAccessibilityRule {
    let id = "form-visual-label"
    let title = "Form controls have an associated visible label"
    let description = "Form controls should have a visible label independent of placeholder text."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        nil
    }

    func evaluate(rootNode: AccessibilityNode) -> [AccessibilityRuleEvaluation] {
        RuleHelper.allNodes(rootNode).compactMap { node in
            guard RuleHelper.textInputs.contains(node.role), node.visible else { return nil }

            if !RuleHelper.clean(node.label).isEmpty {
                return RuleHelper.pass(
                    ruleID: id,
                    name: title,
                    description: description,
                    node: node,
                    message: "Form control exposes an accessible name; visual label association is also checked from nearby hierarchy text."
                )
            }

            if let visualLabel = RuleHelper.nearbyVisualLabel(for: node, in: rootNode) {
                return RuleHelper.pass(
                    ruleID: id,
                    name: title,
                    description: description,
                    node: node,
                    message: "A nearby visible text label (\"\(RuleHelper.clean(visualLabel.label))\") is associated with the form control by screen geometry."
                )
            }

            return RuleHelper.validation(
                ruleID: id,
                name: title,
                description: description,
                node: node,
                message: "No accessible or nearby visible text label could be established from the current hierarchy.",
                remediation: "Provide a persistent visible label associated with the field; do not rely on placeholder text alone."
            )
        }
    }
}

struct AutocompleteRule: AccessibilityRule {
    let id = "form-autocomplete"
    let title = "Autocomplete information is specified for form field"
    let description = "Form fields should expose appropriate autocomplete semantics where applicable."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.textInputs.contains(node.role), node.visible else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                    message: "Autocomplete/content-type metadata is not exposed through Appium, so it could not be checked.",
                                    remediation: "Verify the field has the correct autocomplete/content-type semantics.")
    }
}

struct ScreenTitleRule: AccessibilityRule {
    let id = "screen-title"
    let title = "Title is specified for screen"
    let description = "Screens should expose a meaningful title to assistive technology."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .navigationBar, node.visible else { return nil }
        if RuleHelper.clean(node.label).isEmpty {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Navigation bar has no accessible title.",
                                   remediation: "Expose a meaningful screen title.")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Navigation bar exposes a screen title.")
    }
}

// MARK: - Validation rules

private struct ValidationRule: AccessibilityRule {
    let id: String
    let title: String
    let description: String
    let applies: (AccessibilityNode) -> Bool
    let message: String
    let remediation: String

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard applies(node) else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: message, remediation: remediation)
    }
}

/// Which text a contrast rule applies to, and the ratio it requires.
private enum ContrastTarget {
    /// Standard text. Text that may be large if bold is also checked here;
    /// `largeThreshold` is what it would need if it were large.
    case standard(threshold: Double, largeThreshold: Double)
    /// Large text only.
    case large(threshold: Double)
    /// Any text, with the threshold picked by estimated size.
    case anySize(standard: Double, large: Double)
}

/// Which backgrounds a contrast rule covers. The minimum-contrast check of
/// each text element belongs to exactly one rule: the standard/large text
/// rules for flat backgrounds, the text-over-image rule for varied ones.
private enum ContrastBackground {
    case flat
    case varied
    case any
}

private enum ContrastRuleFactory {

    private static func ratioText(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value)):1" : String(format: "%.1f:1", value)
    }

    static func result(
        node: AccessibilityNode,
        context: AccessibilityRuleContext,
        ruleID: String,
        title: String,
        description: String,
        target: ContrastTarget,
        background: ContrastBackground
    ) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.isText(node), node.visible, !node.label.isEmpty else { return nil }

        let sizeClass = TextSizeEstimate.classify(node)
        let threshold: Double
        var possiblyLargeThreshold: Double?
        switch (target, sizeClass) {
        case (.standard, .large), (.large, .standard), (.large, .possiblyLarge):
            return nil
        case (.standard(let standard, let large), _):
            threshold = standard
            if sizeClass == .possiblyLarge { possiblyLargeThreshold = large }
        case (.large(let large), _):
            threshold = large
        case (.anySize(_, let large), .large):
            threshold = large
        case (.anySize(let standard, let large), _):
            threshold = standard
            if sizeClass == .possiblyLarge { possiblyLargeThreshold = large }
        }

        let estimatedSize = TextSizeEstimate.fontSize(frame: node.frame, text: node.label)
            .map { "estimated \(Int($0.rounded())) \(node.platform == .android ? "sp" : "pt")" } ?? "size unknown"
        let sizeText: String
        switch sizeClass {
        case .large: sizeText = "large text, \(estimatedSize)"
        case .possiblyLarge: sizeText = "standard text unless bold, \(estimatedSize)"
        case .standard: sizeText = "standard text, \(estimatedSize)"
        }

        let requirement = ratioText(threshold)
        guard let sampler = PixelSampler.make(context: context),
              let measurement = PixelAnalyzer.inkContrast(frame: node.frame, sampler: sampler)
        else {
            // Reported once, by the flat-background rules, not again here.
            guard background != .varied else { return nil }
            return RuleHelper.validation(ruleID: ruleID, name: title, description: description, node: node,
                                         message: "Inconclusive: no text pixels distinct from the background could be found in the screenshot for this element.",
                                         remediation: "Check the element's rendered foreground/background contrast manually.")
        }
        switch background {
        case .flat where measurement.variedBackground: return nil
        case .varied where !measurement.variedBackground: return nil
        default: break
        }

        let measured = String(format: "%.2f:1", measurement.ratio)
        let basis = measurement.variedBackground
            ? "worst-case contrast over a varied (image or gradient) background"
            : "measured rendered contrast"

        if measurement.ratio + 0.001 < threshold {
            if let possiblyLargeThreshold, measurement.ratio + 0.001 >= possiblyLargeThreshold {
                return RuleHelper.validation(ruleID: ruleID, name: title, description: description, node: node,
                                             message: "The \(basis) is \(measured) (\(sizeText)). This is below \(requirement) for standard text but meets \(ratioText(possiblyLargeThreshold)), which is enough if the text is bold.",
                                             remediation: "Confirm whether the text is bold. If it is not, increase the contrast to at least \(requirement).")
            }
            return RuleHelper.fail(ruleID: ruleID, name: title, description: description, node: node,
                                   message: "The \(basis) is \(measured) (\(sizeText)), below the required \(requirement).",
                                   remediation: "Increase the effective foreground/background contrast to at least \(requirement)\(measurement.variedBackground ? ", for example with a scrim or solid backing behind the text" : "").")
        }
        return RuleHelper.pass(ruleID: ruleID, name: title, description: description, node: node,
                               message: "The \(basis) is \(measured) (\(sizeText)), meeting the required \(requirement).")
    }
}

struct ContrastStandardTextRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "contrast-standard-text-4-5"
    let title = "Verify if color contrast for standard text with its background is sufficient"
    let description = "Standard text should meet a minimum 4.5:1 contrast ratio."
    /// Needs the screenshot: the result comes from the contextual evaluation below.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        ContrastRuleFactory.result(node: node, context: context, ruleID: id, title: title, description: description, target: .standard(threshold: 4.5, largeThreshold: 3), background: .flat)
    }
}

struct ContrastLargeTextRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "contrast-large-text-3"
    let title = "Verify if color contrast for large text with its background is sufficient"
    let description = "Large text should meet a minimum 3:1 contrast ratio."
    /// Needs the screenshot: the result comes from the contextual evaluation below.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        ContrastRuleFactory.result(node: node, context: context, ruleID: id, title: title, description: description, target: .large(threshold: 3), background: .flat)
    }
}

struct ContrastEnhancedStandardTextRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "contrast-standard-text-7"
    let title = "Check if the contrast ratio of standard text ... is 7:1"
    let description = "Standard text enhanced contrast requirement."
    /// Needs the screenshot: the result comes from the contextual evaluation below.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        ContrastRuleFactory.result(node: node, context: context, ruleID: id, title: title, description: description, target: .standard(threshold: 7, largeThreshold: 4.5), background: .any)
    }
}

struct ContrastEnhancedLargeTextRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "contrast-large-text-4-5"
    let title = "Check if the contrast ratio of large text ... is 4.5:1"
    let description = "Large text enhanced contrast requirement."
    /// Needs the screenshot: the result comes from the contextual evaluation below.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        ContrastRuleFactory.result(node: node, context: context, ruleID: id, title: title, description: description, target: .large(threshold: 4.5), background: .any)
    }
}

struct ContrastImageBackgroundRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "contrast-text-over-image"
    let title = "Check contrast between text and background image"
    let description = "Text over imagery must maintain sufficient rendered contrast."
    /// Needs the screenshot: the result comes from the contextual evaluation below.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        ContrastRuleFactory.result(node: node, context: context, ruleID: id, title: title, description: description, target: .anySize(standard: 4.5, large: 3), background: .varied)
    }
}

struct ContrastOpacityRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "contrast-opacity"
    let title = "Check contrast with opacity"
    let description = "Effective rendered contrast must remain sufficient after opacity/compositing."
    /// Opacity is not exposed by XCUITest or UiAutomator, so this rule cannot
    /// tell which text is semi-transparent. The screenshot-based contrast rules
    /// already measure the composited colours, so text with opacity is checked
    /// there; this rule produces no per-element results of its own.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? { nil }
}

struct TextResizeRule: AccessibilityRule {
    let id = "text-resize"
    let title = "Text can be resized"
    let description = "Text should remain usable when Dynamic Type/accessibility text size is increased."

    /// Runtime-only: the result comes from a device probe (see RuntimeProbes.swift).
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

struct LinkRoleRule: AccessibilityRule {
    let id = "text-link-role"
    let title = "Text functions as a link but is missing role link"
    let description = "Link-like text should expose link semantics."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.visible, !node.label.isEmpty else { return nil }
        if node.role == .link {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "Element exposes the link role.")
        }
        guard node.role == .staticText else { return nil }
        let hint = (node.label + " " + node.identifier).lowercased()
        guard hint.contains("http") || hint.contains("www") || hint.contains("link") else { return nil }
        return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                               message: "Text appears link-like but is exposed as static text.",
                               remediation: "Expose link semantics if activating the text navigates somewhere.")
    }
}

struct ButtonRoleRule: AccessibilityRule {
    let id = "text-button-role"
    let title = "Text functions as a button but is missing role button"
    let description = "Actionable text should expose button semantics when appropriate."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.visible else { return nil }
        if node.role == .button {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "Element exposes button semantics.")
        }
        guard node.role == .staticText else { return nil }
        let hint = (node.label + " " + node.identifier + " " + node.traits).lowercased()
        let actionWords = ["button", "submit", "save", "cancel", "continue", "login", "sign in", "delete", "close"]
        guard actionWords.contains(where: { hint.contains($0) }) else { return nil }
        return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                               message: "Text appears action-oriented but is exposed as static text.",
                               remediation: "Expose an appropriate button role when the text performs an action.")
    }
}

struct DecorativeImageRule: AccessibilityRule {
    let id = "decorative-image"
    let title = "Check if Image should be marked as decorative"
    let description = "Decorative images should not add redundant screen-reader content."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .image, node.visible else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Only product/design intent can determine whether this image is decorative.",
                                     remediation: "If decorative, hide it from assistive technology; otherwise provide a useful description.")
    }
}

struct ScreenReaderHiddenInteractiveRule: AccessibilityRule {
    let id = "interactive-screen-reader-hidden"
    let title = "Check if interactive control needs to be hidden for screen reader user"
    let description = "Interactive controls should not be unintentionally hidden from assistive technology."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.controls.contains(node.role), node.visible else { return nil }
        if node.hittable && !node.accessible {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Control is hittable but not exposed as accessible.",
                                   remediation: "Expose the control to assistive technology unless it is intentionally excluded.")
        }
        if node.accessible {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "Interactive control is exposed to assistive technology.")
        }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "The control is not exposed to assistive technology and intent cannot be established from the hierarchy.",
                                     remediation: "Confirm the control is intentionally hidden or expose it to assistive technology.")
    }
}

struct MotionAlternativeRule: AccessibilityRule {
    let id = "motion-alternative"
    let title = "No On-Screen Alternative for Motion Action"
    let description = "Motion-driven actions should have an accessible non-motion alternative."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.visible else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                     message: "Motion-based interaction cannot be tested from the Appium accessibility hierarchy alone.",
                                     remediation: "Exercise motion features and verify an equivalent on-screen control exists.")
    }
}

struct FocusOrderRule: AccessibilityRule {
    let id = "focus-order"
    let title = "Keyboard focus order correct"
    let description = "Runtime accessibility focus should follow a meaningful reading and interaction order."

    // The accessibility tree alone cannot prove the order actually used by
    // VoiceOver/TalkBack. Runtime focus evidence is required; the crawler's
    // keyboard probe supplies a separate keyboard result.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

struct OrientationRule: AccessibilityRule {
    let id = "orientation-support"
    let title = "Check if all the content is available when the device orientation is changed"
    let description = "Content should remain available in supported orientations."

    /// Runtime-only: the result comes from a device probe (see RuntimeProbes.swift).
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

struct ScreenReaderContentRule: AccessibilityRule {
    let id = "screen-reader-content"
    let title = "Content can be accessed by screen reader user"
    let description = "Meaningful content should be exposed to assistive technology."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.visible else { return nil }
        if node.accessible {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "Element is exposed to assistive technology.")
        }
        let hasAccessibleDescendant = Self.flatten(node.children).contains { $0.visible && $0.accessible && (!RuleHelper.clean($0.label).isEmpty || RuleHelper.controls.contains($0.role)) }
        guard !node.children.isEmpty else { return nil }
        if hasAccessibleDescendant {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "Container itself is not accessible, but meaningful descendants are exposed.")
        }
        if RuleHelper.isText(node) || RuleHelper.controls.contains(node.role) {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Meaningful content is visible but not exposed to assistive technology.",
                                   remediation: "Expose the content to assistive technology or ensure an accessible descendant represents it.")
        }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "The container is not accessible and its semantic intent cannot be established automatically.",
                                     remediation: "Verify that meaningful content remains available to screen-reader users.")
    }
    private static func flatten(_ nodes: [AccessibilityNode]) -> [AccessibilityNode] { nodes.flatMap { [$0] + flatten($0.children) } }
}

struct LanguageRule: AccessibilityRule {
    let id = "language"
    let title = "Missing language attribute for content"
    let description = "Content language should be correctly identified where it differs from the app language."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .application else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                    message: "Language metadata is not exposed through Appium, so the scanner has no way to read it.",
                                    remediation: "Verify app and per-content language attributes using VoiceOver/TalkBack or the app source.")
    }
}

struct ModalAccessibilityRule: AccessibilityRule {
    let id = "modal-accessibility"
    let title = "Screen reader focus within modals correct"
    let description = "Assistive-technology focus should enter, remain within, and leave a modal correctly."

    // Appium page source can identify a modal, but standard Appium/WDA/UiAutomator
    // APIs do not provide a portable command for driving VoiceOver/TalkBack focus.
    // Do not infer a PASS/FAIL from labels such as "dialog" or "modal".
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        let text = (node.type + " " + node.identifier + " " + node.label).lowercased()
        guard text.contains("modal") || text.contains("dialog") else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                    message: "A modal was detected, but assistive-technology focus traversal was not available in this Appium session.",
                                    remediation: "Run VoiceOver/TalkBack and verify focus enters the modal, remains contained until dismissal, and returns to the invoking control.")
    }
}

struct LoadingIndicatorContrastRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "loading-indicator-contrast"
    let title = "Loading indicator has sufficient contrast with its background"
    let description = "Loading indicators should remain distinguishable from their background."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }

    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        let text = (node.type + " " + node.identifier + " " + node.label).lowercased()
        guard text.contains("progress") || text.contains("loading") || text.contains("activity"),
              node.visible else { return nil }

        guard let sampler = PixelSampler.make(context: context),
              let measurement = PixelAnalyzer.inkContrast(frame: node.frame, sampler: sampler)
        else {
            return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                         message: "Inconclusive: the indicator could not be told apart from its background in the screenshot (it may be mid-animation or hidden).",
                                         remediation: "Check the loading indicator's contrast against its background manually.")
        }
        let ratio = String(format: "%.2f:1", measurement.ratio)
        if measurement.ratio + 0.001 < 3.0 {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "The loading indicator has a measured contrast of \(ratio), below the required 3:1.",
                                   remediation: "Use an indicator colour with at least 3:1 contrast against its background.")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "The loading indicator has a measured contrast of \(ratio), meeting the required 3:1.")
    }
}

struct LiveRegionRule: AccessibilityRule {
    let id = "live-region"
    let title = "Live region is defined for dynamic content"
    let description = "Dynamic updates that require announcement should expose appropriate accessibility notifications."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .application else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                    message: "Screen-reader announcements for dynamic updates cannot be observed through Appium.",
                                    remediation: "Trigger the update with VoiceOver/TalkBack on and confirm it is announced.")
    }
}

struct TimeLimitedUIRule: AccessibilityRule {
    let id = "time-limited-ui"
    let title = "Time-limited UI has a visible user control"
    let description = "Time-limited content should provide a user-controlled extension or equivalent mechanism."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .application else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Timing behavior cannot be inferred from one hierarchy snapshot.",
                                     remediation: "Exercise timed UI and verify a visible mechanism to extend or disable the time limit.")
    }
}

struct FocusIndicatorRule: AccessibilityRule {
    let id = "focus-indicator"
    let title = "Customized keyboard focus visible"
    let description = "Keyboard focus should have a visible indicator in the rendered UI."

    // Runtime screenshot comparison is performed by KeyboardFocusTester.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

struct NonTextContrastRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "non-text-contrast"
    let title = "Non-text element has sufficient contrast with its background"
    let description = "Meaningful non-text UI components should have sufficient contrast."

    private static let measuredRoles: Set<AccessibilityRole> = [
        .button, .toggle, .checkBox, .radioButton, .slider, .stepper, .segmentedControl, .picker
    ]

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }

    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        guard Self.measuredRoles.contains(node.role), node.visible,
              node.frame.width >= 8, node.frame.height >= 8 else { return nil }

        guard let sampler = PixelSampler.make(context: context),
              let measurement = PixelAnalyzer.componentContrast(frame: node.frame, sampler: sampler)
        else {
            return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                         message: "Inconclusive: too few reliable pixels around this control in the screenshot.",
                                         remediation: "Check the control's boundary or fill contrast manually.")
        }

        // No border or fill to measure: the control is identified by its text or
        // icon, which the text contrast rules cover.
        guard measurement.hasBoundary else { return nil }

        let ratio = String(format: "%.2f:1", measurement.best)
        if measurement.best + 0.001 >= 3.0 {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "The control's boundary or fill has a measured contrast of \(ratio) against its surroundings, meeting 3:1.")
        }

        // A labelled button is identified by its text, so a faint boundary is
        // only a risk. Switches, checkboxes, sliders and similar rely on their
        // shape to show state, so a faint boundary is a failure.
        if node.role == .button {
            return RuleHelper.warning(ruleID: id, name: title, description: description, node: node,
                                      message: "The button's boundary or fill has a measured contrast of \(ratio) against its surroundings, below 3:1. This matters if the shape is needed to recognise it as a control.",
                                      remediation: "Give the control a boundary or fill with at least 3:1 contrast, or make sure a clear text label identifies it.")
        }
        return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                               message: "The control's boundary or fill has a measured contrast of \(ratio) against its surroundings, below the required 3:1.",
                               remediation: "Give the control a boundary, track or fill with at least 3:1 contrast against its background.")
    }
}

struct FormBorderContrastRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "form-border-contrast"
    let title = "Border of form controls has sufficient contrast with its background"
    let description = "Visible form-control boundaries should remain distinguishable."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }

    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.textInputs.contains(node.role), node.visible,
              node.frame.width >= 8, node.frame.height >= 8 else { return nil }

        guard let sampler = PixelSampler.make(context: context),
              let measurement = PixelAnalyzer.componentContrast(frame: node.frame, sampler: sampler)
        else {
            return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                         message: "Inconclusive: too few reliable pixels around this field in the screenshot.",
                                         remediation: "Check the field's border contrast manually.")
        }

        let ratio = String(format: "%.2f:1", measurement.best)
        if measurement.best + 0.001 >= 3.0 {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "The field's border or fill has a measured contrast of \(ratio) against its surroundings, meeting 3:1.")
        }
        return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                               message: "The field's border or fill has a measured contrast of \(ratio) against its surroundings, below the required 3:1.",
                               remediation: "Give the field a border, underline or fill with at least 3:1 contrast so users can see where to type.")
    }
}

struct ErrorMessageRule: AccessibilityRule {
    let id = "error-message-accessibility"
    let title = "Error message is accessible and includes a suggestion to fix it"
    let description = "Validation errors should be identified in text and exposed to assistive technology."

    /// Runtime-only: the error is triggered by the error-message probe (RuntimeProbes.swift).
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

struct ErrorSuggestionRule: AccessibilityRule {
    let id = "error-message-suggestion"
    let title = "Error message includes a suggestion to fix it"
    let description = "When an input error is detected, the message should say how to correct it."

    /// Static path: error text already on screen. The probe covers errors
    /// triggered by submitting an empty form.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .staticText, node.visible else { return nil }
        let text = RuleHelper.clean(node.label)
        guard ErrorMessageHeuristics.looksLikeStrictError(text) else { return nil }

        if ErrorMessageHeuristics.givesGuidance(text) {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "The error message gives guidance on how to correct the input.")
        }
        return RuleHelper.warning(ruleID: id, name: title, description: description, node: node,
                                  message: "The error message \"\(text)\" does not say how to correct the input.",
                                  remediation: "Say what is wrong and how to fix it, for example the expected format or the missing information.")
    }
}

struct KeyboardActivationRule: AccessibilityRule {
    let id = "keyboard-activation"
    let title = "Buttons and links are operable with a keyboard"
    let description = "Controls that can be tapped must also be activated from the keyboard."

    /// Runtime-only: see KeyboardProbes.swift.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

struct KeyboardHiddenFocusRule: AccessibilityRule {
    let id = "keyboard-focus-hidden-content"
    let title = "Hidden content does not receive keyboard focus"
    let description = "Keyboard focus must not land on hidden or off-screen content."

    /// Runtime-only: reported by the keyboard focus probe.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

struct KeyboardNonInteractiveFocusRule: AccessibilityRule {
    let id = "keyboard-focus-noninteractive"
    let title = "Non-interactive elements do not receive keyboard focus"
    let description = "Keyboard focus should only stop on elements the user can act on."

    /// Runtime-only: reported by the keyboard focus probe.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

struct MapAlternativeRule: AccessibilityRule {
    let id = "map-text-alternative"
    let title = "Map view has a text alternative"
    let description = "Maps should expose an accessible textual alternative for meaningful locations and controls."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        let text = (node.type + " " + node.identifier + " " + node.label).lowercased()
        guard text.contains("map") else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Map content is detected by naming only; verify an equivalent textual representation exists.",
                                     remediation: "Provide an accessible textual alternative for important map information.")
    }
}

struct GestureKeyboardRule: AccessibilityRule {
    let id = "gesture-keyboard-operable"
    let title = "Interactive elements operable with keyboard interface"
    let description = "Functionality implemented through gestures should have an equivalent keyboard operation where keyboard operation is supported."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .application else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                     message: "Gesture-to-keyboard equivalence cannot be proven from the accessibility hierarchy without safely executing the gesture and its alternative action.",
                                     remediation: "Exercise the gesture and its keyboard or simple-control alternative and verify both produce the same result.")
    }
}

struct AccessibilityInterfaceOperabilityRule: AccessibilityRule {
    let id = "accessibility-interface-operable"
    let title = "Interactive elements operable with accessibility interface"
    let description = "Interactive controls should be operable through the platform accessibility interface."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .application else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                     message: "Appium exposes the accessibility hierarchy but does not provide portable, reliable VoiceOver/TalkBack activation evidence for this check.",
                                     remediation: "Run VoiceOver on iOS or TalkBack on Android and activate each meaningful control through the accessibility interface.")
    }
}

struct TouchPhaseRule: AccessibilityRule {
    let id = "touch-up-cancellation"
    let title = "Action supports cancellation before activation"
    let description = "Where applicable, an interaction should allow the user to cancel before activation."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .application else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                     message: "Pointer cancellation requires executing a press/drag sequence and observing whether activation occurs on release.",
                                     remediation: "Press the actionable target, move away before release, and verify the action is cancelled where the interaction supports cancellation.")
    }
}

struct ComplexGestureRule: AccessibilityRule {
    let id = "complex-gesture-alternative"
    let title = "Alternative for multi-point/path-based gestures present"
    let description = "Complex gestures should have an equivalent accessible operation."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .application else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                     message: "The accessibility hierarchy does not identify multi-point or path-based gestures and cannot prove an equivalent alternative.",
                                     remediation: "Exercise each multi-point or path gesture and verify a single-pointer or simple-control alternative is available unless the gesture is essential.")
    }
}

struct MultiPointGestureAlternativeRule: AccessibilityRule {
    let id = "multi-point-gesture-alternative"
    let title = "Alternative for multi-point gestures present"
    let description = "Multi-point gesture functionality should have an equivalent simple operation unless the gesture is essential."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .application else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                     message: "The accessibility hierarchy does not identify multi-point gestures or their functional alternatives.",
                                     remediation: "Exercise each multi-point gesture and verify an equivalent single-pointer or simple-control alternative is available unless the gesture is essential.")
    }
}

struct PathBasedGestureAlternativeRule: AccessibilityRule {
    let id = "path-based-gesture-alternative"
    let title = "Alternative for path-based gestures present"
    let description = "Path-based gesture functionality should have an equivalent simple operation unless the gesture is essential."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .application else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                     message: "The accessibility hierarchy does not identify path-based gestures or their functional alternatives.",
                                     remediation: "Exercise each path-based gesture and verify an equivalent simple control or single-pointer alternative is available unless the gesture is essential.")
    }
}

struct ReadingOrderRule: ScreenAccessibilityRule {
    let id = "reading-order"
    let title = "Screen reader focus order includes all meaningful elements"
    let description = "Assistive-technology traversal should include meaningful content in a meaningful order."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }

    func evaluate(rootNode: AccessibilityNode) -> [AccessibilityRuleEvaluation] {
        var elements: [AccessibilityNode] = []
        func visit(_ node: AccessibilityNode) {
            if node.exists, node.visible, node.accessible,
               node.frame.width > 0, node.frame.height > 0,
               node.role != .application, node.role != .scrollView, node.role != .table,
               !RuleHelper.clean(node.label).isEmpty,
               node.children.isEmpty || RuleHelper.controls.contains(node.role) {
                elements.append(node)
            }
            for child in node.children { visit(child) }
        }
        visit(rootNode)

        guard let assessment = VisualOrder.assess(frames: elements.map(\.frame)) else { return [] }

        if assessment.ratio >= VisualOrder.passThreshold {
            return [RuleHelper.pass(ruleID: id, name: title, description: description, node: rootNode,
                                    message: "The accessibility tree order of \(assessment.count) meaningful elements follows the visual reading order (top to bottom, left to right).")]
        }
        return [RuleHelper.warning(ruleID: id, name: title, description: description, node: rootNode,
                                   message: "\(assessment.outOfOrder) of \(assessment.count) meaningful elements are exposed out of visual reading order. Screen readers follow the accessibility tree order by default.",
                                   remediation: "Reorder the accessibility elements (or set traversal order) so assistive technology reads the screen in a meaningful order.")]
    }
}

struct ScreenReaderFocusOrderRule: ScreenAccessibilityRule {
    let id = "screen-reader-focus-order"
    let title = "Screen reader focus order correct"
    let description = "VoiceOver/TalkBack focus should follow a meaningful order."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }

    func evaluate(rootNode: AccessibilityNode) -> [AccessibilityRuleEvaluation] {
        var elements: [AccessibilityNode] = []
        func visit(_ node: AccessibilityNode) {
            if node.exists, node.visible, node.accessible,
               node.frame.width > 0, node.frame.height > 0,
               node.role != .application, node.role != .scrollView, node.role != .table,
               !RuleHelper.clean(node.label).isEmpty,
               node.children.isEmpty || RuleHelper.controls.contains(node.role) {
                elements.append(node)
            }
            for child in node.children { visit(child) }
        }
        visit(rootNode)

        guard let assessment = VisualOrder.assess(frames: elements.map(\.frame)) else { return [] }

        if assessment.ratio >= VisualOrder.passThreshold {
            return [RuleHelper.pass(ruleID: id, name: title, description: description, node: rootNode,
                                    message: "The accessibility tree order of \(assessment.count) meaningful elements follows the visual reading order (top to bottom, left to right).")]
        }
        return [RuleHelper.warning(ruleID: id, name: title, description: description, node: rootNode,
                                   message: "\(assessment.outOfOrder) of \(assessment.count) meaningful elements are exposed out of visual reading order. Screen readers follow the accessibility tree order by default.",
                                   remediation: "Reorder the accessibility elements (or set traversal order) so assistive technology reads the screen in a meaningful order.")]
    }
}

struct ScreenReaderModalFocusRule: AccessibilityRule {
    let id = "screen-reader-modal-focus"
    let title = "Screen reader focus within modals correct"
    let description = "Screen reader focus should enter an active modal, remain contained, and return correctly after dismissal."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .application else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                     message: "Appium hierarchy data cannot prove VoiceOver/TalkBack modal focus entry, containment, and restoration.",
                                     remediation: "Open each modal with VoiceOver/TalkBack enabled, verify focus enters the modal, remains contained, and returns to the invoking control after dismissal.")
    }
}

struct ScreenReaderTrapRule: AccessibilityRule {
    let id = "screen-reader-trap"
    let title = "No screen reader trap present"
    let description = "Assistive-technology focus should be able to leave every component and modal when appropriate."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .application else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                     message: "VoiceOver/TalkBack traversal cannot be driven or observed reliably through the portable Appium hierarchy API.",
                                     remediation: "Navigate through the component with VoiceOver/TalkBack and verify focus can leave it without an unintended loop.")
    }
}

struct ScreenReaderFocusContextChangeRule: AccessibilityRule {
    let id = "screen-reader-focus-context-change"
    let title = "No context change on focus with screen reader present"
    let description = "Receiving assistive-technology focus should not unexpectedly initiate a context change."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .application else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                     message: "A portable Appium hierarchy snapshot cannot distinguish an expected focus announcement from an unexpected context change caused by screen-reader focus.",
                                     remediation: "Traverse controls with VoiceOver/TalkBack and verify focus alone does not navigate, submit, open, or otherwise change context unexpectedly.")
    }
}

struct KeyboardFocusContextChangeRule: AccessibilityRule {
    let id = "keyboard-focus-context-change"
    let title = "No context change on focus with external keyboard"
    let description = "Receiving external-keyboard focus should not unexpectedly change context."

    /// Runtime-only: reported by the keyboard focus probe.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

struct CancelUndoMechanismRule: AccessibilityRule {
    let id = "cancel-undo-mechanism"
    let title = "Cancel or undo action mechanism present"
    let description = "Where an interaction can cause a consequential or difficult-to-reverse change, an appropriate cancel or undo mechanism should be available."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .application else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                     message: "The hierarchy cannot determine which actions require cancellation or undo, so presence of a suitable mechanism cannot be inferred safely.",
                                     remediation: "Exercise consequential actions and verify the user can cancel before commitment or undo the resulting change when applicable.")
    }
}

struct InputContextChangeRule: AccessibilityRule {
    let id = "input-context-change"
    let title = "No unexpected context change on input"
    let description = "Entering data or changing a control should not unexpectedly change context."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .application else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                     message: "Context-change behavior requires entering or changing input and comparing the resulting screen; the static hierarchy cannot prove it.",
                                     remediation: "Enter representative input and verify that focus, navigation, submission, and screen changes occur only when expected.")
    }
}

struct KeyboardFocusRule: AccessibilityRule {
    let id = "keyboard-focus"
    let title = "Interactive control can receive keyboard focus"
    let description = "Keyboard users should be able to reach interactive controls where keyboard operation is supported."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

struct StateUpdateRule: AccessibilityRule {
    let id = "state-updates-after-interaction"
    let title = "State does not get updated on user interaction"
    let description = "Interactive state should update after user actions."

    /// Runtime-only: the result comes from a device probe (see RuntimeProbes.swift).
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

struct LinkColorRule: ScreenAccessibilityRule, ContextualScreenAccessibilityRule {
    let id = "link-color-differentiation"
    let title = "Link color differentiation check"
    let description = "Links should not rely on color alone to communicate their role."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
    func evaluate(rootNode: AccessibilityNode) -> [AccessibilityRuleEvaluation] { [] }

    func evaluate(rootNode: AccessibilityNode, context: AccessibilityRuleContext) -> [AccessibilityRuleEvaluation] {
        guard let sampler = PixelSampler.make(context: context) else { return [] }

        let nodes = RuleHelper.allNodes(rootNode)
        let links = nodes.filter { $0.role == .link && $0.visible && $0.frame.width > 0 && $0.frame.height > 0 }
        let texts = nodes.filter {
            $0.role == .staticText && $0.visible && !RuleHelper.clean($0.label).isEmpty
        }

        var results: [AccessibilityRuleEvaluation] = []

        for link in links {
            // Surrounding body text: on the same line, next to or around the link.
            let neighbour = texts
                .filter { text in
                    guard text.frame != link.frame else { return false }
                    let overlap = min(text.frame.maxY, link.frame.maxY) - max(text.frame.minY, link.frame.minY)
                    guard overlap >= 0.4 * min(text.frame.height, link.frame.height) else { return false }
                    let gap = max(text.frame.minX - link.frame.maxX, link.frame.minX - text.frame.maxX, 0)
                    return gap <= 40
                }
                .min { lhs, rhs in
                    let l = max(lhs.frame.minX - link.frame.maxX, link.frame.minX - lhs.frame.maxX, 0)
                    let r = max(rhs.frame.minX - link.frame.maxX, link.frame.minX - rhs.frame.maxX, 0)
                    return l < r
                }

            // A stand-alone link is not inside a block of text, so colour
            // differentiation does not apply.
            guard let neighbour else { continue }

            guard let linkInk = PixelAnalyzer.inkContrast(frame: link.frame, sampler: sampler) else {
                results.append(RuleHelper.validation(ruleID: id, name: title, description: description, node: link,
                                                     message: "Inconclusive: the link text colour could not be measured from the screenshot.",
                                                     remediation: "Check that the link is distinguishable from surrounding text without relying on colour alone."))
                continue
            }

            if PixelAnalyzer.hasUnderline(frame: link.frame, sampler: sampler, backgroundLuminance: linkInk.backgroundLuminance) {
                results.append(RuleHelper.pass(ruleID: id, name: title, description: description, node: link,
                                               message: "The link is underlined, so it does not rely on colour alone."))
                continue
            }

            guard let bodyInk = PixelAnalyzer.inkContrast(frame: neighbour.frame, sampler: sampler, excluding: link.frame) else {
                results.append(RuleHelper.validation(ruleID: id, name: title, description: description, node: link,
                                                     message: "Inconclusive: the surrounding text colour could not be measured from the screenshot.",
                                                     remediation: "Check that the link is distinguishable from surrounding text without relying on colour alone."))
                continue
            }

            let ratio = PixelMath.contrast(linkInk.inkLuminance, bodyInk.inkLuminance)
            let ratioText = String(format: "%.2f:1", ratio)
            if ratio + 0.001 >= 3.0 {
                results.append(RuleHelper.pass(ruleID: id, name: title, description: description, node: link,
                                               message: "The link text differs from the surrounding text by \(ratioText), meeting 3:1."))
            } else {
                results.append(RuleHelper.fail(ruleID: id, name: title, description: description, node: link,
                                               message: "The link has no underline and its colour differs from the surrounding text by only \(ratioText), below 3:1.",
                                               remediation: "Underline the link or add another non-colour cue, or increase the colour difference to at least 3:1."))
            }
        }
        return results
    }
}

struct VisualLabelRule: AccessibilityRule {
    let id = "visual-label"
    let title = "Visual label is specified for form control"
    let description = "Form controls should have a visible, persistent label."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.textInputs.contains(node.role), node.visible else { return nil }
        if !RuleHelper.clean(node.label).isEmpty || !RuleHelper.clean(node.placeholderValue ?? "").isEmpty {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "Form control exposes a descriptive label or placeholder in the accessibility hierarchy.")
        }
        return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                               message: "Form control has no accessible label or placeholder that can be used as evidence of a visible label.",
                               remediation: "Provide a persistent visible label and expose the same purpose to assistive technology.")
    }
}

struct LanguageChangeRule: AccessibilityRule {
    let id = "language-change"
    let title = "Change in language is defined correctly"
    let description = "Content language changes should be identified correctly."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .application else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                    message: "Per-element language metadata is not exposed through Appium, so language changes could not be checked.",
                                    remediation: "Verify language changes are identified for screen-reader pronunciation.")
    }
}

struct TextSpacingRule: AccessibilityRule {
    let id = "text-spacing"
    let title = "Text spacing requirements met"
    let description = "Content should remain usable with increased text spacing."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.isText(node), node.visible, !node.label.isEmpty else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Text spacing requires applying increased spacing styles and rescanning the rendered layout.",
                                     remediation: "Test increased line/paragraph/letter/word spacing and verify no clipping or overlap.")
    }
}

struct ModalFocusContainmentRule: AccessibilityRule {
    let id = "modal-focus-containment"
    let title = "Keyboard focus within modals correct"
    let description = "Keyboard focus should remain inside an active modal until dismissal."

    // Runtime keyboard traversal is evaluated by KeyboardFocusTester.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}
