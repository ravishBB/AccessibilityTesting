
import Foundation
import CoreGraphics
import AppKit

// MARK: - Common rule context
nonisolated struct AccessibilityRuleContext {
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

nonisolated protocol ContextualAccessibilityRule {
    func evaluate(
        node: AccessibilityNode,
        context: AccessibilityRuleContext
    ) -> AccessibilityRuleEvaluation?
}


// MARK: - Rule catalog

nonisolated struct AccessibilityRules {

    static var all: [AccessibilityRule] {
        [
            // Existing / direct element rules
            CommonAccessibleNameRule(),
            DescriptiveButtonNameRule(),
            ImageButtonNameRule(),
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
            InputPurposeRule(),
            ScreenTitleRule(),
            DuplicateInteractiveNameRule(),
            InteractiveTargetOverlapRule(),

            ContrastStandardTextRule(),
            ContrastLargeTextRule(),
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
            StatusLiveRegionRule(),
            TimeLimitedUIRule(),
            FocusIndicatorRule(),
            NonTextContrastRule(),
            FormBorderContrastRule(),
            ErrorExposureRule(),
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
            LanguageChangeRule(),
            TextSpacingRule(),
            ModalFocusContainmentRule(),
            MissingRoleRule(),
            NameViaHintRule(),
            LabelInNameRule(),
            HeadingCandidateRule(),
            FocusIndicatorContrastRule(),
            FocusNotObscuredRule(),
            ModalClosableRule()
        ]
    }
}

// MARK: - Core common rules
nonisolated struct CommonAccessibleNameRule: AccessibilityRule {
    let id = "accessible-name"
    let title = "Accessible Name"
    let description = "Interactive controls must expose a meaningful accessible name."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.controls.contains(node.role), node.visible, node.enabled,
              !node.semantics.mergedIntoAncestor else { return nil }
        // Buttons have a dedicated descriptive-name rule. Keeping the common
        // rule off buttons prevents duplicate PASS/FAIL records.
        guard node.role != .button else { return nil }
        // A name given only as a hint is reported by name-via-hint.
        guard !RuleHelper.isNamedOnlyByHint(node) else { return nil }
        if RuleHelper.clean(node.label).isEmpty {
            let imageSegments = node.role == .segmentedControl &&
                RuleHelper.allNodes(node).dropFirst().contains { $0.role == .image }
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: imageSegments
                                       ? "Image segmented control has no accessible name."
                                       : "Interactive element has no accessible name.",
                                   remediation: "Provide a meaningful accessibility label.")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Interactive element has an accessible name.")
    }
}

nonisolated struct CommonMinimumTargetSizeRule: ScreenAccessibilityRule {
    let id = "touch-target-size-24"
    let title = "Interactive controls meet the minimum target size (24pt) requirement"
    let description = "Interactive controls should provide at least a 24×24 point target."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }

    /// WCAG 2.5.8: a target under 24×24 still passes when a 24-diameter circle
    /// centred on it touches no other target and no other undersized
    /// target's circle (the spacing exception).
    func evaluate(rootNode: AccessibilityNode) -> [AccessibilityRuleEvaluation] {
        let targets = RuleHelper.allNodes(rootNode).filter {
            RuleHelper.controls.contains($0.role) && $0.visible && $0.enabled &&
                RuleHelper.isWhollyMeasurable($0) && $0.frame.width > 0 && $0.frame.height > 0
        }
        let unit = rootNode.platform.sizeUnit
        func undersized(_ node: AccessibilityNode) -> Bool { node.frame.width < 24 || node.frame.height < 24 }
        func center(_ node: AccessibilityNode) -> CGPoint { CGPoint(x: node.frame.midX, y: node.frame.midY) }
        func distance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            return (dx * dx + dy * dy).squareRoot()
        }

        return targets.map { node in
            guard undersized(node) else {
                return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                       message: "Interactive control meets the 24×24 \(unit) minimum target size.")
            }
            let point = center(node)
            let crowding = targets.first { other in
                guard other.frame != node.frame, !other.frame.contains(node.frame), !node.frame.contains(other.frame) else { return false }
                if undersized(other) {
                    let o = center(other)
                    return ((o.x - point.x) * (o.x - point.x) + (o.y - point.y) * (o.y - point.y)).squareRoot() < 24
                }
                return distance(point, to: other.frame) < 12
            }
            let size = "\(Int(node.frame.width.rounded()))×\(Int(node.frame.height.rounded())) \(unit)"
            guard let crowding else {
                return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                       message: "The control is \(size), under 24×24, but nothing else is within the 24 \(unit) spacing circle, so it meets the spacing exception.")
            }
            let neighbour = crowding.label.isEmpty ? crowding.type.replacingOccurrences(of: "XCUIElementType", with: "") : crowding.label
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "The control is \(size) and \"\(neighbour)\" is within its 24 \(unit) spacing circle, so it meets neither the minimum size nor the spacing exception.",
                                   remediation: "Increase the target to at least 24×24 \(unit) (for example with a larger contentShape or padding), or move neighbouring targets further away.")
        }
    }
}

// MARK: - Helpers

