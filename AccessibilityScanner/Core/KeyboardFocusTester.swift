import Foundation
import CoreGraphics
import AppKit

final class KeyboardFocusTester {

    struct Result {
        let evaluations: [AccessibilityRuleEvaluation]
        let focusedSequence: [String]
        let reachedControlCount: Int
        let requiredControlCount: Int
        let evidenceAvailable: Bool
        /// Controls keyboard focus reached, in the order it reached them.
        var reachedNodes: [AccessibilityNode] = []
    }

    private let appium: AppiumClient
    private let maxAdditionalTabs: Int
    private let settleMilliseconds: UInt64

    /// Tabs to try before concluding the session does not expose keyboard
    /// focus at all. Each Tab costs a full hierarchy fetch.
    private let tabsBeforeGivingUp = 3

    init(
        appium: AppiumClient,
        maxAdditionalTabs: Int = 24,
        settleMilliseconds: UInt64 = 60
    ) {
        self.appium = appium
        self.maxAdditionalTabs = maxAdditionalTabs
        self.settleMilliseconds = settleMilliseconds
    }

    func unavailableEvaluation(rootNode: AccessibilityNode, error: Error) -> AccessibilityRuleEvaluation {
        baseEvaluation(
            ruleID: "keyboard-focus",
            name: "Interactive elements focusable using a keyboard interface",
            description: "Interactive controls should be reachable through the supported keyboard focus mechanism.",
            node: rootNode,
            status: .notTested,
            severity: .warning,
            message: "Keyboard focus could not be tested because the runtime keyboard capability was unavailable.",
            remediation: "Verify that the Appium session exposes keyboard actions and focused state, then rerun the scan."
        )
    }

