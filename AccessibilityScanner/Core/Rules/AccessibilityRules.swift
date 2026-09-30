
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

            // Explicit validation rules. These are surfaced as VALIDATE,
            // never as an invented pass/fail result.
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
            TouchPhaseRule(),
            ComplexGestureRule(),
            ReadingOrderRule(),
            KeyboardFocusRule(),
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
        guard RuleHelper.controls.contains(node.type), node.visible, node.enabled else { return nil }
        // Buttons have a dedicated descriptive-name rule. Keeping the common
        // rule off buttons prevents duplicate PASS/FAIL records.
        guard node.type != "XCUIElementTypeButton" else { return nil }
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
        guard RuleHelper.controls.contains(node.type), node.visible, node.enabled else { return nil }
        if node.frame.width < 44 || node.frame.height < 44 {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Interactive control does not meet the 44×44 point target size.",
                                   remediation: "Increase the interactive area to at least 44×44 points.")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Interactive control meets the 44×44 point target size.")
    }
}

struct CommonMinimumTargetSizeRule: AccessibilityRule {
    let id = "touch-target-size-24"
    let title = "Interactive controls meet the minimum target size (24pt) requirement"
    let description = "Interactive controls should provide at least a 24×24 point target."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.controls.contains(node.type), node.visible, node.enabled else { return nil }
        if node.frame.width < 24 || node.frame.height < 24 {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Interactive control does not meet the 24×24 point minimum target size.",
                                   remediation: "Increase the interactive area to at least 24×24 points or provide adequate spacing.")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Interactive control meets the 24×24 point minimum target size.")
    }
}

// MARK: - Helpers

private enum RuleHelper {

    static let buttons: Set<String> = [
        "XCUIElementTypeButton"
    ]

    static let textInputs: Set<String> = [
        "XCUIElementTypeTextField",
        "XCUIElementTypeSecureTextField",
        "XCUIElementTypeTextView"
    ]

    static let controls: Set<String> = [
        "XCUIElementTypeButton",
        "XCUIElementTypeTextField",
        "XCUIElementTypeSecureTextField",
        "XCUIElementTypeSlider",
        "XCUIElementTypeSwitch",
        "XCUIElementTypeStepper",
        "XCUIElementTypePickerWheel",
        "XCUIElementTypeSegmentedControl"
    ]

    static let images: Set<String> = [
        "XCUIElementTypeImage"
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
        node.type == "XCUIElementTypeStaticText" ||
        node.type == "XCUIElementTypeTextView" ||
        node.type == "XCUIElementTypeTextField" ||
        node.type == "XCUIElementTypeSecureTextField"
    }

    static func isVisible(_ node: AccessibilityNode) -> Bool {
        node.visible && node.exists && node.frame.width > 0 && node.frame.height > 0
    }

    static func isImageLikeButton(_ node: AccessibilityNode) -> Bool {
        guard node.type == "XCUIElementTypeButton" else { return false }

        let identifier = node.identifier.lowercased()
        let label = clean(node.label)

        // A button that contains an image child is an image button even when
        // the developer did not use an image/icon identifier. This is one of
        // the strongest image-button signals available in WDA's hierarchy.
        let containsImageChild = node.children.contains { child in
            child.type == "XCUIElementTypeImage"
        }

        return label.isEmpty && (
            containsImageChild ||
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
            node.type == "XCUIElementTypeStaticText" &&
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
            if node.exists, node.visible, node.enabled, controls.contains(node.type),
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
        guard node.type == "XCUIElementTypeButton", node.visible else { return nil }
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
        guard node.type == "XCUIElementTypeButton", node.visible else { return nil }
        let imageLike = RuleHelper.isImageLikeButton(node)
        guard imageLike else { return nil }
        return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                               message: "Image-based button has no accessible name.",
                               remediation: "Provide an accessibility label that describes the action, not only the image appearance.")
    }
}

struct EnhancedTargetSizeRule: AccessibilityRule {
    let id = "target-size-enhanced-44"
    let title = "Interactive controls meet the enhanced target size (44pt) requirement"
    let description = "Interactive controls should expose at least a 44×44 point target."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.controls.contains(node.type), node.visible, node.enabled else { return nil }
        guard node.frame.width < 44 || node.frame.height < 44 else {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "Interactive control meets the 44pt target size.")
        }
        return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                               message: "Interactive control is smaller than 44×44pt.",
                               remediation: "Increase the hit area to at least 44×44pt.")
    }
}