private nonisolated enum RuleHelper {

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

    static func words(_ node: AccessibilityNode) -> Set<String> {
        var spaced = ""
        var previous: Character?
        for character in node.label + " " + node.identifier {
            if let previous, previous.isLowercase, character.isUppercase { spaced.append(" ") }
            spaced.append(character)
            previous = character
        }
        let parts = spaced.lowercased().split { !$0.isLetter && !$0.isNumber }
        return Set(parts.map(String.init))
    }

    /// No accessible name, but a hint or tooltip that names the purpose
    /// (Android exposes both; iOS does not expose hints).
    static func isNamedOnlyByHint(_ node: AccessibilityNode) -> Bool {
        guard controls.contains(node.role), !textInputs.contains(node.role), node.visible,
              clean(node.label).isEmpty
        else { return false }
        return !clean(node.semantics.hint ?? node.semantics.tooltip).isEmpty
    }

    /// A control checked on its own, whose frame in this snapshot is its
    /// real size: not merged into a clickable parent, not cut off by scrolling.
    static func isWhollyMeasurable(_ node: AccessibilityNode) -> Bool {
        !node.semantics.mergedIntoAncestor && !node.semantics.partiallyVisible
    }

    /// A descendant that exposes a real control role (not guessed).
    static func childControl(of node: AccessibilityNode) -> AccessibilityNode? {
        let roles: Set<AccessibilityRole> = [.checkBox, .radioButton, .toggle, .button, .slider]
        return allNodes(node).dropFirst().first {
            $0.visible && roles.contains($0.role) && !$0.semantics.roleInferred
        }
    }

    /// Text that reads as a sentence or description, not as the label of a
    /// tappable item.
    static func isDescriptiveText(_ text: String) -> Bool {
        let value = clean(text)
        if wordList(value).count > 5 { return true }
        return value.contains("—") || value.contains("(") || value.hasSuffix(".") || value.contains(": ")
    }

    /// The most prominent text inside a card: the tallest line of text,
    /// which is the headline rather than a tag or byline.
    static func titleText(of node: AccessibilityNode) -> String? {
        let texts = allNodes(node).dropFirst().filter {
            $0.role == .staticText && $0.visible && wordList(clean($0.label)).count >= 2
        }
        func lineHeight(_ text: AccessibilityNode) -> Double {
            text.semantics.textSizePoints
                ?? TextSizeEstimate.fontSize(frame: text.frame, text: text.label).map(Double.init)
                ?? Double(text.frame.height)
        }
        return texts.max { lineHeight($0) < lineHeight($1) }.map { clean($0.label) }
    }

    static func childTextSegments(of node: AccessibilityNode) -> [String]? {
        let parts = allNodes(node).dropFirst()
            .filter { $0.role == .staticText && $0.visible }
            .map { clean($0.label) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts
    }

    static func childText(of node: AccessibilityNode) -> String? {
        let parts = allNodes(node).dropFirst()
            .filter { $0.role == .staticText && $0.visible }
            .map { clean($0.label) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    static func wordList(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }


    static func isBelowOrBeside(_ text: AccessibilityNode, _ field: AccessibilityNode) -> Bool {
        let verticalGap = max(text.frame.minY - field.frame.maxY, field.frame.minY - text.frame.maxY, 0)
        let horizontalOverlap = min(text.frame.maxX, field.frame.maxX) - max(text.frame.minX, field.frame.minX)
        return verticalGap <= 60 && horizontalOverlap > 0
    }

    static func isScrollContainer(_ node: AccessibilityNode) -> Bool {
        node.role == .scrollView || node.role == .table ||
            node.type.contains("ScrollView") || node.type.contains("CollectionView") ||
            node.traits.contains("scrollable")
    }

    static func isGenericName(_ value: String) -> Bool {
        let normalized = clean(value).lowercased()
        if normalized.isEmpty { return true }

        let generic = [
            "button", "btn", "click", "click here", "tap", "tap here",
            "image", "img", "icon", "action", "item", "cell", "link", "view", "label"
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
nonisolated struct DescriptiveButtonNameRule: AccessibilityRule {
    let id = "button-name-descriptive"
    let title = "Accessible name for button is descriptive"
    let description = "Button names should identify the action or purpose."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .button, node.visible, !node.semantics.mergedIntoAncestor else { return nil }
        // Image-only buttons are reported by the image-button-specific rule.
        guard !RuleHelper.isImageLikeButton(node) else { return nil }
        guard !RuleHelper.isNamedOnlyByHint(node) else { return nil }
        if RuleHelper.isGenericName(node.label) {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Button accessible name is missing or generic.",
                                   remediation: "Provide a concise name describing the button's action or purpose.")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Button has a descriptive-looking accessible name.")
    }
}

nonisolated struct ImageButtonNameRule: AccessibilityRule {
    let id = "image-button-name"
    let title = "Missing accessible name for image button"
    let description = "Image-only buttons need an accessible name."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .button, node.visible, !node.semantics.mergedIntoAncestor else { return nil }
        let imageLike = RuleHelper.isImageLikeButton(node)
        guard imageLike, !RuleHelper.isNamedOnlyByHint(node) else { return nil }
        return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                               message: "Image-based button has no accessible name.",
                               remediation: "Provide an accessibility label that describes the action, not only the image appearance.")
    }
}

nonisolated struct PlaceholderOnlyNameRule: AccessibilityRule {
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

nonisolated struct DescriptiveInteractiveNameRule: AccessibilityRule {
    let id = "interactive-name-descriptive"
    let title = "Accessible name for interactive element is descriptive"
    let description = "Interactive elements should expose meaningful names."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.controls.contains(node.role), node.visible,
              !node.semantics.mergedIntoAncestor else { return nil }
        guard node.role != .button else { return nil }
        // A missing name is reported once, by accessible-name.
        guard !RuleHelper.clean(node.label).isEmpty else { return nil }
        if RuleHelper.isGenericName(node.label) {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Interactive element has a generic accessible name.",
                                   remediation: "Use a name that communicates the control's purpose.")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Interactive element has a descriptive-looking accessible name.")
    }
}

nonisolated struct AccessibleLabelImageRule: AccessibilityRule {
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

nonisolated struct DescriptiveImageRule: AccessibilityRule {
    let id = "image-name-descriptive"
    let title = "Non-descriptive accessible name for image"
    let description = "Image labels should communicate meaningful content."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .image, node.visible, node.accessible else { return nil }
        // A missing label is reported once, by image-accessible-label.
        guard !RuleHelper.clean(node.label).isEmpty else { return nil }
        if RuleHelper.isGenericName(node.label) {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Image accessible name is generic.",
                                   remediation: "Describe the meaningful content or purpose of the image.")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Image has a descriptive-looking accessible name.")
    }
}

nonisolated struct AdjustableValueRule: AccessibilityRule {
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

nonisolated struct DuplicateInteractiveNameRule: ScreenAccessibilityRule {
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

nonisolated struct InteractiveTargetOverlapRule: ScreenAccessibilityRule {
    let id = "interactive-target-overlap"
    let title = "Interactive targets do not improperly overlap"
    let description = "Interactive controls should not substantially overlap in a way that can make activation ambiguous."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        nil
    }

    func evaluate(rootNode: AccessibilityNode) -> [AccessibilityRuleEvaluation] {
        let controls = RuleHelper.visibleInteractiveNodes(rootNode).filter { !$0.semantics.mergedIntoAncestor }
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

nonisolated struct DisabledButtonStateRule: AccessibilityRule {
    let id = "button-disabled-state"
    let title = "Disabled state of button not defined"
    let description = "A disabled button should expose its disabled state consistently."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .button, node.visible else { return nil }
        // Only a disabled button is evidence: it shows the disabled state is
        // exposed. An enabled button proves nothing either way.
        guard !node.enabled else { return nil }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Button is exposed as disabled by the accessibility hierarchy.")
    }
}

nonisolated struct RoleTraitConsistencyRule: AccessibilityRule {
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

nonisolated struct StateTraitConsistencyRule: AccessibilityRule {
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

        // A missing value on an adjustable control is reported once, by
        // adjustable-accessibility-value.

        return RuleHelper.pass(
            ruleID: id, name: title, description: description, node: node,
            message: "Current enabled, hittable, and exposed state information is internally consistent."
        )
    }
}

nonisolated struct TextClippingRule: ScreenAccessibilityRule {
    let id = "text-clipping"
    let title = "Text is not clipped by layout bounds"
    let description = "Visible text should remain within the screen and its accessible layout bounds."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        nil
    }

    func evaluate(rootNode: AccessibilityNode) -> [AccessibilityRuleEvaluation] {
        let rootBounds = rootNode.frame

        // Text inside a scrolling container (carousel, list) that runs past
        // the screen edge is scrolled out of view, not clipped.
        var texts: [(node: AccessibilityNode, insideScroll: Bool)] = []
        func collect(_ node: AccessibilityNode, insideScroll: Bool) {
            let scrolls = insideScroll || RuleHelper.isScrollContainer(node)
            if RuleHelper.isText(node) { texts.append((node, insideScroll)) }
            node.children.forEach { collect($0, insideScroll: scrolls) }
        }
        collect(rootNode, insideScroll: false)

        return texts.compactMap { node, insideScroll in
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
            let visibleArea = visibleIntersection.isNull ? 0 : max(visibleIntersection.width * visibleIntersection.height, 0)
            let visibleRatio = visibleArea / area

            // Wholly off screen, or partly scrolled out of a scroll view: not clipping.
            if visibleRatio == 0 || (insideScroll && visibleRatio < 0.80) {
                return nil
            }

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

nonisolated struct HeadingQualityRule: AccessibilityRule {
    let id = "heading-quality"
    let title = "Non-descriptive heading text"
    let description = "Headings should provide meaningful section context."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        // VoiceOver skips a container that is not an accessibility element;
        // the text inside it (checked itself) is what users hear.
        guard RuleHelper.hasTrait(node, RuleHelper.headingsTraits), node.visible,
              node.accessible || RuleHelper.isText(node),
              !node.semantics.mergedIntoAncestor else { return nil }
        let label = RuleHelper.clean(node.label).isEmpty
            ? RuleHelper.childText(of: node) ?? ""
            : RuleHelper.clean(node.label)
        // A "heading" that reads like body text (long, or a full sentence)
        // may be marked as a heading by mistake.
        if label.count > 80 || RuleHelper.wordList(label).count > 12 || label.hasSuffix(".") {
            return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                         message: "This text is marked as a heading but reads like body text (\(RuleHelper.wordList(label).count) words).",
                                         remediation: "Mark only text that introduces a section as a heading.")
        }
        if RuleHelper.isGenericName(label) {
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "Heading text is missing or generic.",
                                   remediation: "Use concise text that identifies the section.")
        }
        return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                               message: "Heading has a meaningful-looking label.")
    }
}

nonisolated struct SegmentControlRule: AccessibilityRule {
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

nonisolated struct TabAccessibilityRule: AccessibilityRule {
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

nonisolated struct FormLabelRule: ScreenAccessibilityRule {
    let id = "form-visual-label"
    let title = "Form controls have an associated visible label"
    let description = "Form controls should have a visible label independent of placeholder text."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        nil
    }

    func evaluate(rootNode: AccessibilityNode) -> [AccessibilityRuleEvaluation] {
        RuleHelper.allNodes(rootNode).compactMap { node in
            guard RuleHelper.textInputs.contains(node.role), node.visible else { return nil }

            if let visualLabel = RuleHelper.nearbyVisualLabel(for: node, in: rootNode) {
                return RuleHelper.pass(
                    ruleID: id,
                    name: title,
                    description: description,
                    node: node,
                    message: "A nearby visible text label (\"\(RuleHelper.clean(visualLabel.label))\") is associated with the form control by screen geometry."
                )
            }

            // No name, no placeholder and no text next to it: nothing tells a
            // sighted user what to enter. (Placeholder-only fields are
            // reported by placeholder-only-name.)
            if RuleHelper.clean(node.label).isEmpty, RuleHelper.clean(node.placeholderValue).isEmpty {
                return RuleHelper.fail(
                    ruleID: id,
                    name: title,
                    description: description,
                    node: node,
                    message: "The field has no visible label, no placeholder and no accessible name.",
                    remediation: "Add a persistent visible label next to the field and use it as the accessible name."
                )
            }

            return RuleHelper.validation(
                ruleID: id,
                name: title,
                description: description,
                node: node,
                message: RuleHelper.clean(node.label).isEmpty
                    ? "No accessible or nearby visible text label could be established from the current hierarchy."
                    : "The field has an accessible name (\"\(RuleHelper.clean(node.label))\"), but no visible label could be found next to it.",
                remediation: "Provide a persistent visible label associated with the field; do not rely on placeholder text alone."
            )
        }
    }
}


nonisolated struct ScreenTitleRule: AccessibilityRule {
    let id = "screen-title"
    let title = "Title is specified for screen"
    let description = "Screens should expose a meaningful title to assistive technology."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        // Android panes (activities, dialogs, Compose/Flutter/RN screens)
        // can carry a title without a toolbar.
        if let paneTitle = node.semantics.paneTitle {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "The screen pane exposes the title \"\(paneTitle)\".")
        }
        guard node.role == .navigationBar, node.visible else { return nil }
        // UIKit and SwiftUI put the title in the bar's name or in a text
        // element inside the bar (large titles), not always in its label.
        let shownTitle = [RuleHelper.clean(node.label), RuleHelper.childText(of: node) ?? "", RuleHelper.clean(node.identifier)]
            .first { !$0.isEmpty && !RuleHelper.isGenericName($0) }
        if let shownTitle, RuleHelper.clean(node.label).isEmpty {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "Navigation bar exposes the screen title \"\(shownTitle)\".")
        }
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

private nonisolated struct ValidationRule: AccessibilityRule {
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
private nonisolated enum ContrastTarget {
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
private nonisolated enum ContrastBackground {
    case flat
    case varied
    case any
}

private nonisolated enum ContrastRuleFactory {

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
        guard RuleHelper.isText(node), node.visible, !node.label.isEmpty,
              !node.semantics.partiallyVisible else { return nil }
        // A text field's frame is the whole box. Its label, placeholder and
        // typed text are drawn by child text nodes (measured themselves) or
        // are absent when nothing has been typed.
        if RuleHelper.textInputs.contains(node.role),
           RuleHelper.childText(of: node) != nil || RuleHelper.clean(node.value).isEmpty {
            return nil
        }

        // Emoji are pictographs drawn in their own colours, not text.
        let glyphs = node.label.unicodeScalars.filter { !$0.properties.isWhitespace }
        if !glyphs.isEmpty, glyphs.allSatisfy({ $0.properties.isEmojiPresentation || $0.properties.isEmojiModifier || $0.value == 0xFE0F || $0.value == 0x200D }) {
            return nil
        }

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

        let unit = node.platform == .android ? "sp" : "pt"
        let estimatedSize: String
        if let points = node.semantics.textSizePoints {
            estimatedSize = "\(Int(points.rounded())) \(unit)"
        } else {
            estimatedSize = TextSizeEstimate.fontSize(frame: node.frame, text: node.label)
                .map { "estimated \(Int($0.rounded())) \(unit)" } ?? "size unknown"
        }
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
            // Over an image or gradient the worst-case pixel decides the
            // ratio, and a busy area of the image can sit under one letter
            // only. A tester judges whether the text is readable.
            if measurement.variedBackground {
                return RuleHelper.validation(ruleID: ruleID, name: title, description: description, node: node,
                                             message: "The \(basis) is \(measured) (\(sizeText)), below \(requirement). Check whether the text stays readable over the whole background.",
                                             remediation: "If any part of the text is hard to read, add a scrim or solid backing so the contrast is at least \(requirement).")
            }
            // About 1:1 means no text is drawn at this position: it is
            // covered (a bar, a sheet) or rendered elsewhere.
            if measurement.ratio < 1.15 {
                return RuleHelper.validation(ruleID: ruleID, name: title, description: description, node: node,
                                             message: "No text could be seen at this element's position in the screenshot (\(measured)). It may be covered by a bar or overlay, or drawn somewhere else.",
                                             remediation: "Check where this text appears on screen and measure its contrast there.")
            }
            // Within 5% of the threshold the screenshot's compression and
            // anti-aliasing decide the result, not the colours.
            if measurement.ratio >= threshold * 0.95 {
                return RuleHelper.validation(ruleID: ruleID, name: title, description: description, node: node,
                                             message: "The \(basis) is \(measured) (\(sizeText)), just under \(requirement). Measure the exact foreground and background colours.",
                                             remediation: "If the design colours are below \(requirement), darken the text or lighten the background.")
            }
            if let possiblyLargeThreshold, measurement.ratio + 0.001 >= possiblyLargeThreshold {
                return RuleHelper.validation(ruleID: ruleID, name: title, description: description, node: node,
                                             message: "The \(basis) is \(measured) (\(sizeText)). This is below \(requirement) for standard text but meets \(ratioText(possiblyLargeThreshold)), which is enough if the text is bold.",
                                             remediation: "Confirm whether the text is bold. If it is not, increase the contrast to at least \(requirement).")
            }
            let message = "The \(basis) is \(measured) (\(sizeText)), below the required \(requirement)."
            let remediation = "Increase the effective foreground/background contrast to at least \(requirement)\(measurement.variedBackground ? ", for example with a scrim or solid backing behind the text" : "")."
            return RuleHelper.fail(ruleID: ruleID, name: title, description: description, node: node,
                                   message: message, remediation: remediation)
        }
        return RuleHelper.pass(ruleID: ruleID, name: title, description: description, node: node,
                               message: "The \(basis) is \(measured) (\(sizeText)), meeting the required \(requirement).")
    }
}

nonisolated struct ContrastStandardTextRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "contrast-standard-text-4-5"
    let title = "Verify if color contrast for standard text with its background is sufficient"
    let description = "Standard text should meet a minimum 4.5:1 contrast ratio."
    /// Needs the screenshot: the result comes from the contextual evaluation below.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        ContrastRuleFactory.result(node: node, context: context, ruleID: id, title: title, description: description, target: .standard(threshold: 4.5, largeThreshold: 3), background: .flat)
    }
}

nonisolated struct ContrastLargeTextRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "contrast-large-text-3"
    let title = "Verify if color contrast for large text with its background is sufficient"
    let description = "Large text should meet a minimum 3:1 contrast ratio."
    /// Needs the screenshot: the result comes from the contextual evaluation below.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        ContrastRuleFactory.result(node: node, context: context, ruleID: id, title: title, description: description, target: .large(threshold: 3), background: .flat)
    }
}