    func test(rootNode: AccessibilityNode) async throws -> Result {
        if appium.platform == .ios {
            return Result(
                evaluations: [baseEvaluation(
                    ruleID: "keyboard-focus",
                    name: "Interactive elements focusable using a keyboard interface",
                    description: "Interactive controls should be reachable through the supported keyboard focus mechanism.",
                    node: rootNode,
                    status: .notTested,
                    severity: .warning,
                    message: "Keyboard focus cannot be tested on iOS through Appium: WebDriverAgent does not report Full Keyboard Access focus.",
                    remediation: "Connect a keyboard, turn on Full Keyboard Access, and Tab through the screen to confirm every control is reachable, visibly focused and operable."
                )],
                focusedSequence: [],
                reachedControlCount: 0,
                requiredControlCount: 0,
                evidenceAvailable: false
            )
        }
        let activeModal = modalNode(in: rootNode)
        let controlsRoot = activeModal ?? rootNode
        let controls = interactiveControls(in: controlsRoot)
        guard !controls.isEmpty else {
            // An open modal with nothing to focus traps keyboard users: they
            // cannot reach a close button.
            let evaluations = activeModal.map { modal in
                [ProbeEvaluation.make(
                    ruleID: "modal-focus-containment",
                    status: .fail,
                    message: "The modal has no keyboard-focusable interactive controls, so keyboard users cannot act on it or close it.",
                    remediation: "Make the modal's buttons, including a close or dismiss control, keyboard focusable.",
                    node: modal
                )]
            } ?? []
            return Result(evaluations: evaluations, focusedSequence: [], reachedControlCount: 0, requiredControlCount: 0, evidenceAvailable: true)
        }

        var reachedKeys = Set<String>()
        var sequence: [String] = []
        var seenFocusedKeys = Set<String>()
        var observedFocusedElement = false
        var trapDetected = false
        var visualEvidence: [String: Bool] = [:]
        var indicatorContrast: [String: (node: AccessibilityNode, ratio: Double)] = [:]
        var obscuredBy: [String: (node: AccessibilityNode, cover: AccessibilityNode)] = [:]
        var traversalCompleted = false
        var hiddenFocused: [String: AccessibilityNode] = [:]
        var nonInteractiveFocused: [String: AccessibilityNode] = [:]
        let baselineLabels = ProbeNodes.contentLabels(in: rootNode)
        var contextChanged = false
        var stepsObserved = 0

        let maxTabs = min(maxAdditionalTabs, max(1, controls.count + 2))
        let baselineScreenshot = try? await appium.getScreenshot()

        for tabIndex in 0..<maxTabs {
            try Task.checkCancellation()
            if !observedFocusedElement && hiddenFocused.isEmpty && tabIndex >= tabsBeforeGivingUp {
                break
            }
            try await appium.pressTab()

            if settleMilliseconds > 0 {
                try await Task.sleep(for: .milliseconds(settleMilliseconds))
            }

            let source = try await appium.getSource()
            let root = try appium.makeParser().parse(source)

            // Focus that lands on hidden content is reported even though the
            // visible-focus lookup below ignores it.
            if let anyFocused = anyFocusedNode(in: root), !(anyFocused.visible && anyFocused.accessible) {
                hiddenFocused[stableKey(for: anyFocused)] = anyFocused
            }

            // Focus alone must not navigate away or rebuild the screen.
            if !baselineLabels.isEmpty {
                let currentLabels = ProbeNodes.contentLabels(in: root)
                let missing = Double(baselineLabels.subtracting(currentLabels).count) / Double(baselineLabels.count)
                if missing > 0.6 {
                    contextChanged = true
                    try? await appium.goBack()
                    break
                }
            }

            guard let focused = firstFocusedNode(in: root) else {
                continue
            }

            stepsObserved += 1
            if !(focused.isInteractive || focused.isKeyboardFocusable) {
                nonInteractiveFocused[stableKey(for: focused)] = focused
            }

            observedFocusedElement = true
            let key = stableKey(for: focused)
            let isNewFocus = seenFocusedKeys.insert(key).inserted

            if sequence.last != key {
                sequence.append(key)
            }

            if let matching = controls.first(where: { stableKey(for: $0) == key }) {
                reachedKeys.insert(stableKey(for: matching))

                if isNewFocus, let baselineScreenshot {
                    let focusedScreenshot = try? await appium.getScreenshot()
                    visualEvidence[key] = focusRegionChanged(
                        before: baselineScreenshot,
                        after: focusedScreenshot,
                        node: matching,
                        hierarchySize: rootNode.frame.size
                    )
                    if visualEvidence[key] == true,
                       let ratio = indicatorContrastRatio(
                        before: baselineScreenshot,
                        after: focusedScreenshot,
                        node: matching,
                        hierarchySize: rootNode.frame.size
                       ) {
                        indicatorContrast[key] = (matching, ratio)
                    }
                }
                if isNewFocus, let cover = coveringElement(over: focused, in: root) {
                    obscuredBy[key] = (matching, cover)
                }
            }

            if !isNewFocus && reachedKeys.count < controls.count {
                trapDetected = true
                break
            }

            if reachedKeys.count == controls.count {
                traversalCompleted = true
                break
            }
        }

        guard observedFocusedElement else {
            return Result(
                evaluations: [
                    baseEvaluation(
                        ruleID: "keyboard-focus",
                        name: "Interactive elements focusable using a keyboard interface",
                        description: "Interactive controls should be reachable through the supported keyboard focus mechanism.",
                        node: rootNode,
                        status: .notTested,
                        severity: .warning,
                        message: "The scanner could not observe a focused element after keyboard navigation.",
                        remediation: "Verify keyboard navigation is enabled on the device and that Appium exposes the focused/focusable state for this platform."
                    ),
                    baseEvaluation(
                        ruleID: "focus-indicator",
                        name: "Customized keyboard focus visible",
                        description: "Keyboard focus must have a visible indication in the rendered UI.",
                        node: rootNode,
                        status: .notTested,
                        severity: .warning,
                        message: "Focus-visible evidence was unavailable because the runtime session did not expose a focused element.",
                        remediation: "Run the scan with keyboard navigation enabled and verify the rendered focus indicator."
                    )
                ],
                focusedSequence: sequence,
                reachedControlCount: 0,
                requiredControlCount: controls.count,
                evidenceAvailable: false
            )
        }

        var evaluations: [AccessibilityRuleEvaluation] = []

        // 1. Interactive elements focusable using a keyboard interface.
        for control in controls {
            let key = stableKey(for: control)
            if reachedKeys.contains(key) {
                evaluations.append(baseEvaluation(
                    ruleID: "keyboard-focus",
                    name: "Interactive elements focusable using a keyboard interface",
                    description: "Interactive controls should be reachable through the supported keyboard focus mechanism.",
                    node: control,
                    status: .pass,
                    severity: .info,
                    message: "Keyboard focus reached this interactive element during runtime Tab navigation.",
                    remediation: ""
                ))
            } else if trapDetected {
                evaluations.append(baseEvaluation(
                    ruleID: "keyboard-focus",
                    name: "Interactive elements focusable using a keyboard interface",
                    description: "Interactive controls should be reachable through the supported keyboard focus mechanism.",
                    node: control,
                    status: .fail,
                    severity: .error,
                    message: "Keyboard focus became trapped before this interactive element was reached.",
                    remediation: "Make the control keyboard focusable and ensure keyboard focus can reach it without becoming trapped."
                ))
            } else {
                evaluations.append(baseEvaluation(
                    ruleID: "keyboard-focus",
                    name: "Interactive elements focusable using a keyboard interface",
                    description: "Interactive controls should be reachable through the supported keyboard focus mechanism.",
                    node: control,
                    status: .notTested,
                    severity: .warning,
                    message: "Keyboard focus did not reach this control before the runtime probe limit, so a failure cannot be proven.",
                    remediation: "Rerun with keyboard navigation enabled or increase the runtime focus probe limit before treating this control as a defect."
                ))
            }
        }

        if trapDetected {
            evaluations.append(baseEvaluation(
                ruleID: "modal-accessibility",
                name: "No keyboard trap present",
                description: "Keyboard focus must be able to move away from a focused component.",
                node: rootNode,
                status: .fail,
                severity: .error,
                message: "Keyboard focus repeated before all reachable interactive elements were visited, indicating a possible keyboard trap.",
                remediation: "Verify that keyboard focus can leave the component using standard keyboard navigation or an exposed exit mechanism."
            ))
        } else if traversalCompleted {
            evaluations.append(baseEvaluation(
                ruleID: "modal-accessibility",
                name: "No keyboard trap present",
                description: "Keyboard focus must be able to move away from a focused component.",
                node: rootNode,
                status: .pass,
                severity: .info,
                message: "All controls in the active keyboard-focus scope were reached without a focus cycle.",
                remediation: ""
            ))
        } else {
            evaluations.append(baseEvaluation(
                ruleID: "modal-accessibility",
                name: "No keyboard trap present",
                description: "Keyboard focus must be able to move away from a focused component.",
                node: rootNode,
                status: .notTested,
                severity: .warning,
                message: "The keyboard probe ended before it could prove that focus was not trapped.",
                remediation: "Rerun the scan with a sufficient keyboard traversal limit and verify focus can leave the component or modal."
            ))
        }

        // 3. Focus-visible requires rendered evidence. Do not infer it from
        // the focused attribute alone.
        let reachedControls = controls.filter { reachedKeys.contains(stableKey(for: $0)) }
        if visualEvidence.count == reachedControls.count && !visualEvidence.isEmpty {
            for control in reachedControls {
                let visible = visualEvidence[stableKey(for: control)] ?? false
                evaluations.append(baseEvaluation(
                    ruleID: "focus-indicator",
                    name: "Customized keyboard focus visible",
                    description: "Keyboard focus must have a visible indication in the rendered UI.",
                    node: control,
                    status: visible ? .pass : .fail,
                    severity: visible ? .info : .error,
                    message: visible
                        ? "A rendered visual change was detected around the focused control."
                        : "Keyboard focus changed in the accessibility hierarchy, but no rendered visual change was detected around the focused control.",
                    remediation: visible ? "" : "Provide a persistent, clearly visible focus indicator for keyboard focus."
                ))
            }
        } else if !reachedControls.isEmpty {
            evaluations.append(baseEvaluation(
                ruleID: "focus-indicator",
                name: "Customized keyboard focus visible",
                description: "Keyboard focus must have a visible indication in the rendered UI.",
                node: reachedControls.first ?? rootNode,
                status: .notTested,
                severity: .warning,
                message: "Rendered focus evidence was incomplete, so focus visibility was not classified as a failure.",
                remediation: "Rerun the runtime focus probe with screenshot capture available for each reached control."
            ))
        }
        for (node, ratio) in indicatorContrast.values {
            let text = String(format: "%.2f:1", ratio)
            evaluations.append(ProbeEvaluation.make(
                ruleID: "focus-indicator-contrast",
                status: ratio >= 3 ? .pass : .fail,
                message: ratio >= 3
                    ? "The focus indicator contrasts \(text) with the colours it replaces."
                    : "The focus indicator contrasts only \(text) with the colours it replaces; at least 3:1 is required.",
                remediation: ratio >= 3 ? "" : "Make the focus indicator at least 3:1 against adjacent colours, for example a thicker or darker outline.",
                node: node
            ))
        }
        for (node, cover) in obscuredBy.values {
            let coverName = cover.label.isEmpty ? (cover.identifier.isEmpty ? cover.type : cover.identifier) : cover.label
            evaluations.append(ProbeEvaluation.make(
                ruleID: "focus-not-obscured",
                status: .validate,
                message: "When focused, this control lies under \"\(coverName)\", which may hide it from keyboard users.",
                remediation: "Scroll focused controls clear of sticky headers, footers and banners.",
                node: node
            ))
        }

        let expectedKeys = controls.map(stableKey(for:))
        let observedControlKeys = sequence.filter { expectedKeys.contains($0) }
        let orderTitle = "Screen reader/keyboard focus order correct"
        let orderDescription = "Focus should traverse meaningful interactive elements in an intended order."
        if reachedKeys.count == controls.count && observedControlKeys == expectedKeys {
            evaluations.append(baseEvaluation(
                ruleID: "focus-order",
                name: orderTitle,
                description: orderDescription,
                node: rootNode,
                status: .pass,
                severity: .info,
                message: "Runtime keyboard focus traversed all interactive controls in the accessibility-tree order.",
                remediation: ""
            ))
        } else {
            // Compare the order focus really moved in with the visual reading order.
            let observedFrames = observedControlKeys.compactMap { key in
                controls.first { stableKey(for: $0) == key }?.frame
            }
            if let assessment = VisualOrder.assess(frames: observedFrames) {
                if assessment.ratio >= VisualOrder.passThreshold {
                    evaluations.append(baseEvaluation(
                        ruleID: "focus-order",
                        name: orderTitle,
                        description: orderDescription,
                        node: rootNode,
                        status: .pass,
                        severity: .info,
                        message: "Runtime keyboard focus moved through \(assessment.count) controls in visual reading order.",
                        remediation: ""
                    ))
                } else {
                    evaluations.append(baseEvaluation(
                        ruleID: "focus-order",
                        name: orderTitle,
                        description: orderDescription,
                        node: rootNode,
                        status: .warning,
                        severity: .warning,
                        message: "Runtime keyboard focus visited \(assessment.outOfOrder) of \(assessment.count) controls out of visual reading order.",
                        remediation: "Make keyboard focus follow a meaningful order, normally the visual reading order."
                    ))
                }
            }
        }

        // 4b. Hidden / non-interactive content receiving focus, and context
        // changes caused by focus alone.
        for node in hiddenFocused.values {
            evaluations.append(ProbeEvaluation.make(
                ruleID: "keyboard-focus-hidden-content",
                status: .fail,
                message: "Keyboard focus landed on hidden or non-accessible content.",
                remediation: "Remove hidden content from the keyboard focus order.",
                node: node
            ))
        }
        for node in nonInteractiveFocused.values {
            evaluations.append(ProbeEvaluation.make(
                ruleID: "keyboard-focus-noninteractive",
                status: .warning,
                message: "Keyboard focus stopped on a non-interactive element.",
                remediation: "Only make elements keyboard focusable when the user can act on them.",
                node: node
            ))
        }
        if hiddenFocused.isEmpty {
            evaluations.append(ProbeEvaluation.make(
                ruleID: "keyboard-focus-hidden-content",
                status: .pass,
                message: "Keyboard focus never landed on hidden content during traversal.",
                node: rootNode
            ))
        }
        if nonInteractiveFocused.isEmpty && stepsObserved > 0 {
            evaluations.append(ProbeEvaluation.make(
                ruleID: "keyboard-focus-noninteractive",
                status: .pass,
                message: "Keyboard focus only stopped on interactive elements during traversal.",
                node: rootNode
            ))
        }
        if contextChanged {
            evaluations.append(ProbeEvaluation.make(
                ruleID: "keyboard-focus-context-change",
                status: .fail,
                message: "Moving keyboard focus changed the screen content without any activation.",
                remediation: "Do not navigate or rebuild the screen when an element only receives focus.",
                node: rootNode
            ))
        } else if stepsObserved >= 2 {
            evaluations.append(ProbeEvaluation.make(
                ruleID: "keyboard-focus-context-change",
                status: .pass,
                message: "Moving keyboard focus through \(stepsObserved) elements did not change the screen content.",
                node: rootNode
            ))
        }

        // 5. If a modal/dialog is exposed in the current hierarchy, prove that
        // keyboard focus does not escape its bounds while it is present.
        if let modal = modalNode(in: rootNode) {
            let focusedNodes = sequence.compactMap { key in
                controls.first { stableKey(for: $0) == key }
            }
            let outside = focusedNodes.first { !modal.frame.contains($0.frame.center) }
            evaluations.append(baseEvaluation(
                ruleID: "modal-focus-containment",
                name: "Keyboard focus within modals correct",
                description: "When a modal is active, keyboard focus should remain within it until dismissal.",
                node: modal,
                status: outside == nil ? .pass : .fail,
                severity: outside == nil ? .info : .error,
                message: outside == nil
                    ? "All observed keyboard focus remained within the detected modal bounds."
                    : "Keyboard focus moved outside the detected modal while it was active.",
                remediation: outside == nil ? "" : "Contain keyboard focus within the modal until it is dismissed, then restore focus appropriately."
            ))
        }

        return Result(
            evaluations: evaluations,
            focusedSequence: sequence,
            reachedControlCount: reachedKeys.count,
            requiredControlCount: controls.count,
            evidenceAvailable: true,
            reachedNodes: sequence.compactMap { key in
                controls.first { stableKey(for: $0) == key }
            }
        )
    }

