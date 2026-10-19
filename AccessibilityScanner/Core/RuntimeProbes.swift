//
//  RuntimeProbes.swift
//  AccessibilityScanner


import Foundation
import CoreGraphics

// MARK: - Environment

struct RuntimeProbeEnvironment {
    let bundleID: String
    let platform: MobilePlatform
    let udid: String
    let allowAppRelaunch: Bool
    let allowAppInteraction: Bool
}

// MARK: - Shared helpers

enum ProbeEvaluation {

    static func make(
        ruleID: String,
        status: RuleResultStatus,
        message: String,
        remediation: String = "",
        node: AccessibilityNode
    ) -> AccessibilityRuleEvaluation {
        let rule = AccessibilityRules.all.first { $0.id == ruleID }

        let severity: AccessibilityFinding.Severity
        switch status {
        case .fail: severity = .error
        case .pass: severity = .info
        default: severity = .warning
        }

        return AccessibilityRuleEvaluation(
            ruleID: ruleID,
            ruleName: rule?.title ?? ruleID,
            ruleDescription: rule?.description ?? "",
            status: status,
            severity: severity,
            message: message,
            remediation: remediation,
            node: node
        )
    }
}

enum ProbeNodes {

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func all(in root: AccessibilityNode) -> [AccessibilityNode] {
        var result: [AccessibilityNode] = []
        func visit(_ node: AccessibilityNode) {
            if node.exists { result.append(node) }
            for child in node.children { visit(child) }
        }
        visit(root)
        return result
    }

    /// Visible text and control labels, used to compare two layouts.
    static func contentLabels(in root: AccessibilityNode) -> Set<String> {
        var labels = Set<String>()
        for node in all(in: root) {
            guard node.visible,
                  AccessibilityRole.controls.contains(node.role) ||
                    AccessibilityRole.textual.contains(node.role)
            else { continue }
            let label = clean(node.label)
            if !label.isEmpty { labels.insert(label) }
        }
        return labels
    }

    /// Finds the same element again in a later snapshot.
    static func find(_ target: AccessibilityNode, in root: AccessibilityNode) -> AccessibilityNode? {
        let identifier = clean(target.identifier)
        let label = clean(target.label)
        return all(in: root).first { node in
            guard node.type == target.type else { return false }
            if !identifier.isEmpty { return clean(node.identifier) == identifier }
            return !label.isEmpty && clean(node.label) == label
        }
    }

    /// Visible named elements plus controls. Flutter builds its accessibility
    /// tree only once something asks for it, so the first reads after a
    /// launch can be nearly empty.
    /// The same content is still on screen, shifted by one common offset:
    /// a scroll, not a change caused by activating something.
    static func contentScrolled(from before: AccessibilityNode, to after: AccessibilityNode) -> Bool {
        func positions(_ root: AccessibilityNode) -> [String: CGPoint] {
            var result: [String: CGPoint] = [:]
            var duplicates = Set<String>()
            for node in all(in: root) where node.visible && !clean(node.label).isEmpty {
                let key = node.type + "|" + clean(node.label)
                if result[key] != nil { duplicates.insert(key) }
                result[key] = node.frame.origin
            }
            duplicates.forEach { result[$0] = nil }
            return result
        }
        let old = positions(before), new = positions(after)
        let shared = old.keys.filter { new[$0] != nil }
        guard old.count >= 4, Double(shared.count) / Double(old.count) >= 0.4 else { return false }

        let shifts = shared.map { CGPoint(x: new[$0]!.x - old[$0]!.x, y: new[$0]!.y - old[$0]!.y) }
        let dy = shifts.map(\.y).sorted()[shifts.count / 2]
        let dx = shifts.map(\.x).sorted()[shifts.count / 2]
        guard abs(dy) > 4 || abs(dx) > 4 else { return false }
        let moved = shifts.filter { abs($0.y - dy) < 3 && abs($0.x - dx) < 3 }.count
        return Double(moved) / Double(shifts.count) >= 0.6
    }

    static func meaningfulCount(in root: AccessibilityNode) -> Int {
        all(in: root).filter { node in
            node.visible && (!clean(node.label).isEmpty || AccessibilityRole.controls.contains(node.role))
        }.count
    }

