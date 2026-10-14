//
//  KeyboardAndFormProbes.swift
//  AccessibilityScanner
//


import Foundation
import CoreGraphics

extension ProbeNodes {
    static func contentSignature(in root: AccessibilityNode) -> Int {
        var hasher = Hasher()
        for node in all(in: root) where node.visible {
            let traits = node.traits
                .replacingOccurrences(of: "focused", with: "")
                .trimmingCharacters(in: .whitespaces)
            hasher.combine(node.type)
            hasher.combine(node.label)
            hasher.combine(node.value ?? "")
            hasher.combine(traits)
        }
        return hasher.finalize()
    }

    static func focusedNode(in root: AccessibilityNode) -> AccessibilityNode? {
        all(in: root).first { $0.focused && $0.visible }
    }
}

// MARK: - Keyboard activation

final class KeyboardActivationProbe {

    private let appium: AppiumClient
    private let ruleID = "keyboard-activation"
    private let maximumControls: Int
    private let maximumTabsPerControl: Int
    private let focusResult: KeyboardFocusTester.Result?
    private let alreadyTested: Set<String>

    private(set) var testedKeys = Set<String>()
    init(
        appium: AppiumClient,
        maximumControls: Int = 3,
        maximumTabsPerControl: Int = 30,
        focusResult: KeyboardFocusTester.Result? = nil,
        alreadyTested: Set<String> = []
    ) {
        self.appium = appium
        self.maximumControls = maximumControls
        self.maximumTabsPerControl = maximumTabsPerControl
        self.focusResult = focusResult
        self.alreadyTested = alreadyTested
    }

    func test(rootNode: AccessibilityNode) async throws -> [AccessibilityRuleEvaluation] {

        if let focusResult, !focusResult.evidenceAvailable {
            return [ProbeEvaluation.make(
                ruleID: ruleID,
                status: .notTested,
                message: "Keyboard activation was not tested because keyboard focus could not be observed on this screen.",
                remediation: "Tab to each button and link with a hardware keyboard and press Space/Enter to confirm it activates.",
                node: rootNode
            )]
        }

        var eligible = ProbeNodes.all(in: rootNode)
            .filter {
                ($0.role == .button || $0.role == .link) &&
                $0.visible && $0.enabled &&
                ActionSafety.isSafeToActivate($0) &&
                !alreadyTested.contains(ProbeNodes.probeKey($0)) &&
                NavigationAction(node: $0).xpath != nil
            }

        var tabLimit = maximumTabsPerControl
        if let reached = focusResult?.reachedNodes, !reached.isEmpty {
            // Controls focus never reached are already reported by the focus
            // traversal; trying them again would only burn the Tab limit.
            eligible = reached.compactMap { node in eligible.first { matches(node, $0) } }
            tabLimit = min(maximumTabsPerControl, reached.count + 2)
        }

        let candidates = eligible.prefix(maximumControls)
        guard !candidates.isEmpty else { return [] }

        // Start from what is on screen now, not the earlier snapshot.
        guard let currentSource = try? await appium.getSource(),
              var current = try? appium.makeParser().parse(currentSource)
        else { return [] }

        var results: [AccessibilityRuleEvaluation] = []

        for control in candidates {
            try Task.checkCancellation()

            testedKeys.insert(ProbeNodes.probeKey(control))
            let name = control.hasAccessibleName ? control.label : control.identifier
            let beforeLabels = ProbeNodes.contentLabels(in: current)

            // 1. Move keyboard focus onto the control.
            var focused = false
            for _ in 0..<tabLimit {
                try await appium.pressTab()
                try await Task.sleep(nanoseconds: 120_000_000)
                guard let source = try? await appium.getSource(),
                      let root = try? appium.makeParser().parse(source) else { break }
                current = root
                if let node = ProbeNodes.focusedNode(in: root), matches(node, control) {
                    focused = true
                    break
                }
            }

            guard focused else {
                results.append(ProbeEvaluation.make(
                    ruleID: ruleID,
                    status: .notTested,
                    message: "Keyboard focus could not be moved onto \"\(name)\", so keyboard activation was not tested.",
                    remediation: "Tab to the control with a hardware keyboard and press Space/Enter to confirm it activates.",
                    node: control
                ))
                continue
            }

            // 2. Activate it from the keyboard.
            let focusedSignature = ProbeNodes.contentSignature(in: current)
            try await appium.pressActivate()
            try await Task.sleep(nanoseconds: 700_000_000)

            guard let afterSource = try? await appium.getSource(),
                  let afterRoot = try? appium.makeParser().parse(afterSource) else {
                results.append(ProbeEvaluation.make(
                    ruleID: ruleID,
                    status: .notTested,
                    message: "The screen could not be read after pressing the activation key on \"\(name)\".",
                    node: control
                ))
                continue
            }

            if ProbeNodes.contentSignature(in: afterRoot) != focusedSignature {
                results.append(ProbeEvaluation.make(
                    ruleID: ruleID,
                    status: .pass,
                    message: "\"\(name)\" responded to the keyboard activation key.",
                    node: control
                ))
                current = await restoreIfNavigated(from: afterRoot, baselineLabels: beforeLabels, fallback: afterRoot)
                continue
            }

            guard let xpath = NavigationAction(node: control).xpath,
                  (try? await appium.tapElement(usingXPath: xpath)) != nil else {
                results.append(ProbeEvaluation.make(
                    ruleID: ruleID,
                    status: .validate,
                    message: "Activating \"\(name)\" from the keyboard produced no visible change, and it could not be tapped to compare.",
                    remediation: "Press Space/Enter on the control with a hardware keyboard and confirm it activates.",
                    node: control
                ))
                continue
            }

            try await Task.sleep(nanoseconds: 700_000_000)
            guard let tapSource = try? await appium.getSource(),
                  let tapRoot = try? appium.makeParser().parse(tapSource) else { continue }

            if ProbeNodes.contentSignature(in: tapRoot) != focusedSignature {
                results.append(ProbeEvaluation.make(
                    ruleID: ruleID,
                    status: .fail,
                    message: "\"\(name)\" responds to a tap but not to the keyboard activation key.",
                    remediation: "Make the control respond to keyboard activation (Space/Enter) the same way it responds to a tap.",
                    node: control
                ))
                current = await restoreIfNavigated(from: tapRoot, baselineLabels: beforeLabels, fallback: tapRoot)
            } else {
                results.append(ProbeEvaluation.make(
                    ruleID: ruleID,
                    status: .validate,
                    message: "Neither a tap nor the keyboard activation key on \"\(name)\" produced a visible change, so keyboard operability could not be confirmed.",
                    remediation: "Press Space/Enter on the control with a hardware keyboard and confirm it activates.",
                    node: control
                ))
                current = tapRoot
            }

        }

        return results
    }

