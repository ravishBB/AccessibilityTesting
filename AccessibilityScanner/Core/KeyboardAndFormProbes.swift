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
    /// iOS: asks the tester to press Tab and Space on the keyboard connected
    /// to the phone when Appium's keys do not reach Full Keyboard Access.
    private let guide: GuidedChecks?

    private(set) var testedKeys = Set<String>()
    init(
        appium: AppiumClient,
        maximumControls: Int = 3,
        maximumTabsPerControl: Int = 30,
        focusResult: KeyboardFocusTester.Result? = nil,
        alreadyTested: Set<String> = [],
        guide: GuidedChecks? = nil
    ) {
        self.guide = guide
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

        if appium.platform == .ios {
            return try await testWithScreenshots(candidates: Array(candidates), tabLimit: tabLimit, rootNode: rootNode)
        }

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

    // MARK: iOS (focus seen in screenshots)

    /// iOS: WebDriverAgent does not report Full Keyboard Access focus, so the
    /// focused control is the one ringed in the focus ring's colour learned
    /// during the Tab traversal. Tab and Space come from Appium when they
    /// reach the phone's keyboard focus, otherwise from the tester.
    private func testWithScreenshots(candidates: [AccessibilityNode], tabLimit: Int, rootNode: AccessibilityNode) async throws -> [AccessibilityRuleEvaluation] {
        guard let guide, let ring = focusResult?.ringColour else {
            return [ProbeEvaluation.make(
                ruleID: ruleID, status: .notTested,
                message: "Keyboard activation was not tested: it needs the keyboard focus check to have run with a keyboard connected to the phone.",
                remediation: "Tab to each button and link with a hardware keyboard and press Space to confirm it activates.",
                node: rootNode)]
        }
        let tabByAppium = focusResult?.tabByAppium == true
        var results: [AccessibilityRuleEvaluation] = []

        func screenshot() async -> CGImage? { KeyboardFocusTester.image(try? await appium.getScreenshot()) }
        func readRoot() async -> AccessibilityNode? {
            guard let source = try? await appium.getSource() else { return nil }
            return try? appium.makeParser().parse(source)
        }
        /// The control ringed in the focus colour now.
        func focused(in root: AccessibilityNode, shot: CGImage) -> AccessibilityNode? {
            ProbeNodes.all(in: root)
                .filter { $0.visible && AccessibilityRole.controls.contains($0.role) }
                .map { ($0, KeyboardFocusTester.ringMatch(shot, node: $0, color: ring, hierarchySize: root.frame.size)) }
                .filter { $0.1 >= 0.25 }
                .max { $0.1 < $1.1 }?.0
        }
        /// Shows a card and waits until the screen changes or the tester
        /// answers. Returns the changed screenshot, or nil.
        func waitForChange(_ step: GuidedChecks.Step, from start: CGImage) async throws -> CGImage? {
            guide.present(step)
            defer { if guide.isWaiting(step.id) { guide.finish(.detected) } }
            let deadline = Date().addingTimeInterval(45)
            let ignoreTop = Int(Double(start.height) * 0.07)
            while guide.isWaiting(step.id), Date() < deadline {
                try await Task.sleep(nanoseconds: 300_000_000)
                guard let shot = await screenshot() else { continue }
                if KeyboardFocusTester.changedRegion(start, shot, ignoreTop: ignoreTop) != nil {
                    try await Task.sleep(nanoseconds: 400_000_000)
                    return await screenshot() ?? shot
                }
            }
            return nil
        }

        for control in candidates {
            try Task.checkCancellation()
            testedKeys.insert(ProbeNodes.probeKey(control))
            let name = control.hasAccessibleName ? control.label : control.identifier

            // 1. Focus onto the control.
            var onControl = false
            guard var shot = await screenshot(), var root = await readRoot() else { break }
            for _ in 0..<tabLimit {
                if let node = focused(in: root, shot: shot), matches(node, control) { onControl = true; break }
                if tabByAppium {
                    try? await appium.pressTab()
                    try await Task.sleep(nanoseconds: 400_000_000)
                    guard let next = await screenshot() else { break }
                    shot = next
                } else {
                    let step = GuidedChecks.Step(
                        title: "Press Tab on the keyboard",
                        message: "Press Tab once to move focus towards \"\(name)\". The scanner then checks that pressing Space activates it.",
                        actions: [GuidedChecks.Action(reply: .skip, title: "Skip")],
                        progress: "Press Tab")
                    guard let next = try await waitForChange(step, from: shot) else { break }
                    shot = next
                }
                guard let next = await readRoot() else { break }
                root = next
            }
            guard onControl else {
                results.append(ProbeEvaluation.make(
                    ruleID: ruleID, status: .notTested,
                    message: "Keyboard focus could not be moved onto \"\(name)\", so keyboard activation was not tested.",
                    remediation: "Tab to the control with a hardware keyboard and press Space to confirm it activates.",
                    node: control))
                continue
            }

            // 2. Activate it from the keyboard.
            let beforeLabels = ProbeNodes.contentLabels(in: root)
            var activated: CGImage?
            if tabByAppium {
                try? await appium.pressActivate()
                try await Task.sleep(nanoseconds: 700_000_000)
                if let after = await screenshot(),
                   KeyboardFocusTester.changedRegion(shot, after, ignoreTop: Int(Double(shot.height) * 0.07)) != nil {
                    activated = after
                }
            }
            if activated == nil {
                let step = GuidedChecks.Step(
                    title: "Press Space on the keyboard",
                    message: "Focus is on \"\(name)\". Press Space once to activate it. If nothing happens, press Nothing happened.",
                    actions: [GuidedChecks.Action(reply: .skip, title: "Skip"),
                              GuidedChecks.Action(reply: .nothingHappened, title: "Nothing happened")],
                    progress: "Watching the screen…")
                activated = try await waitForChange(step, from: shot)
                if activated == nil, guide.lastReply == .skip {
                    results.append(ProbeEvaluation.make(
                        ruleID: ruleID, status: .notTested,
                        message: "Keyboard activation of \"\(name)\" was skipped by the tester.",
                        remediation: "Press Space on the control with a hardware keyboard and confirm it activates.",
                        node: control))
                    continue
                }
            }

            if activated != nil {
                results.append(ProbeEvaluation.make(
                    ruleID: ruleID, status: .pass,
                    message: "\"\(name)\" responded to Space from the keyboard.",
                    node: control))
                let now = await readRoot() ?? root
                _ = await restoreIfNavigated(from: now, baselineLabels: beforeLabels, fallback: now)
                continue
            }

            // 3. Nothing from the keyboard: does a tap do anything?
            guard let xpath = NavigationAction(node: control).xpath,
                  (try? await appium.tapElement(usingXPath: xpath)) != nil else {
                results.append(ProbeEvaluation.make(
                    ruleID: ruleID, status: .validate,
                    message: "Pressing Space on \"\(name)\" produced no visible change, and it could not be tapped to compare.",
                    remediation: "Press Space on the control with a hardware keyboard and confirm it activates.",
                    node: control))
                continue
            }
            try await Task.sleep(nanoseconds: 700_000_000)
            if let tapped = await screenshot(),
               KeyboardFocusTester.changedRegion(shot, tapped, ignoreTop: Int(Double(shot.height) * 0.07)) != nil {
                results.append(ProbeEvaluation.make(
                    ruleID: ruleID, status: .fail,
                    message: "\"\(name)\" responds to a tap but not to Space from a keyboard, so keyboard users cannot operate it.",
                    remediation: "Make the control respond to keyboard activation the same way it responds to a tap (a UIButton or accessibilityActivate()).",
                    node: control))
                let now = await readRoot() ?? root
                _ = await restoreIfNavigated(from: now, baselineLabels: beforeLabels, fallback: now)
            } else {
                results.append(ProbeEvaluation.make(
                    ruleID: ruleID, status: .validate,
                    message: "Neither a tap nor Space on \"\(name)\" produced a visible change, so keyboard operability could not be confirmed.",
                    remediation: "Press Space on the control with a hardware keyboard and confirm it activates.",
                    node: control))
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