    private func interactiveControls(in root: AccessibilityNode) -> [AccessibilityNode] {
        var result: [AccessibilityNode] = []
        var seen = Set<String>()

        func walk(_ node: AccessibilityNode) {
            if node.visible && node.enabled && node.exists && (node.isInteractive || node.isKeyboardFocusable) {
                let key = stableKey(for: node)
                if seen.insert(key).inserted { result.append(node) }
            }
            for child in node.children { walk(child) }
        }
        walk(root)
        return result
    }

    private func firstFocusedNode(in root: AccessibilityNode) -> AccessibilityNode? {
        if root.focused && root.visible && root.exists { return root }
        for child in root.children {
            if let focused = firstFocusedNode(in: child) { return focused }
        }
        return nil
    }

    /// Like `firstFocusedNode` but also finds focus on hidden elements.
    private func anyFocusedNode(in root: AccessibilityNode) -> AccessibilityNode? {
        if root.focused && root.exists { return root }
        for child in root.children {
            if let focused = anyFocusedNode(in: child) { return focused }
        }
        return nil
    }

    private func modalNode(in root: AccessibilityNode) -> AccessibilityNode? {
        var candidate: AccessibilityNode?
        func walk(_ node: AccessibilityNode) {
            let text = (node.type + " " + node.identifier + " " + node.label).lowercased()
            if text.contains("dialog") || text.contains("modal") || node.role.rawValue == "dialog" {
                candidate = node
                return
            }
            for child in node.children where candidate == nil { walk(child) }
        }
        walk(root)
        return candidate
    }