    private func restoreIfNavigated(
        from root: AccessibilityNode,
        baselineLabels: Set<String>,
        fallback: AccessibilityNode
    ) async -> AccessibilityNode {

        guard !baselineLabels.isEmpty else { return fallback }
        let labels = ProbeNodes.contentLabels(in: root)
        let missing = Double(baselineLabels.subtracting(labels).count) / Double(baselineLabels.count)
        guard missing > 0.5 else { return fallback }

        try? await appium.goBack()
        try? await Task.sleep(nanoseconds: 800_000_000)
        if let source = try? await appium.getSource(),
           let restored = try? appium.makeParser().parse(source) {
            return restored
        }
        return fallback
    }

    private func matches(_ node: AccessibilityNode, _ control: AccessibilityNode) -> Bool {
        guard node.type == control.type else { return false }
        let identifier = control.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !identifier.isEmpty { return node.identifier == control.identifier }
        return node.label == control.label
    }
}

// MARK: - Error messages

nonisolated enum ErrorMessageHeuristics {

    private static let errorCues = [
        "error", "invalid", "incorrect", "required", "must", "cannot", "can't", "can not",
        "wrong", "failed", "not valid", "please enter", "empty", "missing"
    ]

    private static let strictErrorCues = [
        "error", "invalid", "incorrect", "failed", "wrong", "not valid"
    ]

    private static let guidanceCues = [
        "enter", "must", "should", "at least", "at most", "between", "format", "example",
        "e.g.", "please", "try", "use ", "include", "contain", "required", "empty",
        "missing", "match", "provide", "select", "choose"
    ]

    /// Broad: used on text that newly appeared after submitting a form.
    static func looksLikeError(_ text: String) -> Bool {
        let lower = text.lowercased()
        return errorCues.contains { lower.contains($0) }
    }

    /// Narrow: used on text already on screen, where "required" labels are common.
    static func looksLikeStrictError(_ text: String) -> Bool {
        let lower = text.lowercased()
        return strictErrorCues.contains { lower.contains($0) }
    }

    static func givesGuidance(_ text: String) -> Bool {
        let lower = text.lowercased()
        return guidanceCues.contains { lower.contains($0) }
    }
}

final class ErrorMessageProbe {

    private let appium: AppiumClient
    private let alreadyTested: Set<String>

    private(set) var testedKeys = Set<String>()

    private static let submitCues = [
        "sign in", "log in", "login", "continue", "next", "register", "sign up",
        "create account", "verify"
    ]

    init(appium: AppiumClient, alreadyTested: Set<String> = []) {
        self.appium = appium
        self.alreadyTested = alreadyTested
    }