    /// Re-reads the hierarchy while it exposes almost nothing, up to ~8 s.
    static func readSettledRoot(using appium: AppiumClient) async throws -> AccessibilityNode? {
        var root = try? appium.makeParser().parse(try await appium.getSource())
        var attempts = 0
        while let current = root, meaningfulCount(in: current) < 3, attempts < 4 {
            attempts += 1
            try await Task.sleep(nanoseconds: 2_000_000_000)
            root = try? appium.makeParser().parse(try await appium.getSource())
        }
        return root
    }

    static func probeKey(_ node: AccessibilityNode) -> String {
        [node.type, clean(node.identifier), clean(node.label)].joined(separator: "|")
    }

    /// Value plus checked/selected tokens: what changes when a control toggles.
    static func stateSignature(_ node: AccessibilityNode) -> String {
        var tokens: [String] = [clean(node.value ?? "")]
        let traits = node.traits.lowercased()
        for token in ["checked", "selected", "on"] where traits.contains(token) {
            tokens.append(token)
        }
        return tokens.joined(separator: "|")
    }
}

// MARK: - Orientation (BB40055, BB40056)

final class OrientationProbe {

    private let appium: AppiumClient
    private let ruleID = "orientation-support"

    init(appium: AppiumClient) {
        self.appium = appium
    }

    func test(rootNode: AccessibilityNode) async throws -> [AccessibilityRuleEvaluation] {

        guard let original = try? await appium.getOrientation() else {
            return [notTested(rootNode, "The driver did not report the device orientation.")]
        }

        let target = original == "LANDSCAPE" ? "PORTRAIT" : "LANDSCAPE"

        guard (try? await appium.setOrientation(target)) != nil else {
            return [notTested(rootNode, "The driver refused to rotate the device.")]
        }

        var rotated = original
        var rotatedSource: String?

        do {
            try await Task.sleep(nanoseconds: 800_000_000)
            rotated = (try? await appium.getOrientation()) ?? original
            if rotated != original {
                rotatedSource = try? await appium.getSource()
            }
        } catch {
            await restore(original)
            throw error
        }

        // Always put the device back the way it was.
        await restore(original)

        guard rotated != original else {
            return [
                ProbeEvaluation.make(
                    ruleID: ruleID,
                    status: .fail,
                    message: "The screen stayed in \(original.lowercased()) when the device was rotated to \(target.lowercased()). The screen is locked in one orientation.",
                    remediation: "Support both orientations unless a single orientation is essential to the content.",
                    node: rootNode
                )
            ]
        }

        guard let rotatedSource,
              let rotatedRoot = try? appium.makeParser().parse(rotatedSource)
        else {
            return [notTested(rootNode, "The rotated hierarchy could not be read.")]
        }

        let before = ProbeNodes.contentLabels(in: rootNode)
        let after = ProbeNodes.contentLabels(in: rotatedRoot)
        guard !before.isEmpty else { return [] }

        let missing = before.subtracting(after)
        let ratio = Double(missing.count) / Double(before.count)
        let sample = missing.sorted().prefix(3).joined(separator: ", ")

        if ratio <= 0.2 {
            return [
                ProbeEvaluation.make(
                    ruleID: ruleID,
                    status: .pass,
                    message: "The screen rotated to \(target.lowercased()) and \(before.count - missing.count) of \(before.count) text and control labels stayed available.",
                    node: rootNode
                )
            ]
        }

        let status: RuleResultStatus = ratio <= 0.5 ? .warning : .fail
        return [
            ProbeEvaluation.make(
                ruleID: ruleID,
                status: status,
                message: "\(missing.count) of \(before.count) text and control labels are not exposed in \(target.lowercased()) (for example: \(sample)). Some may only be scrolled off-screen.",
                remediation: "Make sure all content and controls remain available, or reachable by scrolling, in both orientations.",
                node: rootNode
            )
        ]
    }