    private func stableKey(for node: AccessibilityNode) -> String {
        let identifier = node.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = node.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let frame = "\(Int(node.frame.origin.x.rounded())):\(Int(node.frame.origin.y.rounded())):\(Int(node.frame.width.rounded())):\(Int(node.frame.height.rounded()))"
        return [node.type, identifier, label, frame].joined(separator: "|")
    }

    /// Contrast between the focus indicator and what it replaced: the median
    /// colour of changed pixels after focus against the same pixels before.
    private func indicatorContrastRatio(before: Data, after: Data?, node: AccessibilityNode, hierarchySize: CGSize) -> Double? {
        guard let after, let beforeImage = NSImage(data: before), let afterImage = NSImage(data: after),
              let beforeCG = beforeImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let afterCG = afterImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let width = min(beforeCG.width, afterCG.width)
        let height = min(beforeCG.height, afterCG.height)
        let scaleX = CGFloat(width) / max(1, hierarchySize.width)
        let scaleY = CGFloat(height) / max(1, hierarchySize.height)
        let x = max(0, Int((node.frame.minX - 6) * scaleX))
        let y = max(0, Int((node.frame.minY - 6) * scaleY))
        let w = min(width - x, max(1, Int((node.frame.width + 12) * scaleX)))
        let h = min(height - y, max(1, Int((node.frame.height + 12) * scaleY)))
        guard w > 1, h > 1,
              let beforePixels = pixelBytes(beforeCG, x: x, y: y, width: w, height: h),
              let afterPixels = pixelBytes(afterCG, x: x, y: y, width: w, height: h),
              beforePixels.count == afterPixels.count else { return nil }

        func luminance(_ p: [UInt8], _ i: Int) -> Double {
            func channel(_ v: UInt8) -> Double {
                let c = Double(v) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(p[i]) + 0.7152 * channel(p[i + 1]) + 0.0722 * channel(p[i + 2])
        }

        var afterL: [Double] = []
        var beforeL: [Double] = []
        for i in Swift.stride(from: 0, to: beforePixels.count - 3, by: 4) {
            let distance = abs(Int(beforePixels[i]) - Int(afterPixels[i]))
                + abs(Int(beforePixels[i + 1]) - Int(afterPixels[i + 1]))
                + abs(Int(beforePixels[i + 2]) - Int(afterPixels[i + 2]))
            if distance > 60 {
                afterL.append(luminance(afterPixels, i))
                beforeL.append(luminance(beforePixels, i))
            }
        }
        guard afterL.count >= 20 else { return nil }
        let a = afterL.sorted()[afterL.count / 2]
        let b = beforeL.sorted()[beforeL.count / 2]
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// A sticky bar (navigation bar, tab bar, toolbar) drawn over most of the
    /// focused control.
    private func coveringElement(over focused: AccessibilityNode, in root: AccessibilityNode) -> AccessibilityNode? {
        let barRoles: Set<AccessibilityRole> = [.navigationBar, .tabBar]
        var result: AccessibilityNode?
        func walk(_ node: AccessibilityNode) {
            guard result == nil else { return }
            if node.visible, barRoles.contains(node.role) {
                let overlap = node.frame.intersection(focused.frame)
                let area = max(1, focused.frame.width * focused.frame.height)
                // Not the control's own bar: the control is not inside it.
                let isInside = node.frame.contains(focused.frame)
                if !overlap.isNull, !isInside, overlap.width * overlap.height / area > 0.3 {
                    result = node
                    return
                }
            }
            node.children.forEach(walk)
        }
        walk(root)
        return result
    }

    private func focusRegionChanged(before: Data, after: Data?, node: AccessibilityNode, hierarchySize: CGSize) -> Bool {
        guard let after, let beforeImage = NSImage(data: before), let afterImage = NSImage(data: after),
              let beforeCG = beforeImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let afterCG = afterImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }

        let width = min(beforeCG.width, afterCG.width)
        let height = min(beforeCG.height, afterCG.height)
        guard width > 0, height > 0 else { return false }

        let scaleX = CGFloat(width) / max(1, hierarchySize.width)
        let scaleY = CGFloat(height) / max(1, hierarchySize.height)
        let x = max(0, Int((node.frame.minX - 6) * scaleX))
        let yFromTop = max(0, Int((node.frame.minY - 6) * scaleY))
        let w = min(width - x, max(1, Int((node.frame.width + 12) * scaleX)))
        let h = min(height - yFromTop, max(1, Int((node.frame.height + 12) * scaleY)))
        guard w > 1, h > 1 else { return false }

        let beforePixels = pixelBytes(beforeCG, x: x, y: yFromTop, width: w, height: h)
        let afterPixels = pixelBytes(afterCG, x: x, y: yFromTop, width: w, height: h)
        guard let beforePixels, let afterPixels, beforePixels.count == afterPixels.count else { return false }

        var changed = 0
        let stride = 4
        for i in Swift.stride(from: 0, to: beforePixels.count, by: stride * 3) {
            let distance = abs(Int(beforePixels[i]) - Int(afterPixels[i]))
                + abs(Int(beforePixels[i + 1]) - Int(afterPixels[i + 1]))
                + abs(Int(beforePixels[i + 2]) - Int(afterPixels[i + 2]))
            if distance > 24 { changed += 1 }
        }

        let samples = max(1, beforePixels.count / (stride * 3))
        return Double(changed) / Double(samples) >= 0.002
    }

    private func pixelBytes(
        _ image: CGImage,
        x: Int,
        y: Int,
        width: Int,
        height: Int
    ) -> [UInt8]? {
        guard let provider = image.dataProvider,
              let data = provider.data else {
            return nil
        }

        guard let base = CFDataGetBytePtr(data) else {
            return nil
        }

        let bytesPerRow = image.bytesPerRow
        let bytesPerPixel = 4
        let rowByteCount = width * bytesPerPixel

        var result = [UInt8](
            repeating: 0,
            count: width * height * bytesPerPixel
        )

        for row in 0..<height {
            let srcOffset =
                (y + row) * bytesPerRow +
                x * bytesPerPixel

            let dstOffset =
                row * rowByteCount

            for i in 0..<rowByteCount {
                result[dstOffset + i] = base[srcOffset + i]
            }
        }
        return result
    }

    private func baseEvaluation(
        ruleID: String,
        name: String,
        description: String,
        node: AccessibilityNode,
        status: RuleResultStatus,
        severity: AccessibilityFinding.Severity,
        message: String,
        remediation: String
    ) -> AccessibilityRuleEvaluation {
        AccessibilityRuleEvaluation(
            ruleID: ruleID,
            ruleName: name,
            ruleDescription: description,
            status: status,
            severity: severity,
            message: message,
            remediation: remediation,
            node: node
        )
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