nonisolated struct ContrastImageBackgroundRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "contrast-text-over-image"
    let title = "Check contrast between text and background image"
    let description = "Text over imagery must maintain sufficient rendered contrast."
    /// Needs the screenshot: the result comes from the contextual evaluation below.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        ContrastRuleFactory.result(node: node, context: context, ruleID: id, title: title, description: description, target: .anySize(standard: 4.5, large: 3), background: .varied)
    }
}

nonisolated struct ContrastOpacityRule: AccessibilityRule, ContextualAccessibilityRule {
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

nonisolated struct TextResizeRule: AccessibilityRule {
    let id = "text-resize"
    let title = "Text can be resized"
    let description = "Text should remain usable when Dynamic Type/accessibility text size is increased."

    /// Runtime-only: the result comes from a device probe (see RuntimeProbes.swift).
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

nonisolated struct LinkRoleRule: AccessibilityRule {
    let id = "text-link-role"
    let title = "Text functions as a link but is missing role link"
    let description = "Link-like text should expose link semantics."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.visible, !node.label.isEmpty else { return nil }
        if node.role == .link {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "Element exposes the link role.")
        }
        guard node.role == .staticText, !node.semantics.insideActionable else { return nil }
        let label = node.label.lowercased()
        let looksLikeURL = label.contains("http://") || label.contains("https://") || label.contains("www.")
        guard looksLikeURL || (RuleHelper.words(node).contains("link") && !RuleHelper.isDescriptiveText(node.label))
        else { return nil }
        // The name itself says it is a link ("…, opens link"), so screen
        // reader users hear it; whether that is acceptable is a judgement.
        if RuleHelper.hasTrait(node, ["clickable"]), RuleHelper.words(node).contains("link") {
            return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                         message: "Tappable text has no link role, but its accessible name says it is a link. Check whether the announcement is clear enough.",
                                         remediation: "Prefer exposing the link role (Role/accessibilityRole link) instead of putting \"link\" in the name.")
        }
        if RuleHelper.hasTrait(node, ["clickable"]) {
            return RuleHelper.warning(ruleID: id, name: title, description: description, node: node,
                                      message: "Tappable text appears link-like but is exposed as static text.",
                                      remediation: "Expose link semantics (Role/accessibilityRole link) for text that navigates somewhere.")
        }
        // Not marked tappable: it may be plain text, or a gesture handler
        // the hierarchy cannot show.
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Text appears link-like but is exposed as static text and is not marked tappable. Check whether activating it navigates somewhere.",
                                     remediation: "If it is a link, expose link semantics and make it focusable; otherwise no change is needed.")
    }
}

