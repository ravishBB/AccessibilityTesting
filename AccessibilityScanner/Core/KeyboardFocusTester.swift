import Foundation
import CoreGraphics

/// Runtime keyboard-focus probe for Appium sessions.
///
/// This is intentionally separate from the static KeyboardFocusRule. The rule
/// catalog still owns the rule ID, while this tester supplies the evidence that
/// a static accessibility hierarchy cannot prove by itself.
final class KeyboardFocusTester {

    struct Result {
        let evaluations: [AccessibilityRuleEvaluation]
        let focusedSequence: [String]
        let reachedControlCount: Int
        let requiredControlCount: Int
        let evidenceAvailable: Bool
    }

    private let appium: AppiumClient
    private let maxAdditionalTabs: Int

    init(appium: AppiumClient, maxAdditionalTabs: Int = 80) {
        self.appium = appium
        self.maxAdditionalTabs = maxAdditionalTabs
    }

    func unavailableEvaluation(rootNode: AccessibilityNode, error: Error) -> AccessibilityRuleEvaluation {
        validationEvaluation(
            node: rootNode,
            message: "Keyboard focus test could not be executed: \(error.localizedDescription)",
            remediation: "Verify the Appium session accepts W3C keyboard actions and rerun the scan."
        )
    }

    func test(rootNode: AccessibilityNode) async throws -> Result {
        let controls = interactiveControls(in: rootNode)

        guard !controls.isEmpty else {
            return Result(
                evaluations: [],
                focusedSequence: [],
                reachedControlCount: 0,
                requiredControlCount: 0,
                evidenceAvailable: true
            )
        }

        // WDA exposes XCTest's hasFocus value as the `focused` element
        // attribute. The screen does not necessarily start with a focused
        // control, so the probe intentionally sends the first Tab before
        // deciding whether focus evidence is available.
        var reachedKeys = Set<String>()
        var sequence: [String] = []
        var seenStates = Set<String>()
        var observedFocusedElement = false

        // Do not force a minimum of 80 Appium round-trips on every screen.
        // The previous `max(...)` made even a screen with 2 controls perform
        // 80 Tab -> page-source cycles. Cap the probe by the number of
        // controls actually present, while retaining a configurable safety
        // ceiling for larger screens.
        let maxTabs = min(maxAdditionalTabs, controls.count * 3 + 3)

        for _ in 0..<maxTabs {
            try Task.checkCancellation()
            try await appium.pressTab()

            // Give XCTest/WDA a short opportunity to settle its focus state.
            try await Task.sleep(for: .milliseconds(120))

            let source = try await appium.getSource()
            let root = try appium.makeParser().parse(source)

            guard let focused = firstFocusedNode(in: root) else {
                continue
            }

            observedFocusedElement = true
            let key = stableKey(for: focused)
            if sequence.last != key {
                sequence.append(key)
            }

            recordFocused(
                in: root,
                controls: controls,
                reachedKeys: &reachedKeys,
                sequence: &sequence
            )

            let stateKey = key + "|" + reachedKeys.sorted().joined(separator: ",")
            if !seenStates.insert(stateKey).inserted {
                break
            }

            if reachedKeys.count == controls.count {
                break
            }
        }

        if !observedFocusedElement {
            let evaluation = validationEvaluation(
                node: rootNode,
                message: "Keyboard focus could not be observed after Tab navigation.",
                remediation: "Ensure the XCUITest/Appium source exposes the focused attribute and that the app supports keyboard focus navigation on this screen."
            )
            return Result(
                evaluations: [evaluation],
                focusedSequence: sequence,
                reachedControlCount: 0,
                requiredControlCount: controls.count,
                evidenceAvailable: false
            )
        }

        var evaluations: [AccessibilityRuleEvaluation] = []

        for control in controls {
            let key = stableKey(for: control)
            if reachedKeys.contains(key) {
                evaluations.append(
                    passEvaluation(
                        node: control,
                        message: "Keyboard focus reached this interactive control during Tab navigation."
                    )
                )
            } else {
                evaluations.append(
                    failEvaluation(
                        node: control,
                        message: "Keyboard focus did not reach this interactive control during Tab navigation.",
                        remediation: "Make the control keyboard focusable and ensure it participates in the intended keyboard focus order."
                    )
                )
            }
        }

        return Result(
            evaluations: evaluations,
            focusedSequence: sequence,
            reachedControlCount: reachedKeys.count,
            requiredControlCount: controls.count,
            evidenceAvailable: true
        )
    }

    private func interactiveControls(in root: AccessibilityNode) -> [AccessibilityNode] {
        var result: [AccessibilityNode] = []

        func walk(_ node: AccessibilityNode) {
            if node.visible && node.enabled && node.exists &&
                (node.isInteractive || node.isKeyboardFocusable) {
                result.append(node)
            }
            for child in node.children {
                walk(child)
            }
        }

        walk(root)
        return result
    }

    private func firstFocusedNode(in root: AccessibilityNode) -> AccessibilityNode? {
        if root.focused && root.visible && root.exists {
            return root
        }
        for child in root.children {
            if let focused = firstFocusedNode(in: child) {
                return focused
            }
        }
        return nil
    }

    private func recordFocused(
        in root: AccessibilityNode,
        controls: [AccessibilityNode],
        reachedKeys: inout Set<String>,
        sequence: inout [String]
    ) {
        guard let focused = firstFocusedNode(in: root) else { return }
        let focusedKey = stableKey(for: focused)
        if sequence.last != focusedKey {
            sequence.append(focusedKey)
        }

        if let matching = controls.first(where: { stableKey(for: $0) == focusedKey }) {
            reachedKeys.insert(stableKey(for: matching))
        }
    }

    private func stableKey(for node: AccessibilityNode) -> String {
        let identifier = node.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = node.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let frame = "\(Int(node.frame.origin.x.rounded())):\(Int(node.frame.origin.y.rounded())):\(Int(node.frame.width.rounded())):\(Int(node.frame.height.rounded()))"
        return [node.type, identifier, label, frame].joined(separator: "|")
    }

    private func baseEvaluation(
        node: AccessibilityNode,
        status: RuleResultStatus,
        severity: AccessibilityFinding.Severity,
        message: String,
        remediation: String?
    ) -> AccessibilityRuleEvaluation {
        AccessibilityRuleEvaluation(
            ruleID: "keyboard-focus",
            ruleName: "Interactive control can receive keyboard focus",
            ruleDescription: "Keyboard users should be able to reach interactive controls where keyboard operation is supported.",
            status: status,
            severity: severity,
            message: message,
            remediation: remediation ?? "",
            node: node
        )
    }

    private func passEvaluation(node: AccessibilityNode, message: String) -> AccessibilityRuleEvaluation {
        baseEvaluation(node: node, status: .pass, severity: .info, message: message, remediation: nil)
    }

    private func failEvaluation(node: AccessibilityNode, message: String, remediation: String) -> AccessibilityRuleEvaluation {
        baseEvaluation(node: node, status: .fail, severity: .error, message: message, remediation: remediation)
    }

    private func validationEvaluation(node: AccessibilityNode, message: String, remediation: String) -> AccessibilityRuleEvaluation {
        baseEvaluation(node: node, status: .validate, severity: .warning, message: message, remediation: remediation)
    }
}