struct MinimumTargetSizeRule: AccessibilityRule {
    let id = "target-size-minimum-24"
    let title = "Interactive controls meet the minimum target size (24pt) requirement"
    let description = "Interactive controls should expose at least a 24×24 point target."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.controls.contains(node.type), node.visible, node.enabled else { return nil }
        guard node.frame.width >= 24, node.frame.height >= 24 else {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Interactive control is smaller than 24×24pt.",
                                   remediation: "Increase the target size or provide adequate spacing around the control.")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Interactive control meets the 24pt minimum target size.")
    }
}

struct PlaceholderOnlyNameRule: AccessibilityRule {
    let id = "placeholder-only-name"
    let title = "Placeholder text used as the only accessible name — no visible label present"
    let description = "A placeholder should not be the only accessible name for a form control."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.textInputs.contains(node.type), node.visible else { return nil }
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
        guard RuleHelper.controls.contains(node.type), node.visible else { return nil }
        guard node.type != "XCUIElementTypeButton" else { return nil }
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
        guard node.type == "XCUIElementTypeImage", node.visible, node.accessible else { return nil }
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
        guard node.type == "XCUIElementTypeImage", node.visible, node.accessible else { return nil }
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
        guard node.type == "XCUIElementTypeButton", node.visible else { return nil }
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

        if node.type == "XCUIElementTypeButton" && traits.contains("statictext") {
            return RuleHelper.fail(
                ruleID: id, name: title, description: description, node: node,
                message: "Button exposes a conflicting static-text trait.",
                remediation: "Expose the correct accessibility role and remove conflicting traits."
            )
        }

        if node.type == "XCUIElementTypeImage" && traits.contains("button") {
            return RuleHelper.fail(
                ruleID: id, name: title, description: description, node: node,
                message: "Image exposes a button trait while the WDA element role is image.",
                remediation: "Expose the interactive element as a button, or remove the button semantics if the image is decorative/non-interactive."
            )
        }

        if traits.contains("link") && !["XCUIElementTypeButton", "XCUIElementTypeStaticText", "XCUIElementTypeLink"].contains(node.type) {
            return RuleHelper.warning(
                ruleID: id, name: title, description: description, node: node,
                message: "Element exposes link semantics on an unexpected WDA element type.",
                remediation: "Verify the element's role is represented consistently for assistive technology."
            )
        }

        return RuleHelper.pass(
            ruleID: id, name: title, description: description, node: node,
            message: "No obvious role/trait conflict was found in the WDA hierarchy."
        )
    }
}

struct StateTraitConsistencyRule: AccessibilityRule {
    let id = "state-trait-consistency"
    let title = "Accessibility state is consistent with the current control state"
    let description = "Exposed state information should agree with the control's current state."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.controls.contains(node.type), node.visible else { return nil }
        let traits = node.traits.lowercased()

        if !node.enabled && node.hittable {
            return RuleHelper.fail(
                ruleID: id, name: title, description: description, node: node,
                message: "Control is reported disabled but remains hittable.",
                remediation: "Synchronize the disabled state with the control's interaction behavior."
            )
        }

        if traits.contains("selected") &&
            !["XCUIElementTypeButton", "XCUIElementTypeSegmentedControl", "XCUIElementTypePickerWheel"].contains(node.type) {
            return RuleHelper.warning(
                ruleID: id, name: title, description: description, node: node,
                message: "Selected state is exposed on a control type where selection semantics are not obvious.",
                remediation: "Verify that the selected state represents a real current state and is announced correctly."
            )
        }

        if node.isAdjustable && !node.hasValue {
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
        guard node.type == "XCUIElementTypeSegmentedControl", node.visible else { return nil }
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
        guard node.type == "XCUIElementTypeButton", node.visible else { return nil }
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
            guard RuleHelper.textInputs.contains(node.type), node.visible else { return nil }

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
        guard RuleHelper.textInputs.contains(node.type), node.visible else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Autocomplete metadata is not exposed by the current WDA node model; verify it on the form field.",
                                     remediation: "Verify the field has the correct autocomplete/content-type semantics.")
    }
}