nonisolated struct ButtonRoleRule: AccessibilityRule {
    let id = "text-button-role"
    let title = "Text functions as a button but is missing role button"
    let description = "Actionable text should expose button semantics when appropriate."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.visible else { return nil }
        if node.role == .button {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "Element exposes button semantics.")
        }
        guard node.role == .staticText, !node.semantics.insideActionable,
              !RuleHelper.isDescriptiveText(node.label) else { return nil }
        // Whole words, so "Saved" or "Closed" are not read as "save"/"close".
        let words = RuleHelper.words(node)
        let actionWords: Set<String> = ["button", "btn", "submit", "save", "cancel", "continue", "login", "signin", "delete", "close"]
        let isAction = !words.isDisjoint(with: actionWords) || RuleHelper.clean(node.label).lowercased() == "sign in"
        guard isAction else { return nil }
        if RuleHelper.hasTrait(node, ["clickable"]) {
            return RuleHelper.warning(ruleID: id, name: title, description: description, node: node,
                                      message: "Tappable text appears action-oriented but is exposed as static text.",
                                      remediation: "Expose a button role for text that performs an action.")
        }
        return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                     message: "Text appears action-oriented but is exposed as static text and is not marked tappable. Check whether tapping it performs an action.",
                                     remediation: "If it performs an action, expose a button role and make it focusable; otherwise no change is needed.")
    }
}

nonisolated struct DecorativeImageRule: ScreenAccessibilityRule {
    let id = "decorative-image"
    let title = "Check if Image should be marked as decorative"
    let description = "Decorative images should not add redundant screen-reader content."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }

    /// One question per distinct image a screen reader reaches on its own.
    /// Icons inside a button or tab are part of that control's name, and a
    /// repeated icon (rating stars, list bullets) is asked about once.
    func evaluate(rootNode: AccessibilityNode) -> [AccessibilityRuleEvaluation] {
        var seen = Set<String>()
        return RuleHelper.allNodes(rootNode).compactMap { node in
            guard node.role == .image, node.visible, node.accessible,
                  !node.semantics.mergedIntoAncestor, !node.semantics.insideActionable,
                  seen.insert(node.identifier + "|" + RuleHelper.clean(node.label)).inserted
            else { return nil }
            return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                         message: "Screen readers announce this image as \"\(RuleHelper.clean(node.label).isEmpty ? "image" : RuleHelper.clean(node.label))\". Only the design intent decides whether it adds information or is decorative.",
                                         remediation: "If decorative, hide it from assistive technology (.accessibilityHidden(true) / importantForAccessibility=no); otherwise keep a description of what it conveys.")
        }
    }
}