    func test(rootNode: AccessibilityNode) async throws -> [AccessibilityRuleEvaluation] {

        let nodes = ProbeNodes.all(in: rootNode).filter { $0.visible }
        let inputs = nodes.filter { AccessibilityRole.textInputs.contains($0.role) }
        guard !inputs.isEmpty else { return [] }

        let untouched = inputs.allSatisfy { input in
            let value = (input.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let placeholder = (input.placeholderValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty || value == placeholder
        }
        guard untouched else { return [] }

        let topOfForm = inputs.map(\.frame.minY).min() ?? 0

        guard let submit = nodes.first(where: { node in
            guard node.role == .button, node.enabled, ActionSafety.isSafeToActivate(node),
                  NavigationAction(node: node).xpath != nil else { return false }
            // The button must belong to the form: below its first field.
            guard node.frame.minY >= topOfForm else { return false }
            let text = (node.label + " " + node.identifier).lowercased()
            return Self.submitCues.contains { text.contains($0) }
        }), let xpath = NavigationAction(node: submit).xpath else { return [] }

        // The same form reached from another path was already submitted.
        guard testedKeys.insert(ProbeNodes.probeKey(submit)).inserted,
              !alreadyTested.contains(ProbeNodes.probeKey(submit)) else { return [] }

        let submitName = submit.hasAccessibleName ? submit.label : submit.identifier
        let beforeLabels = ProbeNodes.contentLabels(in: rootNode)

        do {
            try await appium.tapElement(usingXPath: xpath)
        } catch {
            return []
        }
        try await Task.sleep(nanoseconds: 800_000_000)

        guard let source = try? await appium.getSource(),
              let after = try? appium.makeParser().parse(source) else { return [] }

        let afterLabels = ProbeNodes.contentLabels(in: after)
        if !beforeLabels.isEmpty {
            let missing = Double(beforeLabels.subtracting(afterLabels).count) / Double(beforeLabels.count)
            if missing > 0.5 {
                try? await appium.goBack()
                try? await Task.sleep(nanoseconds: 800_000_000)
                return []
            }
        }

        let newMessages = ProbeNodes.all(in: after)
            .filter { node in
                guard node.visible,
                      AccessibilityRole.textual.contains(node.role) else { return false }
                let text = node.label.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, !beforeLabels.contains(text) else { return false }
                return ErrorMessageHeuristics.looksLikeError(text) || isNearInput(node, inputs)
            }
            .map { $0.label.trimmingCharacters(in: .whitespacesAndNewlines) }

        await dismissAlert(in: after)

        var seen = Set<String>()
        let messages = newMessages.filter { seen.insert($0).inserted }.prefix(6)
        guard !messages.isEmpty else { return [] }

        let lacking = messages.filter { !ErrorMessageHeuristics.givesGuidance($0) }
        let sample = messages.first ?? ""

        var results: [AccessibilityRuleEvaluation] = []

        results.append(ProbeEvaluation.make(
            ruleID: "error-message-accessibility",
            status: .pass,
            message: "Submitting the empty form with \"\(submitName)\" showed \(messages.count) error message\(messages.count == 1 ? "" : "s") as text exposed to assistive technology (for example: \"\(sample)\"). Whether a screen reader announces them was not tested.",
            node: submit
        ))

        if lacking.isEmpty {
            results.append(ProbeEvaluation.make(
                ruleID: "error-message-suggestion",
                status: .pass,
                message: "The error messages shown after submitting the empty form say how to correct the input.",
                node: submit
            ))
        } else {
            let examples = lacking.prefix(3).map { "\"\($0)\"" }.joined(separator: ", ")
            results.append(ProbeEvaluation.make(
                ruleID: "error-message-suggestion",
                status: .warning,
                message: "\(lacking.count) of \(messages.count) error messages do not say how to correct the input (for example: \(examples)).",
                remediation: "Say what is wrong and how to fix it, for example the expected format or the missing information.",
                node: submit
            ))
        }

        return results
    }

    private func isNearInput(_ node: AccessibilityNode, _ inputs: [AccessibilityNode]) -> Bool {
        inputs.contains { input in
            let verticalGap = max(node.frame.minY - input.frame.maxY, input.frame.minY - node.frame.maxY, 0)
            let horizontalOverlap = min(node.frame.maxX, input.frame.maxX) - max(node.frame.minX, input.frame.minX)
            return verticalGap <= 60 && horizontalOverlap > 0
        }
    }

    /// Closes a native alert so the next step starts from the form. Only a
    /// Cancel/Close/OK-style button is pressed, never one that accepts
    /// ("Submit anyway", "Allow", "Delete").
    private func dismissAlert(in root: AccessibilityNode) async {
        guard let alert = ProbeNodes.all(in: root).first(where: { $0.type.contains("Alert") }) else { return }
        let buttons = ProbeNodes.all(in: alert).filter {
            $0.role == .button && NavigationAction(node: $0).xpath != nil
        }
        guard let button = ActionSafety.dismissButton(in: buttons),
              let xpath = NavigationAction(node: button).xpath else { return }

        try? await appium.tapElement(usingXPath: xpath)
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
}