struct ScreenTitleRule: AccessibilityRule {
    let id = "screen-title"
    let title = "Title is specified for screen"
    let description = "Screens should expose a meaningful title to assistive technology."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.type == "XCUIElementTypeNavigationBar", node.visible else { return nil }
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

private enum ScreenshotContrastAnalyzer {

    struct Measurement {
        let ratio: Double
        let foreground: NSColor
        let background: NSColor
    }

    static func measure(node: AccessibilityNode, context: AccessibilityRuleContext) -> Measurement? {
        guard
            let data = context.screenshotData,
            context.screenshotWidth > 0,
            context.screenshotHeight > 0,
            context.hierarchyWidth > 0,
            context.hierarchyHeight > 0,
            let bitmap = NSBitmapImageRep(data: data)
        else { return nil }

        let sx = CGFloat(bitmap.pixelsWide) / CGFloat(context.hierarchyWidth)
        let sy = CGFloat(bitmap.pixelsHigh) / CGFloat(context.hierarchyHeight)
        let x0 = max(0, Int(node.frame.minX * sx))
        let y0 = max(0, Int(node.frame.minY * sy))
        let x1 = min(bitmap.pixelsWide - 1, Int(node.frame.maxX * sx))
        let y1 = min(bitmap.pixelsHigh - 1, Int(node.frame.maxY * sy))

        guard x1 > x0 + 2, y1 > y0 + 2 else { return nil }

        var border: [NSColor] = []
        var interior: [NSColor] = []
        let stepX = max(1, (x1 - x0) / 12)
        let stepY = max(1, (y1 - y0) / 12)

        for x in stride(from: x0, through: x1, by: stepX) {
            if let c = color(bitmap, x: x, topY: y0) { border.append(c) }
            if let c = color(bitmap, x: x, topY: y1) { border.append(c) }
        }
        for y in stride(from: y0, through: y1, by: stepY) {
            if let c = color(bitmap, x: x0, topY: y) { border.append(c) }
            if let c = color(bitmap, x: x1, topY: y) { border.append(c) }
        }

        let insetX = max(1, (x1 - x0) / 6)
        let insetY = max(1, (y1 - y0) / 6)
        for x in stride(from: x0 + insetX, through: max(x0 + insetX, x1 - insetX), by: stepX) {
            for y in stride(from: y0 + insetY, through: max(y0 + insetY, y1 - insetY), by: stepY) {
                if let c = color(bitmap, x: x, topY: y) { interior.append(c) }
            }
        }

        guard !border.isEmpty, !interior.isEmpty else { return nil }

        let background = medianColor(border)
        let bgLum = luminance(background)

        // Text pixels normally differ substantially from the local background.
        let candidates = interior.filter { abs(luminance($0) - bgLum) > 0.08 }
        guard !candidates.isEmpty else { return nil }

        let foreground = medianColor(candidates)
        let ratio = contrastRatio(luminance(foreground), bgLum)
        return Measurement(ratio: ratio, foreground: foreground, background: background)
    }

    private static func color(_ bitmap: NSBitmapImageRep, x: Int, topY: Int) -> NSColor? {
        let y = bitmap.pixelsHigh - 1 - topY
        guard x >= 0, x < bitmap.pixelsWide, y >= 0, y < bitmap.pixelsHigh else { return nil }
        return bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
    }