nonisolated struct ScreenReaderHiddenInteractiveRule: AccessibilityRule {
    let id = "interactive-screen-reader-hidden"
    let title = "Check if interactive control needs to be hidden for screen reader user"
    let description = "Interactive controls should not be unintentionally hidden from assistive technology."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        // Inside an accessibility element: the element represents it.
        guard RuleHelper.controls.contains(node.role), node.visible,
              !node.semantics.mergedIntoAncestor else { return nil }
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

nonisolated struct MotionAlternativeRule: AccessibilityRule {
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

nonisolated struct FocusOrderRule: AccessibilityRule {
    let id = "focus-order"
    let title = "Keyboard focus order correct"
    let description = "Runtime accessibility focus should follow a meaningful reading and interaction order."

    // The accessibility tree alone cannot prove the order actually used by
    // VoiceOver/TalkBack. Runtime focus evidence is required; the crawler's
    // keyboard probe supplies a separate keyboard result.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

nonisolated struct OrientationRule: AccessibilityRule {
    let id = "orientation-support"
    let title = "Check if all the content is available when the device orientation is changed"
    let description = "Content should remain available in supported orientations."

    /// Runtime-only: the result comes from a device probe (see RuntimeProbes.swift).
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

nonisolated struct ScreenReaderContentRule: AccessibilityRule {
    let id = "screen-reader-content"
    let title = "Content can be accessed by screen reader user"
    let description = "Meaningful content should be exposed to assistive technology."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.visible, !node.semantics.mergedIntoAncestor else { return nil }
        if node.accessible {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "Element is exposed to assistive technology.")
        }
        // A layout container with no text, image or control inside has no
        // content to expose.
        let hasContent = Self.flatten(node.children).contains {
            $0.visible && (!RuleHelper.clean($0.label).isEmpty || $0.role == .image || RuleHelper.controls.contains($0.role))
        }
        guard hasContent || RuleHelper.isText(node) || RuleHelper.controls.contains(node.role) else { return nil }
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

nonisolated struct LanguageRule: AccessibilityRule {
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

nonisolated struct ModalAccessibilityRule: AccessibilityRule {
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

nonisolated struct LoadingIndicatorContrastRule: AccessibilityRule, ContextualAccessibilityRule {
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


nonisolated struct TimeLimitedUIRule: AccessibilityRule {
    let id = "time-limited-ui"
    let title = "Time-limited UI has a visible user control"
    let description = "Time-limited content should provide a user-controlled extension or equivalent mechanism."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.role == .application else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                     message: "Timing behavior cannot be inferred from one hierarchy snapshot.",
                                     remediation: "Exercise timed UI and verify a visible mechanism to extend or disable the time limit.")
    }
}

nonisolated struct FocusIndicatorRule: AccessibilityRule {
    let id = "focus-indicator"
    let title = "Customized keyboard focus visible"
    let description = "Keyboard focus should have a visible indicator in the rendered UI."

    // Runtime screenshot comparison is performed by KeyboardFocusTester.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

nonisolated struct NonTextContrastRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "non-text-contrast"
    let title = "Non-text element has sufficient contrast with its background"
    let description = "Meaningful non-text UI components should have sufficient contrast."

    private static let measuredRoles: Set<AccessibilityRole> = [
        .button, .toggle, .checkBox, .radioButton, .slider, .stepper, .segmentedControl, .picker
    ]

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }

    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        guard Self.measuredRoles.contains(node.role), node.visible,
              RuleHelper.isWhollyMeasurable(node),
              node.frame.width >= 8, node.frame.height >= 8 else { return nil }
        // A clickable row around a checkbox or radio: the child control is
        // what shows the state, and it is measured itself.
        if node.semantics.roleInferred, RuleHelper.childControl(of: node) != nil { return nil }

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
        // The frame includes touch padding: the outline, thumb or check
        // mark sits inside it. Those parts identify the control.
        if measurement.hasStrongPart {
            let part = String(format: "%.2f:1", measurement.strongPartRatio)
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "Parts of the control (outline, thumb, mark or icon) have a measured contrast of \(part) against the background, meeting 3:1.")
        }

        // A labelled button is identified by its text, so a faint boundary is
        // only a risk. Switches, checkboxes, sliders and similar rely on their
        // shape to show state, so a faint boundary is a failure.
        if node.role == .button {
            return RuleHelper.warning(ruleID: id, name: title, description: description, node: node,
                                      message: "The button's boundary or fill has a measured contrast of \(ratio) against its surroundings, below 3:1. This matters if the shape is needed to recognise it as a control.",
                                      remediation: "Give the control a boundary or fill with at least 3:1 contrast, or make sure a clear text label identifies it.")
        }
        // The measurement covers the whole frame. When the frame also holds
        // the label (a checkbox row) or mostly empty track area (a slider),
        // the low reading may be the background, not the control's glyph,
        // track or thumb.
        let wide = node.frame.width > node.frame.height * 2
        if node.role == .slider || wide || node.semantics.roleInferred {
            return RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                         message: "The control's frame has a measured contrast of \(ratio) against its surroundings, below 3:1, but the frame includes more than the control's \(node.role == .slider ? "track and thumb" : "visual indicator"). Check the indicator itself.",
                                         remediation: "Make sure the parts that identify the control and its state (\(node.role == .slider ? "track and thumb" : "box, circle, switch track or border")) have at least 3:1 contrast.")
        }
        return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                               message: "The control's boundary or fill has a measured contrast of \(ratio) against its surroundings, below the required 3:1.",
                               remediation: "Give the control a boundary, track or fill with at least 3:1 contrast against its background.")
    }
}

nonisolated struct FormBorderContrastRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "form-border-contrast"
    let title = "Border of form controls has sufficient contrast with its background"
    let description = "Visible form-control boundaries should remain distinguishable."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }

    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.textInputs.contains(node.role), node.visible,
              RuleHelper.isWhollyMeasurable(node),
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