    private func restore(_ original: String) async {
        await DeviceRestore.run {
            do {
                try await self.appium.setOrientation(original)
            } catch {
                trace("Could not restore orientation \(original): \(error.localizedDescription)", Log.probes)
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
    }

    private func notTested(_ node: AccessibilityNode, _ reason: String) -> AccessibilityRuleEvaluation {
        ProbeEvaluation.make(
            ruleID: ruleID,
            status: .notTested,
            message: "Orientation was not tested. \(reason)",
            remediation: "Rotate the device manually and compare the content in both orientations.",
            node: node
        )
    }
}

// MARK: - State after interaction (BB40067 to BB40070)

final class StateUpdateProbe {

    private let appium: AppiumClient
    private let ruleID = "state-updates-after-interaction"
    private let maximumControls: Int
    private let alreadyTested: Set<String>

    /// Probe keys of the controls this run activated.
    private(set) var testedKeys = Set<String>()

    init(appium: AppiumClient, maximumControls: Int = 3, alreadyTested: Set<String> = []) {
        self.appium = appium
        self.maximumControls = maximumControls
        self.alreadyTested = alreadyTested
    }

    /// Only switches and checkboxes are activated: they are the controls whose
    /// state change is visible and that are safe to toggle and put back.
    /// Every control is tapped a second time whatever the hierarchy showed: a
    /// toggle that flipped without updating its accessibility state is flipped
    /// back, and one that ignores taps is unaffected.
    func test(rootNode: AccessibilityNode) async throws -> [AccessibilityRuleEvaluation] {

        let candidates = ProbeNodes.all(in: rootNode)
            .filter {
                ($0.role == .toggle || $0.role == .checkBox) &&
                $0.visible && $0.enabled &&
                ActionSafety.isSafeToActivate($0) &&
                !alreadyTested.contains(ProbeNodes.probeKey($0)) &&
                NavigationAction(node: $0).xpath != nil
            }
            .prefix(maximumControls)

        var results: [AccessibilityRuleEvaluation] = []

        for control in candidates {
            try Task.checkCancellation()
            testedKeys.insert(ProbeNodes.probeKey(control))

            guard let xpath = NavigationAction(node: control).xpath else { continue }
            let name = control.hasAccessibleName ? control.label : control.identifier
            let before = ProbeNodes.stateSignature(control)
            let switchPoint = Self.switchPoint(of: control)
            let beforeShot = try? await appium.getScreenshot()

            // A SwiftUI Toggle row only toggles on the switch itself; its
            // label area ignores taps.
            func activate() async throws {
                if let switchPoint {
                    try await appium.tap(at: switchPoint)
                } else {
                    try await appium.tapElement(usingXPath: xpath)
                }
            }

            do {
                try await activate()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                results.append(
                    ProbeEvaluation.make(
                        ruleID: ruleID,
                        status: .notTested,
                        message: "\"\(name)\" could not be activated: \(error.localizedDescription)",
                        remediation: "Activate the control manually and confirm its state changes.",
                        node: control
                    )
                )
                continue
            }

            // The control was tapped: read its new state, then always put it
            // back, even if reading failed or the scan was stopped.
            var updated: AccessibilityNode?
            var updatedRoot: AccessibilityNode?
            var readError: Error?
            var afterShot: Data?
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                afterShot = try? await appium.getScreenshot()
                let source = try await appium.getSource()
                let root = try appium.makeParser().parse(source)
                updatedRoot = root
                updated = ProbeNodes.find(control, in: root)
            } catch {
                readError = error
            }

            await DeviceRestore.run {
                try? await activate()
                try? await Task.sleep(nanoseconds: 400_000_000)
            }

            if readError is CancellationError { throw CancellationError() }

            guard let updated else {
                results.append(
                    ProbeEvaluation.make(
                        ruleID: ruleID,
                        status: .notTested,
                        message: readError.map { "The state of \"\(name)\" could not be read after it was activated: \($0.localizedDescription)" }
                            ?? "\"\(name)\" could not be found again after it was activated, so its state could not be compared.",
                        remediation: "Activate the control manually and confirm its state changes.",
                        node: control
                    )
                )
                continue
            }

            if ProbeNodes.stateSignature(updated) != before {
                results.append(
                    ProbeEvaluation.make(
                        ruleID: ruleID,
                        status: .pass,
                        message: "The state of \"\(name)\" changed after it was activated.",
                        node: control
                    )
                )
            } else if let beforeShot,
                      !KeyboardFocusTester.focusRegionChanged(
                        before: beforeShot, after: afterShot, node: control,
                        hierarchySize: (updatedRoot ?? rootNode).frame.size) {
                // Nothing changed on screen either: the tap did not reach the
                // control, so there is no evidence of a defect.
                results.append(
                    ProbeEvaluation.make(
                        ruleID: ruleID,
                        status: .notTested,
                        message: "Tapping \"\(name)\" changed neither its appearance nor its state, so the tap may not have reached it.",
                        remediation: "Toggle the control manually and confirm VoiceOver/TalkBack announces the new state.",
                        node: control
                    )
                )
            } else {
                results.append(
                    ProbeEvaluation.make(
                        ruleID: ruleID,
                        status: .fail,
                        message: "\"\(name)\" changed on screen when activated, but its state in the accessibility hierarchy did not change, so screen readers announce the old state.",
                        remediation: "Update the control's value/selected/checked state when the user activates it.",
                        node: control
                    )
                )
            }
        }

        return results
    }

    /// Where to tap a toggle: its inner switch, or the trailing end of a
    /// wide toggle row (the switch sits there). nil: tap the element.
    private static func switchPoint(of control: AccessibilityNode) -> CGPoint? {
        if let inner = ProbeNodes.all(in: control).dropFirst().first(where: { $0.role == .toggle && $0.visible }) {
            return CGPoint(x: inner.frame.midX, y: inner.frame.midY)
        }
        guard control.role == .toggle, control.frame.width > control.frame.height * 3 else { return nil }
        return CGPoint(x: control.frame.maxX - 26, y: control.frame.midY)
    }
}

// MARK: - Large text (BB40031 to BB40033)

final class TextSizeProbe {