    private static func medianColor(_ colors: [NSColor]) -> NSColor {
        let values = colors.compactMap { $0.usingColorSpace(.deviceRGB) }.map { ($0.redComponent, $0.greenComponent, $0.blueComponent) }
        guard !values.isEmpty else { return .white }
        func median(_ values: [CGFloat]) -> CGFloat {
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
        return NSColor(deviceRed: median(values.map(\.0)), green: median(values.map(\.1)), blue: median(values.map(\.2)), alpha: 1)
    }

    private static func luminance(_ color: NSColor) -> Double {
        let c = color.usingColorSpace(.deviceRGB) ?? color
        func linear(_ v: CGFloat) -> Double {
            let x = Double(v)
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }

    private static func contrastRatio(_ a: Double, _ b: Double) -> Double {
        let light = max(a, b)
        let dark = min(a, b)
        return (light + 0.05) / (dark + 0.05)
    }
}

private enum ContrastRuleFactory {
    static func result(
        node: AccessibilityNode,
        context: AccessibilityRuleContext,
        ruleID: String,
        title: String,
        description: String,
        threshold: Double,
        requirement: String
    ) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.isText(node), node.visible, !node.label.isEmpty else { return nil }
        guard let measurement = ScreenshotContrastAnalyzer.measure(node: node, context: context) else {
            return RuleHelper.validation(ruleID: ruleID, name: title, description: description, node: node,
                                         message: "The screenshot did not provide enough reliable pixels to measure the rendered text contrast.",
                                         remediation: "Verify the rendered foreground/background contrast manually or with a dedicated pixel-level contrast tool.")
        }
        let ratioText = String(format: "%.2f:1", measurement.ratio)
        if measurement.ratio + 0.001 < threshold {
            return RuleHelper.fail(ruleID: ruleID, name: title, description: description, node: node,
                                   message: "Measured rendered contrast is \(ratioText), below the required \(requirement).",
                                   remediation: "Increase the effective foreground/background contrast to at least \(requirement).")
        }
        return RuleHelper.pass(ruleID: ruleID, name: title, description: description, node: node,
                               message: "Measured rendered contrast is \(ratioText), meeting the required \(requirement).")
    }
}

struct ContrastStandardTextRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "contrast-standard-text-4-5"
    let title = "Verify if color contrast for standard text with its background is sufficient"
    let description = "Standard text should meet a minimum 4.5:1 contrast ratio."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.isText(node), node.visible, !node.label.isEmpty else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Rendered contrast requires screenshot analysis.",
                                     remediation: "Capture the rendered screen and measure the effective foreground/background contrast.")
    }
    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        ContrastRuleFactory.result(node: node, context: context, ruleID: id, title: title, description: description, threshold: 4.5, requirement: "4.5:1")
    }
}

struct ContrastLargeTextRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "contrast-large-text-3"
    let title = "Verify if color contrast for large text with its background is sufficient"
    let description = "Large text should meet a minimum 3:1 contrast ratio."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.isText(node), node.visible, !node.label.isEmpty else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Rendered contrast requires screenshot analysis.",
                                     remediation: "Capture the rendered screen and measure the effective foreground/background contrast.")
    }
    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        ContrastRuleFactory.result(node: node, context: context, ruleID: id, title: title, description: description, threshold: 3.0, requirement: "3:1")
    }
}

struct ContrastEnhancedStandardTextRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "contrast-standard-text-7"
    let title = "Check if the contrast ratio of standard text ... is 7:1"
    let description = "Standard text enhanced contrast requirement."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.isText(node), node.visible, !node.label.isEmpty else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Rendered contrast requires screenshot analysis.",
                                     remediation: "Capture the rendered screen and measure the effective foreground/background contrast.")
    }
    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        ContrastRuleFactory.result(node: node, context: context, ruleID: id, title: title, description: description, threshold: 7.0, requirement: "7:1")
    }
}

struct ContrastEnhancedLargeTextRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "contrast-large-text-4-5"
    let title = "Check if the contrast ratio of large text ... is 4.5:1"
    let description = "Large text enhanced contrast requirement."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.isText(node), node.visible, !node.label.isEmpty else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Rendered contrast requires screenshot analysis.",
                                     remediation: "Capture the rendered screen and measure the effective foreground/background contrast.")
    }
    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        ContrastRuleFactory.result(node: node, context: context, ruleID: id, title: title, description: description, threshold: 4.5, requirement: "4.5:1")
    }
}

struct ContrastImageBackgroundRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "contrast-text-over-image"
    let title = "Check contrast between text and background image"
    let description = "Text over imagery must maintain sufficient rendered contrast."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.isText(node), node.visible, !node.label.isEmpty else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Rendered contrast requires screenshot analysis.",
                                     remediation: "Capture the rendered screen and measure the effective foreground/background contrast.")
    }
    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        ContrastRuleFactory.result(node: node, context: context, ruleID: id, title: title, description: description, threshold: 4.5, requirement: "4.5:1")
    }
}

