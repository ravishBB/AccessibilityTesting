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
        /// iOS: the focus ring's colour seen in screenshots, and whether
        /// Appium's Tab moved Full Keyboard Access focus (else the tester
        /// pressed Tab). Used again by the keyboard activation check.
        var ringColour: [Int]? = nil
        var tabByAppium: Bool? = nil
    }

    private let appium: AppiumClient
    /// iOS: asks the tester to press Tab on a keyboard connected to the
    /// phone when Appium's Tab does not move Full Keyboard Access focus.
    private let guide: GuidedChecks?
    private let maxAdditionalTabs: Int
    private let settleMilliseconds: UInt64

    /// Tabs to try before concluding the session does not expose keyboard
    /// focus at all. Each Tab costs a full hierarchy fetch.
    private let tabsBeforeGivingUp = 3

    init(
        appium: AppiumClient,
        guide: GuidedChecks? = nil,
        // A full cycle needs one Tab per control plus the wrap back.
        maxAdditionalTabs: Int = 60,
        settleMilliseconds: UInt64 = 60
    ) {
        self.appium = appium
        self.guide = guide
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

    /// `viewportRoots`: the hierarchy at each scroll position of this screen,
    /// top first, so controls below the fold are expected too.
    func test(rootNode: AccessibilityNode, viewportRoots: [AccessibilityNode] = []) async throws -> Result {
        if appium.platform == .ios, guide == nil {
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
        let controls = activeModal == nil
            ? interactiveControls(in: [rootNode] + viewportRoots)
            : interactiveControls(in: [controlsRoot])
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
        var observedFocusedElement = false
        var trapDetected = false
        var trapNode: AccessibilityNode?
        var scrolledSinceScreenshot = false
        var scrolledDuringTraversal = false
        var visualEvidence: [String: Bool] = [:]
        var indicatorContrast: [String: (node: AccessibilityNode, ratio: Double)] = [:]
        var focusCues: [String: (node: AccessibilityNode, cue: FocusCue)] = [:]
        var obscuredBy: [String: (node: AccessibilityNode, cover: AccessibilityNode)] = [:]
        var traversalCompleted = false
        var hiddenFocused: [String: AccessibilityNode] = [:]
        var nonInteractiveFocused: [String: AccessibilityNode] = [:]
        var baselineLabels = ProbeNodes.contentLabels(in: rootNode)
        var baselineRoot = rootNode
        var contextChanged = false
        var stepsObserved = 0

        // Enough Tabs to pass every control and wrap back to the first one.
        let maxTabs = min(maxAdditionalTabs, max(4, controls.count * 2 + 4))
        var baselineScreenshot = try? await appium.getScreenshot()

        var textFieldsLeftByArrow = Set<String>()
        var skipNextTab = false

        // iOS: WebDriverAgent does not report Full Keyboard Access focus, so
        // focus is found in screenshots: the control around which pixels
        // changed since the screenshot taken before the first Tab, or, once
        // the screen has scrolled, the control ringed in the focus ring's
        // colour learned from the first step.
        let visual = appium.platform == .ios
        var tabByAppium: Bool?
        var lastShot = visual ? Self.image(baselineScreenshot) : nil
        var previousShot: CGImage?
        let noFocusShot = lastShot
        let noFocusData = baselineScreenshot
        var testerFinished = false
        var unmappedSteps = 0
        var noFocusLayout = true
        var ringColour: [Int]?
        var promptID: UUID?
        var recorded = 0
        var lastFocusedName = ""

        /// Waits for the tester to press Tab: the next change on screen.
        /// false: the tester pressed Done or skipped, or nothing changed.
        func waitForTesterTab() async throws -> Bool {
            guard let guide else { return false }
            if promptID == nil {
                let step = GuidedChecks.Step(
                    title: "Press Tab on the keyboard",
                    message: "Press Tab on the keyboard connected to the iPhone, once each time this card says Press Tab. Keep going until focus is back on the first control, then press Done.",
                    actions: [GuidedChecks.Action(reply: .skip, title: "Skip this screen"),
                              GuidedChecks.Action(reply: .done, title: "Done")],
                    progress: "Press Tab"
                )
                guide.present(step)
                promptID = step.id
            } else {
                guide.update(progress: "Recorded \(recorded) step\(recorded == 1 ? "" : "s")\(lastFocusedName.isEmpty ? "" : ", last: \"\(lastFocusedName)\""). Press Tab")
            }
            let deadline = Date().addingTimeInterval(45)
            while let id = promptID, guide.isWaiting(id), Date() < deadline {
                try await Task.sleep(nanoseconds: 300_000_000)
                guard let shot = Self.image(try? await appium.getScreenshot()), let last = lastShot else { continue }
                if Self.screenChanged(last, shot) {
                    // Let the ring finish drawing before reading it.
                    try await Task.sleep(nanoseconds: 250_000_000)
                    previousShot = lastShot
                    lastShot = Self.image(try? await appium.getScreenshot()) ?? shot
                    guide.update(progress: "Reading where focus went…")
                    return true
                }
            }
            // Done: the tester saw focus come back to the first control.
            if guide.lastReply == .done { testerFinished = true }
            return false
        }

        /// Moves focus one step: Appium's Tab when it works, else the tester.
        func advanceVisualFocus() async throws -> Bool {
            if tabByAppium != false {
                try? await appium.pressTab()
                try await Task.sleep(nanoseconds: 400_000_000)
                let shot = Self.image(try? await appium.getScreenshot())
                if tabByAppium == nil, let shot, let last = lastShot {
                    tabByAppium = Self.screenChanged(last, shot)
                }
                if tabByAppium == true {
                    previousShot = lastShot
                    lastShot = shot ?? lastShot
                    return true
                }
            }
            return try await waitForTesterTab()
        }

        func visualFocus(in root: AccessibilityNode) -> AccessibilityNode? {
            guard let shot = lastShot else { return nil }
            let size = root.frame.size
            if noFocusLayout, ProbeNodes.contentScrolled(from: rootNode, to: root) { noFocusLayout = false }
            let candidates = interactiveControls(in: [root])
            var found: AccessibilityNode?
            if ringColour == nil {
                // Learn the ring from a control in the content: translucent
                // tab and navigation bars change with what scrolls behind
                // them, which reads like a ring.
                let inBars = Self.barControlFrames(in: root)
                if let reference = noFocusLayout ? noFocusShot : previousShot {
                    let learned = candidates
                        .filter { control in !inBars.contains { $0.intersects(control.frame) } }
                        .map { ($0, Self.changeRatio(before: reference, after: shot, node: $0, hierarchySize: size)) }
                        .filter { $0.1 >= 0.015 }
                        .max { $0.1 < $1.1 }?.0
                    if let learned, let colour = Self.ringColor(before: reference, after: shot, node: learned, hierarchySize: size) {
                        ringColour = colour
                        found = learned
                    }
                }
                if found == nil { unmappedSteps += 1 }
            } else if let ringColour {
                // Where the ring arrived: in its colour now and not before.
                func arrival(_ nodes: [AccessibilityNode]) -> AccessibilityNode? {
                    nodes.map { node -> (AccessibilityNode, Double, Double) in
                        let now = Self.ringMatch(shot, node: node, color: ringColour, hierarchySize: size)
                        let before = previousShot.map { Self.ringMatch($0, node: node, color: ringColour, hierarchySize: size) } ?? 0
                        return (node, now, now - before)
                    }
                    .filter { $0.1 >= 0.25 && $0.2 >= 0.1 }
                    .max { $0.2 < $1.2 }?.0
                }
                let screenArea = root.frame.width * root.frame.height
                found = arrival(candidates)
                    ?? arrival(ProbeNodes.all(in: root).filter {
                        $0.visible && $0.accessible && $0.role != .application && $0.frame.width * $0.frame.height < screenArea * 0.5
                    })
                if found == nil {
                    // The ring arrived on something not shown or not exposed.
                    let hidden = ProbeNodes.all(in: root).filter { !($0.visible && $0.accessible) && $0.frame.width > 0 && $0.frame.height > 0 }
                    if let node = arrival(hidden) {
                        hiddenFocused[stableKey(for: node)] = node
                    } else {
                        unmappedSteps += 1
                    }
                }
            }
            if let found {
                recorded += 1
                lastFocusedName = ProbeNodes.clean(found.label)
            }
            return found
        }

        for tabIndex in 0..<maxTabs {
            try Task.checkCancellation()
            // On iOS the first steps can land in a bar before the ring's
            // colour is known.
            if !observedFocusedElement && hiddenFocused.isEmpty && tabIndex >= (visual ? 6 : tabsBeforeGivingUp) {
                break
            }
            if skipNextTab {
                skipNextTab = false
            } else if visual {
                guard try await advanceVisualFocus() else { break }
            } else {
                try await appium.pressTab()
            }

            if settleMilliseconds > 0 {
                try await Task.sleep(for: .milliseconds(settleMilliseconds))
            }

            let source = try await appium.getSource()
            let root = try appium.makeParser().parse(source)
            
            if let anyFocused = anyFocusedNode(in: root), !(anyFocused.visible && anyFocused.accessible) {
                hiddenFocused[stableKey(for: anyFocused)] = anyFocused
            }
            if !baselineLabels.isEmpty {
                let currentLabels = ProbeNodes.contentLabels(in: root)
                let missing = Double(baselineLabels.subtracting(currentLabels).count) / Double(baselineLabels.count)
                if missing > 0.6 {
                    if Self.scrolledWithinSameContainer(before: baselineRoot, after: root) {
                        baselineLabels = currentLabels
                        baselineRoot = root
                        scrolledSinceScreenshot = true
                        scrolledDuringTraversal = true
                    } else {
                        contextChanged = true
                        try? await appium.goBack()
                        break
                    }
                }
            }

            guard let focused = visual ? visualFocus(in: root) : firstFocusedNode(in: root) else {
                continue
            }

            stepsObserved += 1
            if !(focused.isInteractive || focused.isKeyboardFocusable) {
                nonInteractiveFocused[stableKey(for: focused)] = focused
            }

            observedFocusedElement = true
            let key = stableKey(for: focused)

            if visual, key == sequence.last || sequence.contains(key) {
                // Screenshots can show the same control twice; the cycle is
                // complete only when focus is back on the first control
                // after most of the screen, or when the tester says so.
                if key == sequence.first, sequence.count >= max(2, controls.count / 2) {
                    traversalCompleted = true
                    break
                }
                continue
            }
            if key == sequence.last || sequence.contains(key) {
                if !visual, Self.isTextInput(focused), textFieldsLeftByArrow.insert(key).inserted {
                    try await appium.pressArrowDown()
                    if settleMilliseconds > 0 {
                        try await Task.sleep(for: .milliseconds(settleMilliseconds))
                    }
                    skipNextTab = true
                    continue
                }
                if key != sequence.first,
                   unreachedFocusableControl(after: key, controls: controls, reached: reachedKeys) {
                    trapDetected = true
                    trapNode = focused
                } else {
                    traversalCompleted = true
                }
                break
            }
            sequence.append(key)

            if let matching = controls.first(where: { stableKey(for: $0) == key }) {
                reachedKeys.insert(key)

                // iOS: focus was found by its ring, so it is visible; contrast
                // and cue need the screenshot taken before any focus.
                if visual {
                    visualEvidence[key] = true
                    if noFocusLayout, let noFocusData {
                        let focusedScreenshot = try? await appium.getScreenshot()
                        if let ratio = indicatorContrastRatio(before: noFocusData, after: focusedScreenshot, node: focused, hierarchySize: root.frame.size) {
                            indicatorContrast[key] = (matching, ratio)
                        }
                        if let cue = Self.focusCue(before: noFocusData, after: focusedScreenshot, node: focused, hierarchySize: root.frame.size) {
                            focusCues[key] = (matching, cue)
                        }
                    }
                } else if scrolledSinceScreenshot {
                    baselineScreenshot = try? await appium.getScreenshot()
                    scrolledSinceScreenshot = false
                } else if let baselineScreenshot {
                    let focusedScreenshot = try? await appium.getScreenshot()
                    visualEvidence[key] = Self.focusRegionChanged(
                        before: baselineScreenshot,
                        after: focusedScreenshot,
                        node: focused,
                        hierarchySize: root.frame.size
                    )
                    if visualEvidence[key] == true,
                       let ratio = indicatorContrastRatio(
                        before: baselineScreenshot,
                        after: focusedScreenshot,
                        node: focused,
                        hierarchySize: root.frame.size
                       ) {
                        indicatorContrast[key] = (matching, ratio)
                    }
                    if visualEvidence[key] == true,
                       let cue = Self.focusCue(before: baselineScreenshot, after: focusedScreenshot,
                                               node: focused, hierarchySize: root.frame.size) {
                        focusCues[key] = (matching, cue)
                    }
                }
                if let cover = coveringElement(over: focused, in: root) {
                    obscuredBy[key] = (matching, cover)
                }
            }
        }

        if visual && testerFinished { traversalCompleted = true }

        // Close the Press Tab card if the traversal ended on its own.
        if let promptID, guide?.isWaiting(promptID) == true { guide?.finish(.done) }

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
            } else if traversalCompleted && visual {
                evaluations.append(baseEvaluation(
                    ruleID: "keyboard-focus",
                    name: "Interactive elements focusable using a keyboard interface",
                    description: "Interactive controls should be reachable through the supported keyboard focus mechanism.",
                    node: control,
                    status: .validate,
                    severity: .warning,
                    message: "Tab went round the whole screen, but the scanner did not see focus on this control in the screenshots. Check whether Tab reaches it.",
                    remediation: "Make the control keyboard focusable (a UIButton or UIControl, or accessibilityRespondsToUserInteraction with focus support)."
                ))
            } else if traversalCompleted {
                evaluations.append(baseEvaluation(
                    ruleID: "keyboard-focus",
                    name: "Interactive elements focusable using a keyboard interface",
                    description: "Interactive controls should be reachable through the supported keyboard focus mechanism.",
                    node: control,
                    status: .fail,
                    severity: .error,
                    message: "Tab moved through the whole screen without ever reaching this control, so keyboard users cannot reach it.",
                    remediation: "Make the control keyboard focusable (Modifier.focusable / clickable in Compose, focusable in React Native, Focus in Flutter)."
                ))
            } else if trapDetected {
                evaluations.append(baseEvaluation(
                    ruleID: "keyboard-focus",
                    name: "Interactive elements focusable using a keyboard interface",
                    description: "Interactive controls should be reachable through the supported keyboard focus mechanism.",
                    node: control,
                    status: .notTested,
                    severity: .warning,
                    message: "A keyboard trap earlier on the screen stopped Tab before this control, so whether it is focusable could not be checked.",
                    remediation: "Fix the keyboard trap, then check this control again."
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
                node: trapNode ?? rootNode,
                status: .fail,
                severity: .error,
                message: "Keyboard focus could not move past this element: Tab kept returning to it while focusable controls further down were never reached.",
                remediation: "Let Tab and Shift+Tab move focus out of this element. Do not move focus back to it from onFocusChanged or key handlers."
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

        let reachedControls = controls.filter { reachedKeys.contains(stableKey(for: $0)) }
        if !visualEvidence.isEmpty {
            for control in reachedControls {
                guard let visible = visualEvidence[stableKey(for: control)] else { continue }
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
                    ? "The focus indicator contrasts \(text) with the colours next to it."
                    : "The focus indicator contrasts only \(text) with the colours next to it; at least 3:1 is required.",
                remediation: ratio >= 3 ? "" : "Make the focus indicator at least 3:1 against adjacent colours, for example a thicker or darker outline.",
                node: node
            ))
        }
        // 1.4.1: focus shown only by a change of colour.
        for (node, cue) in focusCues.values {
            let ratio = String(format: "%.2f:1", cue.stateRatio)
            if cue.hasOutline {
                evaluations.append(ProbeEvaluation.make(
                    ruleID: "focus-indicator-color-only", status: .pass,
                    message: "Focus adds an outline or border around the control, so it does not rely on colour alone.",
                    node: node))
            } else if cue.stateRatio >= 3 {
                evaluations.append(ProbeEvaluation.make(
                    ruleID: "focus-indicator-color-only", status: .pass,
                    message: "Focus changes the control's lightness by \(ratio), which is visible without colour perception.",
                    node: node))
            } else {
                evaluations.append(ProbeEvaluation.make(
                    ruleID: "focus-indicator-color-only", status: .fail,
                    message: "Focus is shown only by a change of colour: no outline or border is added and the lightness changes by \(ratio), under 3:1, so users who cannot tell the colours apart cannot see where focus is.",
                    remediation: "Add a non-colour cue such as an outline, border or underline, or change the lightness by at least 3:1.",
                    node: node))
            }
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
     
            let observedFrames = observedControlKeys.compactMap { key -> CGRect? in
                guard let index = controls.firstIndex(where: { stableKey(for: $0) == key }) else { return nil }
                return scrolledDuringTraversal
                    ? CGRect(x: 0, y: CGFloat(index) * 10, width: 1, height: 1)
                    : controls[index].frame
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
        if hiddenFocused.isEmpty && visual && unmappedSteps > 0 {
            evaluations.append(ProbeEvaluation.make(
                ruleID: "keyboard-focus-hidden-content",
                status: .notTested,
                message: "\(unmappedSteps) focus step\(unmappedSteps == 1 ? "" : "s") could not be matched to an element in the screenshots, so focus landing on hidden content cannot be ruled out.",
                remediation: "Tab through the screen and check focus never disappears onto something not shown.",
                node: rootNode
            ))
        } else if hiddenFocused.isEmpty {
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
            },
            ringColour: ringColour,
            tabByAppium: tabByAppium
        )
    }

    /// Controls in content order across the given scroll positions. Controls
    /// merged into a clickable parent or cut off by the viewport are left out:
    /// the parent, or the viewport showing them whole, stands for them.
    private func interactiveControls(in roots: [AccessibilityNode]) -> [AccessibilityNode] {
        var result: [AccessibilityNode] = []
        var seen = Set<String>()

        func walk(_ node: AccessibilityNode) {
            if node.visible && node.enabled && node.exists && (node.isInteractive || node.isKeyboardFocusable),
               !node.semantics.mergedIntoAncestor, !node.semantics.partiallyVisible {
                let key = stableKey(for: node)
                if seen.insert(key).inserted { result.append(node) }
            }
            for child in node.children { walk(child) }
        }
        roots.forEach(walk)
        return result
    }

    /// A control after `key` in content order that the hierarchy marks
    /// keyboard-focusable but Tab never reached.
    private func unreachedFocusableControl(after key: String, controls: [AccessibilityNode], reached: Set<String>) -> Bool {
        let start = controls.firstIndex { stableKey(for: $0) == key } ?? -1
        return controls.enumerated().contains { index, control in
            index > start && control.isKeyboardFocusable && !reached.contains(stableKey(for: control))
        }
    }

    /// Both snapshots have the same scrolling container (same class and
    /// frame) and the focused element, if any, is inside it.
    static func scrolledWithinSameContainer(before: AccessibilityNode, after: AccessibilityNode) -> Bool {
        func scrollers(_ root: AccessibilityNode) -> [AccessibilityNode] {
            ProbeNodes.all(in: root).filter { node in
                node.visible && node.frame.width > 0 && node.frame.height > 0 &&
                    (node.role == .scrollView || node.role == .table ||
                     node.traits.split(separator: " ").contains("scrollable"))
            }
        }
        func same(_ a: AccessibilityNode, _ b: AccessibilityNode) -> Bool {
            a.type == b.type &&
                abs(a.frame.minX - b.frame.minX) < 2 && abs(a.frame.minY - b.frame.minY) < 2 &&
                abs(a.frame.width - b.frame.width) < 2 && abs(a.frame.height - b.frame.height) < 2
        }
        let previous = scrollers(before)
        let shared = scrollers(after).filter { candidate in previous.contains { same($0, candidate) } }
        guard !shared.isEmpty else { return false }
        guard let focused = ProbeNodes.all(in: after).first(where: { $0.focused && $0.visible }) else { return true }
        return shared.contains { $0.frame.intersects(focused.frame) }
    }

    private static func isTextInput(_ node: AccessibilityNode) -> Bool {
        AccessibilityRole.textInputs.contains(node.role)
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
        // No position: Tab scrolls the screen, so the same control moves.
        let size = "\(Int((node.frame.width / 4).rounded())):\(Int((node.frame.height / 4).rounded()))"
        return [node.type, identifier, label, size].joined(separator: "|")
    }


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
              let beforePixels = Self.pixelBytes(beforeCG, x: x, y: y, width: w, height: h),
              let afterPixels = Self.pixelBytes(afterCG, x: x, y: y, width: w, height: h),
              beforePixels.count == afterPixels.count else { return nil }

        func luminance(_ p: [UInt8], _ i: Int) -> Double {
            func channel(_ v: UInt8) -> Double {
                let c = Double(v) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(p[i]) + 0.7152 * channel(p[i + 1]) + 0.0722 * channel(p[i + 2])
        }

        // WCAG 1.4.11 (AA): the indicator against the colours next to it,
        // which are the pixels focus did not change. Comparing with the
        // colours it replaced is the AAA Focus Appearance measure.
        var indicatorL: [Double] = []
        var adjacentL: [Double] = []
        for i in Swift.stride(from: 0, to: beforePixels.count - 3, by: 4) {
            let distance = abs(Int(beforePixels[i]) - Int(afterPixels[i]))
                + abs(Int(beforePixels[i + 1]) - Int(afterPixels[i + 1]))
                + abs(Int(beforePixels[i + 2]) - Int(afterPixels[i + 2]))
            if distance > 60 {
                indicatorL.append(luminance(afterPixels, i))
            } else if distance < 12 {
                adjacentL.append(luminance(afterPixels, i))
            }
        }
        guard indicatorL.count >= 20, adjacentL.count >= 20 else { return nil }
        let a = indicatorL.sorted()[indicatorL.count / 2]
        let b = adjacentL.sorted()[adjacentL.count / 2]
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

    struct FocusCue {
        /// An outline, border or ring appears at the control's edge.
        let hasOutline: Bool
        /// Lightness contrast between the focused and unfocused colours of
        /// the pixels focus changed.
        let stateRatio: Double
    }

    /// How focus changed the control's appearance: a shape at its edge, or
    /// only the colour of what was already there.
    static func focusCue(before: Data, after: Data?, node: AccessibilityNode, hierarchySize: CGSize) -> FocusCue? {
        guard let after, let beforeImage = NSImage(data: before), let afterImage = NSImage(data: after),
              let beforeCG = beforeImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let afterCG = afterImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = min(beforeCG.width, afterCG.width), height = min(beforeCG.height, afterCG.height)
        let scale = CGFloat(width) / max(1, hierarchySize.width)
        let margin = Int((6 * scale).rounded())
        let band = max(2, Int((3 * scale).rounded()))
        let x0 = max(0, Int(node.frame.minX * scale) - margin), y0 = max(0, Int(node.frame.minY * scale) - margin)
        let x1 = min(width, Int(node.frame.maxX * scale) + margin), y1 = min(height, Int(node.frame.maxY * scale) + margin)
        let w = x1 - x0, h = y1 - y0
        guard w > 2 * margin + 4, h > 2 * margin + 4,
              let b = pixelBytes(beforeCG, x: x0, y: y0, width: w, height: h),
              let a = pixelBytes(afterCG, x: x0, y: y0, width: w, height: h), a.count == b.count else { return nil }

        func luminance(_ p: [UInt8], _ i: Int) -> Double {
            func c(_ v: UInt8) -> Double { let x = Double(v) / 255; return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
            return 0.2126 * c(p[i]) + 0.7152 * c(p[i + 1]) + 0.0722 * c(p[i + 2])
        }
        // Control edges inside the crop.
        let left = margin, top = margin, right = w - margin, bottom = h - margin
        var outsideTotal = 0, outsideChanged = 0, edgeTotal = 0, edgeChanged = 0, innerTotal = 0, innerChanged = 0
        var beforeL: [Double] = [], afterL: [Double] = []
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let changed = abs(Int(b[i]) - Int(a[i])) + abs(Int(b[i + 1]) - Int(a[i + 1])) + abs(Int(b[i + 2]) - Int(a[i + 2])) > 60
                if changed { beforeL.append(luminance(b, i)); afterL.append(luminance(a, i)) }
                let inside = x >= left && x < right && y >= top && y < bottom
                if !inside {
                    outsideTotal += 1; if changed { outsideChanged += 1 }
                } else if x < left + band || x >= right - band || y < top + band || y >= bottom - band {
                    edgeTotal += 1; if changed { edgeChanged += 1 }
                } else {
                    innerTotal += 1; if changed { innerChanged += 1 }
                }
            }
        }
        guard beforeL.count >= 20 else { return nil }
        let outside = Double(outsideChanged) / Double(max(outsideTotal, 1))
        let edge = Double(edgeChanged) / Double(max(edgeTotal, 1))
        let inner = Double(innerChanged) / Double(max(innerTotal, 1))
        // A ring drawn just outside the control, or at its edge while the
        // inside stays the same. A changed fill reaches the edge too, so it
        // only counts when the inside did not change.
        let hasOutline = outside >= 0.3 || (edge >= 0.5 && inner < 0.3)
        let lb = beforeL.sorted()[beforeL.count / 2], la = afterL.sorted()[afterL.count / 2]
        return FocusCue(hasOutline: hasOutline, stateRatio: (max(la, lb) + 0.05) / (min(la, lb) + 0.05))
    }

    /// Whether the rendered pixels around `node` changed between two screenshots.
    static func focusRegionChanged(before: Data, after: Data?, node: AccessibilityNode, hierarchySize: CGSize) -> Bool {
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

        let beforePixels = Self.pixelBytes(beforeCG, x: x, y: yFromTop, width: w, height: h)
        let afterPixels = Self.pixelBytes(afterCG, x: x, y: yFromTop, width: w, height: h)
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

    // MARK: Focus seen in screenshots (iOS)

    /// Decodes a screenshot once for the comparisons below.
    static func image(_ data: Data?) -> CGImage? {
        guard let data, let image = NSImage(data: data) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Share of sampled pixels around `node` (6 pt margin) that differ
    /// between two screenshots of the same layout.
    static func changeRatio(before: CGImage, after: CGImage, node: AccessibilityNode, hierarchySize: CGSize) -> Double {
        let width = min(before.width, after.width), height = min(before.height, after.height)
        let scaleX = CGFloat(width) / max(1, hierarchySize.width), scaleY = CGFloat(height) / max(1, hierarchySize.height)
        let x = max(0, Int((node.frame.minX - 6) * scaleX)), y = max(0, Int((node.frame.minY - 6) * scaleY))
        let w = min(width - x, Int((node.frame.width + 12) * scaleX)), h = min(height - y, Int((node.frame.height + 12) * scaleY))
        guard w > 1, h > 1,
              let a = pixelBytes(before, x: x, y: y, width: w, height: h),
              let b = pixelBytes(after, x: x, y: y, width: w, height: h), a.count == b.count else { return 0 }
        var changed = 0, samples = 0
        for i in Swift.stride(from: 0, to: a.count, by: 12) {
            samples += 1
            if abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2])) > 24 { changed += 1 }
        }
        return Double(changed) / Double(max(1, samples))
    }

    /// Whether anything on screen changed (a focus ring appeared or moved).
    static func screenChanged(_ before: CGImage, _ after: CGImage) -> Bool {
        let width = min(before.width, after.width), height = min(before.height, after.height)
        guard let a = pixelBytes(before, x: 0, y: 0, width: width, height: height),
              let b = pixelBytes(after, x: 0, y: 0, width: width, height: height) else { return false }
        var changed = 0
        for i in Swift.stride(from: 0, to: a.count, by: 4 * 7) where
            abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2])) > 40 {
            changed += 1
            if changed > 40 { return true }
        }
        return false
    }

    /// Frames of tab, navigation and tool bars: translucent, so their pixels
    /// change with the content behind them.
    static func barControlFrames(in root: AccessibilityNode) -> [CGRect] {
        ProbeNodes.all(in: root)
            .filter { $0.visible && ($0.role == .tabBar || $0.role == .navigationBar || $0.type.contains("Toolbar")) }
            .map(\.frame)
    }

    /// The area that differs between two screenshots, in pixels, below
    /// `ignoreTop` pixels (the status bar's clock). nil: nothing changed.
    static func changedRegion(_ before: CGImage, _ after: CGImage, ignoreTop: Int) -> CGRect? {
        let width = min(before.width, after.width), height = min(before.height, after.height)
        guard height > ignoreTop,
              let a = pixelBytes(before, x: 0, y: ignoreTop, width: width, height: height - ignoreTop),
              let b = pixelBytes(after, x: 0, y: ignoreTop, width: width, height: height - ignoreTop) else { return nil }
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1, changed = 0
        let step = 3
        for y in Swift.stride(from: 0, to: height - ignoreTop, by: step) {
            for x in Swift.stride(from: 0, to: width, by: step) {
                let i = (y * width + x) * 4
                if abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2])) > 40 {
                    changed += 1
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard changed >= 30 else { return nil }
        return CGRect(x: minX, y: minY + ignoreTop, width: maxX - minX + step, height: maxY - minY + step)
    }

    /// The thin band where a focus ring is drawn: 3 pt inside to 6 pt
    /// outside the control's frame, in pixels.
    private static func ringBand(_ node: AccessibilityNode, width: Int, height: Int, hierarchySize: CGSize) -> [(x: Int, y: Int, w: Int, h: Int)] {
        let sx = CGFloat(width) / max(1, hierarchySize.width), sy = CGFloat(height) / max(1, hierarchySize.height)
        let outer = node.frame.insetBy(dx: -6, dy: -6), inner = node.frame.insetBy(dx: 3, dy: 3)
        let rects = [
            CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: inner.minY - outer.minY),
            CGRect(x: outer.minX, y: inner.maxY, width: outer.width, height: outer.maxY - inner.maxY),
            CGRect(x: outer.minX, y: inner.minY, width: inner.minX - outer.minX, height: inner.height),
            CGRect(x: inner.maxX, y: inner.minY, width: outer.maxX - inner.maxX, height: inner.height)
        ]
        return rects.compactMap { rect in
            let x = max(0, Int(rect.minX * sx)), y = max(0, Int(rect.minY * sy))
            let w = min(width - x, Int(rect.width * sx)), h = min(height - y, Int(rect.height * sy))
            return w > 0 && h > 0 ? (x, y, w, h) : nil
        }
    }

    /// The focus ring's colour: the median of the band pixels that changed
    /// when focus arrived.
    static func ringColor(before: CGImage, after: CGImage, node: AccessibilityNode, hierarchySize: CGSize) -> [Int]? {
        var reds: [Int] = [], greens: [Int] = [], blues: [Int] = []
        for band in ringBand(node, width: min(before.width, after.width), height: min(before.height, after.height), hierarchySize: hierarchySize) {
            guard let a = pixelBytes(before, x: band.x, y: band.y, width: band.w, height: band.h),
                  let b = pixelBytes(after, x: band.x, y: band.y, width: band.w, height: band.h) else { continue }
            for i in Swift.stride(from: 0, to: min(a.count, b.count), by: 4) where
                abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2])) > 60 {
                reds.append(Int(b[i])); greens.append(Int(b[i + 1])); blues.append(Int(b[i + 2]))
            }
        }
        guard reds.count >= 20 else { return nil }
        func median(_ values: [Int]) -> Int { values.sorted()[values.count / 2] }
        return [median(reds), median(greens), median(blues)]
    }

    /// Share of a control's ring band drawn in the focus ring's colour.
    static func ringMatch(_ shot: CGImage, node: AccessibilityNode, color: [Int], hierarchySize: CGSize) -> Double {
        var matching = 0, total = 0
        for band in ringBand(node, width: shot.width, height: shot.height, hierarchySize: hierarchySize) {
            guard let pixels = pixelBytes(shot, x: band.x, y: band.y, width: band.w, height: band.h) else { continue }
            for i in Swift.stride(from: 0, to: pixels.count, by: 8) {
                total += 1
                if abs(Int(pixels[i]) - color[0]) + abs(Int(pixels[i + 1]) - color[1]) + abs(Int(pixels[i + 2]) - color[2]) < 60 { matching += 1 }
            }
        }
        return Double(matching) / Double(max(1, total))
    }

    static func pixelBytes(
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