nonisolated struct ErrorSuggestionRule: AccessibilityRule {
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

/// Runtime-only: measured by KeyboardFocusTester during Tab traversal.
nonisolated struct FocusIndicatorContrastRule: AccessibilityRule {
    let id = "focus-indicator-contrast"
    let title = "Focus indicator has sufficient contrast"
    let description = "The keyboard focus indicator must have at least 3:1 contrast with adjacent colours."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

/// Runtime-only: checked by KeyboardFocusTester during Tab traversal.
nonisolated struct FocusNotObscuredRule: AccessibilityRule {
    let id = "focus-not-obscured"
    let title = "Check if focus indicator is obscured by another element"
    let description = "A focused control must not be hidden by sticky headers, footers or banners."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

nonisolated struct KeyboardActivationRule: AccessibilityRule {
    let id = "keyboard-activation"
    let title = "Buttons and links are operable with a keyboard"
    let description = "Controls that can be tapped must also be activated from the keyboard."

    /// Runtime-only: see KeyboardProbes.swift.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

nonisolated struct KeyboardHiddenFocusRule: AccessibilityRule {
    let id = "keyboard-focus-hidden-content"
    let title = "Hidden content does not receive keyboard focus"
    let description = "Keyboard focus must not land on hidden or off-screen content."

    /// Runtime-only: reported by the keyboard focus probe.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

nonisolated struct KeyboardNonInteractiveFocusRule: AccessibilityRule {
    let id = "keyboard-focus-noninteractive"
    let title = "Non-interactive elements do not receive keyboard focus"
    let description = "Keyboard focus should only stop on elements the user can act on."

    /// Runtime-only: reported by the keyboard focus probe.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

nonisolated struct MapAlternativeRule: AccessibilityRule {
    let id = "map-text-alternative"
    let title = "Map view has a text alternative"
    let description = "Maps should expose an accessible textual alternative for meaningful locations and controls."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.visible else { return nil }

        // A real map view: iOS XCUIElementTypeMap, Android MapView / Google Maps.
        let isMapView = node.type == "XCUIElementTypeMap" ||
            node.type.hasSuffix("MapView") || node.type.contains(".maps.")
        if isMapView {
            let labelledMarkers = RuleHelper.allNodes(node).dropFirst()
                .filter { $0.accessible && !RuleHelper.clean($0.label).isEmpty }
            if !RuleHelper.clean(node.label).isEmpty || !labelledMarkers.isEmpty {
                return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                       message: "The map exposes text to assistive technology (\(labelledMarkers.count) labelled marker\(labelledMarkers.count == 1 ? "" : "s")\(RuleHelper.clean(node.label).isEmpty ? "" : " and a map label")).")
            }
            return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                                   message: "The map has no accessible label and no labelled markers, so its content is not available as text.",
                                   remediation: "Label the map and its markers, or provide the same information as a list.")
        }

        // Something only named like a map ("Show Map", a map.fill icon) is
        // not a map view: nothing to check.
        return nil
    }
}

/// BB40114. An open dialog offers a way to close it.
nonisolated struct ModalClosableRule: ScreenAccessibilityRule {
    let id = "modal-closable"
    let title = "Modal dialog can be closed"
    let description = "A modal dialog must offer a visible, accessible way to close it."

    private static let closeWords: Set<String> = ["close", "cancel", "dismiss", "done", "ok", "back", "no", "later"]

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }

    func evaluate(rootNode: AccessibilityNode) -> [AccessibilityRuleEvaluation] {
        let modals = RuleHelper.allNodes(rootNode).filter { node in
            guard node.visible else { return false }
            let text = (node.type + " " + node.identifier).lowercased()
            return node.type == "XCUIElementTypeAlert" || node.type == "XCUIElementTypeSheet" ||
                text.contains("dialog") || text.contains("modal") || text.contains("bottomsheet")
        }
        return modals.prefix(1).map { modal in
            let close = RuleHelper.allNodes(modal).first { node in
                RuleHelper.controls.contains(node.role) && node.accessible &&
                !RuleHelper.wordList(node.label + " " + node.identifier).filter { Self.closeWords.contains($0) }.isEmpty
            }
            if let close {
                return RuleHelper.pass(ruleID: id, name: title, description: description, node: modal,
                                       message: "The dialog has an accessible \"\(RuleHelper.clean(close.label))\" control to close it.")
            }
            return RuleHelper.validation(ruleID: id, name: title, description: description, node: modal,
                                         message: "No close, cancel or done control was found in the dialog.",
                                         remediation: "Provide a visible, accessible control that closes the dialog.")
        }
    }
}

nonisolated struct GestureKeyboardRule: AccessibilityRule {
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

nonisolated struct AccessibilityInterfaceOperabilityRule: AccessibilityRule {
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

nonisolated struct TouchPhaseRule: AccessibilityRule {
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

nonisolated struct ComplexGestureRule: AccessibilityRule {
    let id = "complex-gesture-alternative"
    let title = "Alternative for multi-point/path-based gestures present"
    let description = "Complex gestures should have an equivalent accessible operation."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        // Custom accessibility actions are how screen-reader users reach
        // swipe and multi-finger gesture actions.
        if !node.semantics.customActions.isEmpty, node.visible {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "The element exposes custom actions: \(node.semantics.customActions.prefix(4).joined(separator: ", ")).")
        }
        guard node.role == .application else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                     message: "The accessibility hierarchy does not identify multi-point or path-based gestures and cannot prove an equivalent alternative.",
                                     remediation: "Exercise each multi-point or path gesture and verify a single-pointer or simple-control alternative is available unless the gesture is essential.")
    }
}

nonisolated struct MultiPointGestureAlternativeRule: AccessibilityRule {
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

nonisolated struct PathBasedGestureAlternativeRule: AccessibilityRule {
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

nonisolated struct ReadingOrderRule: ScreenAccessibilityRule {
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

nonisolated struct ScreenReaderFocusOrderRule: ScreenAccessibilityRule {
    let id = "screen-reader-focus-order"
    let title = "Screen reader focus order correct"
    let description = "VoiceOver/TalkBack focus should follow a meaningful order."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }

    /// Appium cannot drive VoiceOver/TalkBack focus, so this cannot be
    /// proven automatically. The accessibility tree order, which screen
    /// readers follow by default, is assessed by `reading-order`.
    func evaluate(rootNode: AccessibilityNode) -> [AccessibilityRuleEvaluation] {
        let meaningful = RuleHelper.allNodes(rootNode).filter {
            $0.visible && $0.accessible && !RuleHelper.clean($0.label).isEmpty
        }
        guard meaningful.count >= 2 else { return [] }
        // Not a finding about this screen: a check the scanner cannot run.
        return [RuleHelper.notTested(ruleID: id, name: title, description: description, node: rootNode,
                                      message: "Screen reader focus order cannot be observed through Appium. The accessibility tree order is reported under Reading order.",
                                      remediation: "Swipe through the screen with VoiceOver/TalkBack and confirm focus follows the intended order.")]
    }
}

nonisolated struct ScreenReaderModalFocusRule: AccessibilityRule {
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

nonisolated struct ScreenReaderTrapRule: AccessibilityRule {
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

nonisolated struct ScreenReaderFocusContextChangeRule: AccessibilityRule {
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

nonisolated struct KeyboardFocusContextChangeRule: AccessibilityRule {
    let id = "keyboard-focus-context-change"
    let title = "No context change on focus with external keyboard"
    let description = "Receiving external-keyboard focus should not unexpectedly change context."

    /// Runtime-only: reported by the keyboard focus probe.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

nonisolated struct CancelUndoMechanismRule: AccessibilityRule {
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

nonisolated struct InputContextChangeRule: AccessibilityRule {
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

nonisolated struct KeyboardFocusRule: AccessibilityRule {
    let id = "keyboard-focus"
    let title = "Interactive control can receive keyboard focus"
    let description = "Keyboard users should be able to reach interactive controls where keyboard operation is supported."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

nonisolated struct StateUpdateRule: AccessibilityRule {
    let id = "state-updates-after-interaction"
    let title = "State does not get updated on user interaction"
    let description = "Interactive state should update after user actions."

    /// Runtime-only: the result comes from a device probe (see RuntimeProbes.swift).
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

nonisolated struct LinkColorRule: ScreenAccessibilityRule, ContextualScreenAccessibilityRule {
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

nonisolated struct LanguageChangeRule: AccessibilityRule {
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

nonisolated struct TextSpacingRule: AccessibilityRule {
    let id = "text-spacing"
    let title = "Text spacing requirements met"
    let description = "Content should remain usable with increased text spacing."
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        // One result per screen: the check applies to all text together.
        guard node.role == .application || node.type == "hierarchy" else { return nil }
        guard RuleHelper.allNodes(node).contains(where: { RuleHelper.isText($0) && $0.visible && !$0.label.isEmpty })
        else { return nil }
        return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                     message: "Text spacing requires applying increased spacing styles and rescanning the rendered layout.",
                                     remediation: "Test increased line/paragraph/letter/word spacing and verify no clipping or overlap.")
    }
}

nonisolated struct ModalFocusContainmentRule: AccessibilityRule {
    let id = "modal-focus-containment"
    let title = "Keyboard focus within modals correct"
    let description = "Keyboard focus should remain inside an active modal until dismissal."

    // Runtime keyboard traversal is evaluated by KeyboardFocusTester.
    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }
}

// MARK: - Platform semantics rules
//
// Rules that use data only some platforms expose (PlatformSemantics). They
// return nothing where the data is missing, so a platform that cannot be
// checked is never reported as passing.

/// BB40282. A clickable or checkable generic view (React Native Pressable,
/// Flutter GestureDetector, Compose clickable) with no role.
nonisolated struct MissingRoleRule: AccessibilityRule {
    let id = "missing-role"
    let title = "Missing role for interactive element"
    let description = "Interactive elements must expose a role so assistive technology announces what they are."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard node.visible, node.semantics.roleInferred else { return nil }
        let simpleClass = node.type.split(separator: ".").last.map(String.init) ?? node.type
        // A toggleable Row around a Checkbox or RadioButton: TalkBack reads
        // the child's role and state as part of the row.
        if let child = RuleHelper.childControl(of: node), child.semantics.mergedIntoAncestor {
            let childClass = child.type.split(separator: ".").last.map(String.init) ?? child.type
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "The \(simpleClass) has no role of its own, but it contains a \(childClass) whose role TalkBack announces with it.")
        }
        let expected = node.role == .checkBox ? "checkbox or switch" : "button"
        return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                               message: "This element can be activated but exposes no role (class \(simpleClass)), so TalkBack does not say it is a \(expected).",
                               remediation: "Expose a role: accessibilityRole in React Native, Semantics(button: true) in Flutter, Modifier.semantics { role = Role.Button } in Compose, or use a native \(expected).")
    }
}

/// BB40049. A control whose only name is its hint or tooltip.
nonisolated struct NameViaHintRule: AccessibilityRule {
    let id = "name-via-hint"
    let title = "Accessible name incorrectly specified using hint"
    let description = "A control's purpose must be in its accessible name, not only in its hint."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.isNamedOnlyByHint(node) else { return nil }
        let hint = node.semantics.hint ?? node.semantics.tooltip ?? ""
        return RuleHelper.fail(ruleID: id, name: title, description: description, node: node,
                               message: "The control has no accessible name; its purpose (\"\(RuleHelper.clean(hint))\") is only in the hint, which screen readers announce after a pause or not at all.",
                               remediation: "Put the purpose in the accessible name (contentDescription / accessibilityLabel) and keep the hint for extra guidance only.")
    }
}

/// BB40088, BB40089, BB40121. The accessible name must contain the visible
/// label so voice-control users can say what they see.
nonisolated struct LabelInNameRule: AccessibilityRule, ContextualAccessibilityRule {
    let id = "label-in-name"
    let title = "Accessible name matches visible label"
    let description = "The accessible name of a control with a visible text label must contain that text."

    private static let roles: Set<AccessibilityRole> = [
        .button, .link, .toggle, .checkBox, .radioButton, .segmentedControl
    ]

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        result(node: node, context: nil)
    }

    func evaluate(node: AccessibilityNode, context: AccessibilityRuleContext) -> AccessibilityRuleEvaluation? {
        result(node: node, context: context)
    }

    private func result(node: AccessibilityNode, context: AccessibilityRuleContext?) -> AccessibilityRuleEvaluation? {
        guard Self.roles.contains(node.role), node.visible else { return nil }
        let name = RuleHelper.clean(node.label)
        guard !name.isEmpty else { return nil }

        // Prefer text the platform exposes; fall back to reading the screenshot.
        let visible: String
        let fromScreenshot: Bool
        if let text = node.semantics.visibleText {
            visible = text; fromScreenshot = false
        } else if let segments = RuleHelper.childTextSegments(of: node) {
            // A card shows several texts (tag, title, byline, read time).
            // Its visible label is the title, the longest of them; the name
            // need not repeat badges such as "LIVE" or "NEW".
            visible = segments.count == 1
                ? segments[0]
                : RuleHelper.titleText(of: node) ?? segments[0]
            fromScreenshot = false
        } else if let context, let text = TextRecognizer.text(in: node.frame, context: context) {
            visible = text; fromScreenshot = true
        } else {
            return nil
        }

        let visibleWords = RuleHelper.wordList(visible)
        guard !visibleWords.isEmpty else { return nil }
        let nameWords = Set(RuleHelper.wordList(name))
        let matched = visibleWords.filter { nameWords.contains($0) }.count
        let ratio = Double(matched) / Double(visibleWords.count)
        // Screenshot text can misread a character; allow one miss in longer labels.
        let required = fromScreenshot && visibleWords.count >= 3 ? 0.75 : 1.0

        if ratio >= required {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "The accessible name \"\(name)\" contains the visible label \"\(visible)\".")
        }
        let message = "The accessible name \"\(name)\" does not contain the visible label \"\(visible)\"\(fromScreenshot ? " (read from the screenshot)" : ""). Voice Control users who say the visible label cannot activate it."
        let remediation = "Start the accessible name with the visible label text, or make them match."
        // Text read from the screenshot can be wrong, so it is a warning.
        return fromScreenshot
            ? RuleHelper.warning(ruleID: id, name: title, description: description, node: node, message: message, remediation: remediation)
            : RuleHelper.fail(ruleID: id, name: title, description: description, node: node, message: message, remediation: remediation)
    }
}

/// BB40041. Short, large text that looks like a heading but is not marked as one.
nonisolated struct HeadingCandidateRule: ScreenAccessibilityRule {
    let id = "heading-candidate"
    let title = "Check if the text should be a heading"
    let description = "Text that visually introduces a section should be marked as a heading."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }

    func evaluate(rootNode: AccessibilityNode) -> [AccessibilityRuleEvaluation] {
        let texts = RuleHelper.allNodes(rootNode).filter {
            $0.role == .staticText && $0.visible && !RuleHelper.clean($0.label).isEmpty
        }
        func size(_ node: AccessibilityNode) -> Double? {
            node.semantics.textSizePoints ?? TextSizeEstimate.fontSize(frame: node.frame, text: node.label).map(Double.init)
        }
        let sizes = texts.compactMap(size).sorted()
        guard sizes.count >= 3 else { return [] }
        let median = sizes[sizes.count / 2]

        let candidates = texts.filter { node in
            guard !RuleHelper.hasTrait(node, RuleHelper.headingsTraits),
                  node.semantics.isHeading != true,
                  let points = size(node), points >= max(20, median * 1.3)
            else { return false }
            let label = RuleHelper.clean(node.label)
            // Not headings: emoji and prices (no letters), sentences
            // (Latin or CJK punctuation), and text inside a button or card,
            // which is that control's name.
            guard !node.semantics.insideActionable,
                  label.unicodeScalars.contains(where: { $0.properties.isAlphabetic }),
                  !label.contains(where: { "。，、！？；：".contains($0) })
            else { return false }
            return label.count <= 60 && RuleHelper.wordList(label).count <= 8 && !label.hasSuffix(".")
        }

        return candidates.prefix(5).map { node in
            RuleHelper.validation(ruleID: id, name: title, description: description, node: node,
                                  message: "\"\(RuleHelper.clean(node.label))\" is larger than the surrounding text and looks like a heading, but is not marked as one.",
                                  remediation: "If the text introduces a section, mark it as a heading (accessibilityTraits .header, accessibilityHeading, accessibilityRole=\"header\", Semantics(header: true)).")
        }
    }
}

/// BB40095. Android: an error shown next to a field that TalkBack is not told about.
nonisolated struct ErrorExposureRule: ScreenAccessibilityRule {
    let id = "error-message-accessibility"
    let title = "Error message is announced to screen reader users"
    let description = "Validation errors should be identified in text and exposed to assistive technology."

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? { nil }

    func evaluate(rootNode: AccessibilityNode) -> [AccessibilityRuleEvaluation] {
        // iOS exposes neither field errors nor live regions to Appium.
        guard rootNode.platform == .android else { return [] }
        let nodes = RuleHelper.allNodes(rootNode).filter(\.visible)
        let inputs = nodes.filter { RuleHelper.textInputs.contains($0.role) }
        guard !inputs.isEmpty else { return [] }

        var results: [AccessibilityRuleEvaluation] = []
        for input in inputs where input.semantics.errorText != nil || input.semantics.contentInvalid == true {
            results.append(RuleHelper.pass(ruleID: id, name: title, description: description, node: input,
                                           message: "The field exposes its error to TalkBack\(input.semantics.errorText.map { ": \"\($0)\"" } ?? ".")"))
        }

        let errorTexts = nodes.filter { node in
            node.role == .staticText &&
            ErrorMessageHeuristics.looksLikeStrictError(node.label) &&
            (node.semantics.liveRegion ?? 0) == 0
        }
        for text in errorTexts {
            guard let field = inputs.first(where: { RuleHelper.isBelowOrBeside(text, $0) }),
                  field.semantics.errorText == nil, field.semantics.contentInvalid != true
            else { continue }
            results.append(RuleHelper.warning(ruleID: id, name: title, description: description, node: text,
                                              message: "The error \"\(RuleHelper.clean(text.label))\" is shown next to a field, but the field is not marked invalid and the text is not a live region, so TalkBack does not announce it.",
                                              remediation: "Set the error on the field (setError / TextInputLayout.setError) or make the message a live region so it is announced."))
        }
        return results
    }
}

/// BB40103, BB40104. Android: status content that changes should be a live region.
nonisolated struct StatusLiveRegionRule: AccessibilityRule {
    let id = "live-region"
    let title = "Live region is defined for dynamic content"
    let description = "Dynamic updates that require announcement should expose appropriate accessibility notifications."

    private static let statusCues = ["snackbar", "toast", "status", "banner", "notice"]

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        if node.role == .application {
            guard node.platform == .ios else { return nil }
            return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                        message: "Screen-reader announcements for dynamic updates cannot be observed through Appium on iOS.",
                                        remediation: "Trigger the update with VoiceOver on and confirm it is announced.")
        }
        guard node.platform == .android, node.visible, let liveRegion = node.semantics.liveRegion else { return nil }
        let text = (node.type + " " + node.identifier).lowercased()
        guard Self.statusCues.contains(where: { text.contains($0) }) else { return nil }
        if liveRegion > 0 {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "Status content is a \(liveRegion == 2 ? "assertive" : "polite") live region, so TalkBack announces updates.")
        }
        return RuleHelper.warning(ruleID: id, name: title, description: description, node: node,
                                  message: "This looks like status content (\(node.identifier.isEmpty ? node.type : node.identifier)) but is not a live region, so TalkBack may not announce updates.",
                                  remediation: "Set accessibilityLiveRegion (polite) on the view, or announce the change.")
    }
}

/// BB40091, BB40092. Android: a personal-data field's input type should say
/// what it collects. Autofill hints are not in the hierarchy, so the input
/// type is the evidence available.
nonisolated struct InputPurposeRule: AccessibilityRule {
    let id = "form-autocomplete"
    let title = "Autocomplete information is specified for form field"
    let description = "Form fields should expose appropriate autocomplete semantics where applicable."

    private enum Purpose: String {
        case email, phone, password, name, postalCode = "postal code", address
    }

    func evaluate(node: AccessibilityNode) -> AccessibilityRuleEvaluation? {
        guard RuleHelper.textInputs.contains(node.role), node.visible else { return nil }

        guard node.platform == .android, let inputType = node.semantics.inputType else {
            return RuleHelper.notTested(ruleID: id, name: title, description: description, node: node,
                                        message: "Autocomplete/content-type metadata is not exposed through Appium on this platform, so it could not be checked.",
                                        remediation: "Verify the field has the correct autocomplete/content-type semantics.")
        }
        guard let purpose = purpose(of: node) else { return nil }

        let typeClass = inputType & 0xF
        let variation = inputType & 0xFF0
        let matches: Bool
        switch purpose {
        case .email: matches = typeClass == 1 && [0x20, 0xD0].contains(variation)
        case .phone: matches = typeClass == 3
        case .password: matches = (typeClass == 1 && [0x80, 0x90, 0xE0].contains(variation)) || (typeClass == 2 && variation == 0x10)
        case .name: matches = typeClass == 1 && variation == 0x60
        case .postalCode: matches = typeClass == 2 || (typeClass == 1 && variation == 0x70)
        case .address: matches = typeClass == 1 && variation == 0x70
        }

        if matches {
            return RuleHelper.pass(ruleID: id, name: title, description: description, node: node,
                                   message: "The \(purpose.rawValue) field declares a matching input type.")
        }
        return RuleHelper.warning(ruleID: id, name: title, description: description, node: node,
                                  message: "The field collects a \(purpose.rawValue) but its input type does not say so, so autofill and assistive features cannot identify it.",
                                  remediation: "Set the matching inputType and autofillHints (textContentType / autoComplete in React Native, autofillHints in Flutter).")
    }

    private func purpose(of node: AccessibilityNode) -> Purpose? {
        let text = [node.label, node.placeholderValue ?? "", node.identifier]
            .joined(separator: " ")
            .lowercased()
        if text.contains("email") || text.contains("e-mail") { return .email }
        if text.contains("password") || text.contains("passcode") { return .password }
        if ["phone", "mobile", "telephone"].contains(where: text.contains) { return .phone }
        if ["postcode", "postal code", "zip", "pincode", "pin code"].contains(where: text.contains) { return .postalCode }
        if ["first name", "last name", "full name", "surname", "given name", "family name"].contains(where: text.contains) { return .name }
        if text.contains("address") || text.contains("street") { return .address }
        return nil
    }
}