struct ContrastOpacityRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "contrast-opacity"
    let title = "Check contrast with opacity"
    let description = "Effective rendered contrast must remain sufficient after opacity/compositing."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.isText(node), node.visible, !node.label.isEmpty else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Rendered contrast requires screenshot analysis.",
                                     remediation: "Capture the rendered screen and measure the effective foreground/background contrast.")
    }
    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        ContrastRuleFactory.result(node: node, context: context, ruleID: id, title: title, description: description, threshold: 4.5, requirement: "4.5:1")
    }
}

struct TextResizeRule: AccessibilityRule {
    let id = "text-resize"
    let title = "Text can be resized"
    let description = "Text should remain usable when Dynamic Type/accessibility text size is increased."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.isText(node), node.visible, !node.label.isEmpty else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Text resizing requires running the app under larger accessibility text settings and comparing layouts.",
                                     remediation: "Run a text-size sweep and verify text remains readable and usable.")
    }
}

struct LinkRoleRule: AccessibilityRule {
    let id = "text-link-role"
    let title = "Text functions as a link but is missing role link"
    let description = "Link-like text should expose link semantics."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.type == "XCUIElementTypeStaticText", node.visible, !node.label.isEmpty else { return nil }
        let hint = (node.label + " " + node.identifier).lowercased()
        guard hint.contains("http") || hint.contains("www") || hint.contains("link") else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Text appears link-like; verify it exposes a link role and is operable.",
                                     remediation: "Expose link semantics if activating the text navigates somewhere.")
    }
}

struct ButtonRoleRule: AccessibilityRule {
    let id = "text-button-role"
    let title = "Text functions as a button but is missing role button"
    let description = "Actionable text should expose button semantics when appropriate."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.type == "XCUIElementTypeStaticText", node.visible else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "WDA cannot determine whether a static text element has a tap gesture. Verify actionable text manually or through interaction testing.",
                                     remediation: "If the text performs an action, expose an appropriate button role.")
    }
}

struct DecorativeImageRule: AccessibilityRule {
    let id = "decorative-image"
    let title = "Check if Image should be marked as decorative"
    let description = "Decorative images should not add redundant screen-reader content."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.type == "XCUIElementTypeImage", node.visible else { return nil }
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
        guard RuleHelper.controls.contains(node.type), node.visible else { return nil }
        if node.hittable && !node.accessible {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Control is hittable but not exposed as accessible.",
                                   remediation: "Expose the control to assistive technology unless it is intentionally excluded.")
        }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Verify the control is intentionally exposed or intentionally hidden.",
                                     remediation: "Confirm screen-reader users can operate every required interactive control.")
    }
}

struct MotionAlternativeRule: AccessibilityRule {
    let id = "motion-alternative"
    let title = "No On-Screen Alternative for Motion Action"
    let description = "Motion-driven actions should have an accessible non-motion alternative."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.visible else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Motion-based interaction cannot be inferred from the static accessibility tree.",
                                     remediation: "Exercise motion features and verify an equivalent on-screen control exists.")
    }
}

struct FocusOrderRule: AccessibilityRule {
    let id = "focus-order"
    let title = "Check if focus order is correct on the screen"
    let description = "Accessibility focus should follow a meaningful reading/interaction order."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.type == "XCUIElementTypeApplication" else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Focus order requires observing actual accessibility focus traversal.",
                                     remediation: "Traverse the screen with VoiceOver/keyboard focus and compare the order with the visual reading order.")
    }
}

struct OrientationRule: AccessibilityRule {
    let id = "orientation-support"
    let title = "Check if all the content is available when the device orientation is changed"
    let description = "Content should remain available in supported orientations."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.type == "XCUIElementTypeApplication" else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Orientation behavior requires rotating the device and rescanning the hierarchy.",
                                     remediation: "Run portrait and landscape scans and compare available content and controls.")
    }
}

struct ScreenReaderContentRule: AccessibilityRule {
    let id = "screen-reader-content"
    let title = "Content can be accessed by screen reader user"
    let description = "Meaningful content should be exposed to assistive technology."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.visible, !node.accessible, !node.children.isEmpty else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "This container is not accessible; verify that meaningful descendants are still exposed correctly.",
                                     remediation: "Ensure content is not unintentionally removed from the accessibility tree.")
    }
}