    private let appium: AppiumClient
    private let environment: RuntimeProbeEnvironment
    private let scanner: AccessibilityScanner

    private static let iosCategory = "UICTContentSizeCategoryAccessibilityXXXL"
    private static let androidScale = "2.0"

    init(
        appium: AppiumClient,
        environment: RuntimeProbeEnvironment,
        scanner: AccessibilityScanner = AccessibilityScanner()
    ) {
        self.appium = appium
        self.environment = environment
        self.scanner = scanner
    }

    func test(rootNode: AccessibilityNode) async throws -> [AccessibilityRuleEvaluation] {

        guard environment.allowAppRelaunch else {
            return notTested(
                rootNode,
                "The app was attached in Current Page mode and relaunching it with larger text would lose the open page."
            )
        }

        let serial = environment.udid
        var originalAndroidScale: String?

        do {
            if environment.platform == .android {
                // An earlier run that never restored this device left its
                // font scale changed: its recorded original is the real one.
                if let outstanding = AndroidFontScaleRecovery.outstanding(serial: environment.udid) {
                    originalAndroidScale = outstanding
                } else {
                    originalAndroidScale = try await ProcessRunner.offMain {
                        try AndroidDeviceService().fontScale(serial: serial)
                    }
                }
                AndroidFontScaleRecovery.remember(serial: serial, original: originalAndroidScale)
                let largeScale = Self.androidScale
                try await ProcessRunner.offMain {
                    try AndroidDeviceService().setFontScale(serial: serial, value: largeScale)
                }
                try? await appium.terminateApp(bundleID: environment.bundleID)
                await appium.activateApp(bundleID: environment.bundleID)
            } else {
                try? await appium.terminateApp(bundleID: environment.bundleID)
                try await appium.launchApp(
                    bundleID: environment.bundleID,
                    arguments: ["-UIPreferredContentSizeCategoryName", Self.iosCategory]
                )
            }
        } catch {
            await restore(originalAndroidScale: originalAndroidScale)
            return notTested(rootNode, "Larger text could not be applied: \(error.localizedDescription)")
        }

        var largeRoot: AccessibilityNode?
        do {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            largeRoot = try await ProbeNodes.readSettledRoot(using: appium)
        } catch {
            await restore(originalAndroidScale: originalAndroidScale)
            throw error
        }

        await restore(originalAndroidScale: originalAndroidScale)

        guard let largeRoot else {
            return notTested(rootNode, "The hierarchy could not be read at the larger text size.")
        }

        return evaluate(normal: rootNode, large: largeRoot)
    }

    // MARK: Evaluation