struct LanguageRule: AccessibilityRule {
    let id = "language"
    let title = "Missing language attribute for content"
    let description = "Content language should be correctly identified where it differs from the app language."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.type == "XCUIElementTypeApplication" else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Language metadata is not exposed by the current WDA XML model.",
                                     remediation: "Verify app and per-content language attributes using VoiceOver or accessibility APIs.")
    }
}

struct ModalAccessibilityRule: AccessibilityRule {
    let id = "modal-accessibility"
    let title = "Modal dialog is accessible for screen reader users"
    let description = "Modal dialogs should expose their content and allow dismissal."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        let text = (node.type + " " + node.identifier + " " + node.label).lowercased()
        guard text.contains("modal") || text.contains("dialog") else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Possible modal/dialog detected; verify focus containment, announcement, and dismissal.",
                                     remediation: "Open the modal and verify screen-reader access and a clear close/dismiss action.")
    }
}

struct LoadingIndicatorContrastRule: AccessibilityRule {
    let id = "loading-indicator-contrast"
    let title = "Loading indicator has sufficient contrast with its background"
    let description = "Loading indicators should remain distinguishable from their background."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        let text = (node.type + " " + node.identifier + " " + node.label).lowercased()
        guard text.contains("progress") || text.contains("loading") || text.contains("activity") else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Rendered colors are unavailable from WDA; verify loading indicator contrast visually.",
                                     remediation: "Measure indicator/background contrast in the rendered screenshot.")
    }
}

struct LiveRegionRule: AccessibilityRule {
    let id = "live-region"
    let title = "Live region is defined for dynamic content"
    let description = "Dynamic updates that require announcement should expose appropriate accessibility notifications."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.type == "XCUIElementTypeStaticText", node.visible else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Dynamic update behavior cannot be inferred from a static hierarchy snapshot.",
                                     remediation: "Trigger the update and verify the screen-reader announcement.")
    }
}

struct TimeLimitedUIRule: AccessibilityRule {
    let id = "time-limited-ui"
    let title = "Time-limited UI has a visible user control"
    let description = "Time-limited content should provide a user-controlled extension or equivalent mechanism."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.type == "XCUIElementTypeApplication" else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Timing behavior cannot be inferred from one hierarchy snapshot.",
                                     remediation: "Exercise timed UI and verify a visible mechanism to extend or disable the time limit.")
    }
}

struct FocusIndicatorRule: AccessibilityRule {
    let id = "focus-indicator"
    let title = "Focus indicator is clearly visible"
    let description = "Keyboard/accessibility focus should have a visible indicator with sufficient contrast."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.type == "XCUIElementTypeApplication" else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Focus-indicator visibility requires actual keyboard/VoiceOver focus and screenshot comparison.",
                                     remediation: "Move focus across controls and verify a visible, sufficiently contrasting indicator.")
    }
}

struct NonTextContrastRule: AccessibilityRule {
    let id = "non-text-contrast"
    let title = "Non-text element has sufficient contrast with its background"
    let description = "Meaningful non-text UI components should have sufficient contrast."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.controls.contains(node.type) || node.type == "XCUIElementTypeImage", node.visible else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Rendered colors cannot be obtained from WDA; verify non-text contrast visually.",
                                     remediation: "Measure the relevant component and background contrast in the screenshot.")
    }
}

struct FormBorderContrastRule: AccessibilityRule {
    let id = "form-border-contrast"
    let title = "Border of form controls has sufficient contrast with its background"
    let description = "Visible form-control boundaries should remain distinguishable."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.textInputs.contains(node.type), node.visible else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Border color is not exposed by WDA.",
                                     remediation: "Measure the rendered control border against its background.")
    }
}

struct ErrorMessageRule: AccessibilityRule {
    let id = "error-message-accessibility"
    let title = "Error message is accessible and includes a suggestion to fix it"
    let description = "Validation errors should be announced and provide useful recovery guidance."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        let text = (node.label + " " + (node.value ?? "")).lowercased()
        guard text.contains("error") || text.contains("invalid") else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Error-like content detected; verify announcement and corrective guidance after submitting the form.",
                                     remediation: "Trigger the validation error and verify it is announced and explains how to fix the problem.")
    }
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
    let title = "Gesture-only control is operable with keyboard"
    let description = "Important actions should have an operable non-gesture alternative."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.type == "XCUIElementTypeApplication" else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Gesture-only operation cannot be inferred from the hierarchy.",
                                     remediation: "Exercise gesture interactions and verify keyboard/assistive-technology alternatives where applicable.")
    }
}

struct TouchPhaseRule: AccessibilityRule {
    let id = "touch-up-cancellation"
    let title = "Action fires on touch up, allowing cancellation"
    let description = "Actions should generally allow cancellation before activation where applicable."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.controls.contains(node.type), node.visible else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Touch-down/touch-up behavior cannot be inferred from WDA XML.",
                                     remediation: "Interact with the control and verify activation can be cancelled before touch-up when applicable.")
    }
}

struct ComplexGestureRule: AccessibilityRule {
    let id = "complex-gesture-alternative"
    let title = "Complex gesture has no accessibility alternative"
    let description = "Complex gestures should have an equivalent accessible action."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.type == "XCUIElementTypeApplication" else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Complex gestures cannot be identified from the static hierarchy.",
                                     remediation: "Exercise complex gestures and verify equivalent accessible actions/custom actions.")
    }
}

struct ReadingOrderRule: AccessibilityRule {
    let id = "reading-order"
    let title = "Reading order is accurate"
    let description = "Accessibility traversal should follow a meaningful reading order."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.type == "XCUIElementTypeApplication" else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Reading order cannot be proven from a static hierarchy alone.",
                                     remediation: "Traverse the screen with VoiceOver and compare focus order with the intended visual reading order.")
    }
}

struct KeyboardFocusRule: AccessibilityRule {
    let id = "keyboard-focus"
    let title = "Interactive control can receive keyboard focus"
    let description = "Keyboard users should be able to reach interactive controls where keyboard operation is supported."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.controls.contains(node.type), node.visible else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Keyboard focusability is not exposed by the WDA node model.",
                                     remediation: "Run keyboard navigation and verify every required control can receive focus.")
    }
}

struct StateUpdateRule: AccessibilityRule {
    let id = "state-updates-after-interaction"
    let title = "State does not get updated on user interaction"
    let description = "Interactive state should update after user actions."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.controls.contains(node.type), node.visible else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "State transition requires an interaction probe; this snapshot only shows the current state.",
                                     remediation: "Interact with the control, capture a second hierarchy, and verify the state/value changes correctly.")
    }
}

struct LinkColorRule: AccessibilityRule {
    let id = "link-color-differentiation"
    let title = "Link color differentiation check"
    let description = "Links should not rely on color alone to communicate their role."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        let text = (node.label + " " + node.identifier).lowercased()
        guard text.contains("link") else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Rendered link color and non-color differentiation are not exposed by WDA.",
                                     remediation: "Verify links have sufficient contrast and a non-color cue where required.")
    }
}

struct VisualLabelRule: AccessibilityRule {
    let id = "visual-label"
    let title = "Visual label is specified for form control"
    let description = "Form controls should have a visible, persistent label."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.textInputs.contains(node.type), node.visible else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Visual-label presence cannot be determined from the accessibility hierarchy alone.",
                                     remediation: "Inspect the screenshot and verify a persistent visible label is associated with the field.")
    }
}

struct LanguageChangeRule: AccessibilityRule {
    let id = "language-change"
    let title = "Change in language is defined correctly"
    let description = "Content language changes should be identified correctly."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.isText(node), node.visible else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Per-element language metadata is not exposed by WDA XML.",
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
    let title = "Modal contains keyboard-focusable controls — keyboard focus can be contained"
    let description = "Modal dialogs should manage focus so it does not escape unexpectedly."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        let text = (node.type + " " + node.identifier + " " + node.label).lowercased()
        guard text.contains("modal") || text.contains("dialog") else { return nil }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Focus containment requires opening the modal and exercising keyboard/assistive-technology focus.",
                                     remediation: "Verify focus enters the modal, remains within it as required, and returns appropriately after dismissal.")
    }
}