    private func evaluate(
        normal: AccessibilityNode,
        large: AccessibilityNode
    ) -> [AccessibilityRuleEvaluation] {

        let before = textHeights(in: normal)
        let after = textHeights(in: large)

        var ratios: [Double] = []
        for (label, normalHeight) in before {
            if let largeHeight = after[label], normalHeight > 0 {
                ratios.append(Double(largeHeight / normalHeight))
            }
        }

        var results: [AccessibilityRuleEvaluation] = []

        if ratios.count < 3 {
            results.append(
                ProbeEvaluation.make(
                    ruleID: "text-resize",
                    status: .validate,
                    message: "The larger text size was applied but fewer than three text elements could be matched between the two layouts, so the result is inconclusive.",
                    remediation: "Open the app at the largest text size and confirm text grows and stays readable.",
                    node: normal
                )
            )
        } else {
            let median = ratios.sorted()[ratios.count / 2]
            if median < 1.15 {
                results.append(
                    ProbeEvaluation.make(
                        ruleID: "text-resize",
                        status: .fail,
                        message: "Text did not grow at the largest text size (median size change \(String(format: "%.2f", median))x across \(ratios.count) elements).",
                        remediation: "Use scalable text (Dynamic Type on iOS, sp units on Android) instead of fixed font sizes.",
                        node: normal
                    )
                )
            } else {
                results.append(
                    ProbeEvaluation.make(
                        ruleID: "text-resize",
                        status: .pass,
                        message: "Text grew at the largest text size (median size change \(String(format: "%.2f", median))x across \(ratios.count) elements).",
                        node: normal
                    )
                )
            }
        }

        // Clipping at the larger size, summarised on the normal screen so the
        // annotation never points at the wrong layout.
        let clipped = scanner.evaluateForReport(rootNode: large)
            .filter { $0.ruleID == "text-clipping" && $0.status == .fail }

        if clipped.isEmpty {
            results.append(
                ProbeEvaluation.make(
                    ruleID: "text-clipping",
                    status: .pass,
                    message: "No clipped text was detected at the largest text size.",
                    node: normal
                )
            )
        } else {
            let sample = clipped.prefix(3).map { "\"\($0.elementLabel)\"" }.joined(separator: ", ")
            results.append(
                ProbeEvaluation.make(
                    ruleID: "text-clipping",
                    status: .fail,
                    message: "\(clipped.count) text element\(clipped.count == 1 ? "" : "s") clipped at the largest text size (for example: \(sample)).",
                    remediation: "Let text wrap or the container grow so no text is cut off at larger text sizes.",
                    node: normal
                )
            )
        }

        return results
    }

    private func textHeights(in root: AccessibilityNode) -> [String: CGFloat] {
        var heights: [String: CGFloat] = [:]
        for node in ProbeNodes.all(in: root) {
            guard node.visible, node.role == .staticText, node.frame.height > 0 else { continue }
            let label = node.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty, heights[label] == nil {
                heights[label] = node.frame.height
            }
        }
        return heights
    }

    // MARK: Restore

    private func restore(originalAndroidScale: String?) async {
        let environment = environment
        let appium = appium
        await DeviceRestore.run {
            if environment.platform == .android {
                do {
                    try await ProcessRunner.offMain {
                        try AndroidDeviceService().setFontScale(
                            serial: environment.udid,
                            value: originalAndroidScale
                        )
                    }
                    AndroidFontScaleRecovery.markRestored(serial: environment.udid)
                } catch {
                    // Kept as outstanding: restored at the next launch or scan.
                    trace("Could not restore Android font scale: \(error.localizedDescription)", Log.probes)
                }
                try? await appium.terminateApp(bundleID: environment.bundleID)
                await appium.activateApp(bundleID: environment.bundleID)
            } else {
                try? await appium.terminateApp(bundleID: environment.bundleID)
                try? await appium.launchApp(bundleID: environment.bundleID, arguments: [])
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
    }

    private func notTested(
        _ node: AccessibilityNode,
        _ reason: String
    ) -> [AccessibilityRuleEvaluation] {
        ["text-resize", "text-clipping"].map {
            ProbeEvaluation.make(
                ruleID: $0,
                status: .notTested,
                message: "Larger text was not tested. \(reason)",
                remediation: "Set the device to its largest text size and review the app manually.",
                node: node
            )
        }
    }
}

// MARK: - Pointer cancellation (BB40136, BB40137)
final class PointerCancellationProbe {

    private let appium: AppiumClient
    private let ruleID = "touch-up-cancellation"
    private let alreadyTested: Set<String>

    private(set) var testedKeys = Set<String>()

    init(appium: AppiumClient, alreadyTested: Set<String> = []) {
        self.appium = appium
        self.alreadyTested = alreadyTested
    }

    func test(rootNode: AccessibilityNode) async throws -> [AccessibilityRuleEvaluation] {
        let screen = rootNode.frame
        // Tab and bottom-bar buttons switch screens, so they cannot show
        // cancellation and would move the crawl off this screen.
        let bottomBarTop = screen.minY + screen.height * 0.85
        guard let control = ProbeNodes.all(in: rootNode).first(where: { node in
            node.role == .button && node.visible && node.enabled &&
            node.frame.minY < bottomBarTop && !node.type.contains("TabBar") &&
            ActionSafety.isSafeToExplore(node) &&
            !alreadyTested.contains(ProbeNodes.probeKey(node)) &&
            node.frame.width >= 24 && node.frame.height >= 24 &&
            NavigationAction(node: node).xpath != nil
        }) else { return [] }

        testedKeys.insert(ProbeNodes.probeKey(control))
        let name = control.hasAccessibleName ? control.label : control.identifier
        let start = CGPoint(x: control.frame.midX, y: control.frame.midY)
        // Slide well outside the control, staying on screen.
        let end = CGPoint(
            x: start.x,
            y: start.y > screen.midY ? max(screen.minY + 10, control.frame.minY - 160) : min(screen.maxY - 10, control.frame.maxY + 160)
        )

        guard let before = try? await currentRoot() else { return [] }
        let beforeLabels = ProbeNodes.contentLabels(in: before)
        let beforeSignature = ProbeNodes.contentSignature(in: before)

        try await appium.pressAndSlideAway(from: start, to: end)
        try await Task.sleep(nanoseconds: 700_000_000)
        guard let afterSlide = try? await currentRoot() else { return [] }

        // In a scrolling screen the slide scrolls the content: the
        // platform then cancels the touch, which says nothing about
        // touch-down activation. Put the content back and report nothing.
        if ProbeNodes.contentScrolled(from: before, to: afterSlide) {
            try? await appium.pressAndSlideAway(from: end, to: start)
            try? await Task.sleep(nanoseconds: 500_000_000)
            return []
        }

        if ProbeNodes.contentSignature(in: afterSlide) != beforeSignature {
            // Sliding back restores a scrolled screen but not a screen the
            // control navigated to: only the latter is touch-down activation.
            try? await appium.pressAndSlideAway(from: end, to: start)
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let back = try? await currentRoot() {
                let restored = ProbeNodes.contentLabels(in: back)
                let shared = Double(beforeLabels.intersection(restored).count) / Double(max(beforeLabels.count, 1))
                if shared >= 0.8 { return [] }
            }
            await restore(from: afterSlide, baselineLabels: beforeLabels)
            return [ProbeEvaluation.make(
                ruleID: ruleID,
                status: .fail,
                message: "Pressing \"\(name)\" and sliding off before releasing still triggered it, so the action fires on touch down and cannot be cancelled.",
                remediation: "Trigger the action on touch up inside the control (the platform default) so users can slide away to cancel.",
                node: control
            )]
        }

        // Nothing happened. Check that a normal tap does something.
        guard let xpath = NavigationAction(node: control).xpath,
              (try? await appium.tapElement(usingXPath: xpath)) != nil else { return [] }
        try await Task.sleep(nanoseconds: 700_000_000)
        guard let afterTap = try? await currentRoot() else { return [] }
        guard ProbeNodes.contentSignature(in: afterTap) != beforeSignature else { return [] }
        await restore(from: afterTap, baselineLabels: beforeLabels)

        return [ProbeEvaluation.make(
            ruleID: ruleID,
            status: .pass,
            message: "Sliding off \"\(name)\" before releasing cancelled it, and a normal tap activated it.",
            node: control
        )]
    }

    private func currentRoot() async throws -> AccessibilityNode {
        try appium.makeParser().parse(try await appium.getSource())
    }

    private func restore(from root: AccessibilityNode, baselineLabels: Set<String>) async {
        guard !baselineLabels.isEmpty else { return }
        let missing = Double(baselineLabels.subtracting(ProbeNodes.contentLabels(in: root)).count) / Double(baselineLabels.count)
        guard missing > 0.5 else { return }
        await DeviceRestore.run {
            try? await self.appium.goBack()
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
    }
}
