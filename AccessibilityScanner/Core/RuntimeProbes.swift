//
//  RuntimeProbes.swift
//  AccessibilityScanner


import Foundation
import CoreGraphics
import ImageIO

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

    static func clean(_ text: String) -> String {
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


    static func shortenedText(drawn: String, label: String) -> String? {
        var shown = drawn
        if shown.hasSuffix("…") { shown.removeLast() }
        else if shown.hasSuffix("...") { shown.removeLast(3) }
        else { return nil }
        func normalized(_ text: String) -> String {
            text.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let prefix = normalized(shown), full = normalized(label)
        guard prefix.count >= 3, prefix.count < full.count, full.hasPrefix(prefix) else { return nil }
        return drawn
    }

    static func imageSize(_ data: Data) -> (width: Double, height: Double)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double
        else { return nil }
        return (width, height)
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

        do {
            try await appium.setOrientation(target)
        } catch {
            let text = error.localizedDescription.lowercased()
            if text.contains("unable to rotate") || text.contains("rotate device") {
                return [ProbeEvaluation.make(
                    ruleID: ruleID,
                    status: .fail,
                    message: "The app refused to rotate from \(original.lowercased()) to \(target.lowercased()). The screen is locked in one orientation.",
                    remediation: "Support both orientations unless a single orientation is essential to the content.",
                    node: rootNode
                )]
            }
            return [notTested(rootNode, "The device could not be rotated: \(error.localizedDescription)")]
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

        let status: RuleResultStatus = .validate
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
    /// XPaths of the taps from the app's first screen to the screen under
    /// test, replayed after each relaunch.
    private let route: [String]

    private static let iosCategory = "UICTContentSizeCategoryAccessibilityXXXL"
    private static let androidScale = "2.0"

    init(
        appium: AppiumClient,
        environment: RuntimeProbeEnvironment,
        scanner: AccessibilityScanner = AccessibilityScanner(),
        route: [String] = []
    ) {
        self.appium = appium
        self.environment = environment
        self.scanner = scanner
        self.route = route
    }

    /// Back to the screen under test after a relaunch opened the first one.
    private func replayRoute() async {
        guard !route.isEmpty else { return }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        for xpath in route {
            try? await appium.tapElement(usingXPath: xpath)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
    }

    func test(rootNode: AccessibilityNode) async throws -> [AccessibilityRuleEvaluation] {

        guard environment.allowAppRelaunch else {
            return notTested(
                rootNode,
                "The app was attached without relaunching (Current Page mode or \"Don't relaunch the app\"), and relaunching it with larger text would reset its state."
            )
        }

        let serial = environment.udid
        var originalAndroidScale: String?
        var step = Date()
        func lap(_ name: String) {
            trace("Text size timing: \(name) \(String(format: "%.1f", Date().timeIntervalSince(step)))s", Log.probes)
            step = Date()
        }

        do {
            if environment.platform == .android {
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

        lap("relaunch at large size")
        await replayRoute()
        var largeRoot: AccessibilityNode?
        var largeShot: Data?
        do {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            largeRoot = try await ProbeNodes.readSettledRoot(using: appium)
            let normalTexts = Set(textHeights(in: rootNode).keys)
            var attempts = 0
            while let current = largeRoot, normalTexts.count >= 3,
                  Set(textHeights(in: current).keys).intersection(normalTexts).count < 3, attempts < 4 {
                attempts += 1
                try await Task.sleep(nanoseconds: 2_000_000_000)
                largeRoot = (try? appium.makeParser().parse(try await appium.getSource())) ?? current
            }
            largeShot = try? await appium.getScreenshot()
        } catch {
            await restore(originalAndroidScale: originalAndroidScale)
            throw error
        }

        lap("read large layout")
        await restore(originalAndroidScale: originalAndroidScale)
        await replayRoute()
        lap("restore normal size")

        guard let largeRoot else {
            return notTested(rootNode, "The hierarchy could not be read at the larger text size.")
        }

        var results = evaluate(normal: rootNode, large: largeRoot)
        lap("resize and clipping rules")
        results += Self.truncation(normal: rootNode, large: largeRoot, screenshot: largeShot)
        lap("truncation text recognition")
        results += Self.overlap(normal: rootNode, large: largeRoot)
        return results
    }

    // MARK: Truncation and overlap (BB40033)
    static func truncation(normal: AccessibilityNode, large: AccessibilityNode, screenshot: Data?) -> [AccessibilityRuleEvaluation] {
        guard let screenshot, let size = ProbeNodes.imageSize(screenshot) else {
            return [ProbeEvaluation.make(ruleID: "text-truncation", status: .notTested,
                                         message: "No screenshot could be taken at the largest text size, so shortened text could not be checked.",
                                         remediation: "Set the largest text size and confirm no text ends with \"…\".", node: normal)]
        }
        let context = AccessibilityRuleContext(
            screenshotData: screenshot, screenshotWidth: size.width, screenshotHeight: size.height,
            hierarchyWidth: large.frame.width, hierarchyHeight: large.frame.height
        )
        let texts = ProbeNodes.all(in: large).filter {
            $0.role == .staticText && $0.visible && !$0.semantics.partiallyVisible &&
                ProbeNodes.clean($0.label).count >= 6 && $0.frame.height >= 8
        }.prefix(60)

        var truncated: [String] = []
        for text in texts {
            let label = ProbeNodes.clean(text.label)
            guard !label.contains("…"), !label.hasSuffix("..."),
                  let drawn = TextRecognizer.text(in: text.frame, context: context)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            else { continue }
            if let shown = ProbeNodes.shortenedText(drawn: drawn, label: label) {
                truncated.append("\"\(shown)\" (full text: \"\(label)\")")
            }
        }

        if truncated.isEmpty {
            return [ProbeEvaluation.make(ruleID: "text-truncation", status: .pass,
                                         message: "No text was shortened with an ellipsis at the largest text size (\(texts.count) text elements read).",
                                         node: normal)]
        }
        return [ProbeEvaluation.make(ruleID: "text-truncation", status: .fail,
                                     message: "\(truncated.count) text element\(truncated.count == 1 ? " is" : "s are") shortened with an ellipsis at the largest text size, so part of the text cannot be read (for example: \(truncated.prefix(2).joined(separator: "; "))).",
                                     remediation: "Let the text wrap onto more lines (lineLimit(nil) / maxLines unset) instead of truncating it.",
                                     node: normal)]
    }

    static func overlap(normal: AccessibilityNode, large: AccessibilityNode) -> [AccessibilityRuleEvaluation] {
        func texts(_ root: AccessibilityNode) -> [AccessibilityNode] {
            ProbeNodes.all(in: root).filter {
                $0.role == .staticText && $0.visible && !$0.semantics.partiallyVisible &&
                    !ProbeNodes.clean($0.label).isEmpty && $0.frame.width > 0 && $0.frame.height > 0
            }
        }
        func overlapping(_ a: CGRect, _ b: CGRect) -> Bool {
            let inter = a.intersection(b)
            guard !inter.isNull, inter.width > 1, inter.height > 1 else { return false }
            let smaller = min(a.width * a.height, b.width * b.height)
            return inter.width * inter.height >= smaller * 0.2 && !a.contains(b) && !b.contains(a)
        }
        let normalFrames = Dictionary(texts(normal).map { (ProbeNodes.clean($0.label), $0.frame) }, uniquingKeysWith: { first, _ in first })
        let largeTexts = texts(large)

        var pairs: [String] = []
        for i in largeTexts.indices {
            for j in largeTexts.indices where j > i {
                let a = largeTexts[i], b = largeTexts[j]
                let labelA = ProbeNodes.clean(a.label), labelB = ProbeNodes.clean(b.label)
                guard labelA != labelB, overlapping(a.frame, b.frame) else { continue }
                // Already overlapping at normal size: a design choice (a
                // badge on a title), not caused by scaling.
                if let na = normalFrames[labelA], let nb = normalFrames[labelB], overlapping(na, nb) { continue }
                pairs.append("\"\(labelA)\" and \"\(labelB)\"")
            }
        }

        if pairs.isEmpty {
            return [ProbeEvaluation.make(ruleID: "text-overlap", status: .pass,
                                         message: "No text overlapped other text at the largest text size.",
                                         node: normal)]
        }
        return [ProbeEvaluation.make(ruleID: "text-overlap", status: .fail,
                                     message: "\(pairs.count) pair\(pairs.count == 1 ? "" : "s") of text overlap at the largest text size (for example: \(pairs.prefix(2).joined(separator: "; "))).",
                                     remediation: "Let containers grow with the text (no fixed heights) so scaled text pushes other content down instead of drawing over it.",
                                     node: normal)]
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
            let normalNodes = Dictionary(
                ProbeNodes.all(in: normal)
                    .filter { $0.visible && $0.role == .staticText && !ProbeNodes.clean($0.label).isEmpty }
                    .map { (ProbeNodes.clean($0.label), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            if median >= 1.3 {
                for (label, normalHeight) in before {
                    guard let largeHeight = after[label], normalHeight > 0,
                          largeHeight / normalHeight < 1.1,
                          let node = normalNodes[ProbeNodes.clean(label)] else { continue }
                    results.append(ProbeEvaluation.make(
                        ruleID: "text-resize",
                        status: .fail,
                        message: "\"\(ProbeNodes.clean(label))\" stayed the same size at the largest text size while other text grew \(String(format: "%.1f", median))×, so it uses a fixed font size.",
                        remediation: "Use a scalable font for this text (UIFontMetrics / preferredFont with adjustsFontForContentSizeCategory, or Dynamic Type in SwiftUI).",
                        node: node
                    ))
                }
            }
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
                // Each text measured growing at both sizes passes on its own
                // element, with how much it grew.
                var grown: [AccessibilityRuleEvaluation] = []
                for (label, normalHeight) in before.sorted(by: { $0.key < $1.key }) {
                    guard let largeHeight = after[label], normalHeight > 0,
                          largeHeight / normalHeight >= 1.1,
                          let node = normalNodes[ProbeNodes.clean(label)] else { continue }
                    grown.append(ProbeEvaluation.make(
                        ruleID: "text-resize",
                        status: .pass,
                        message: "\"\(ProbeNodes.clean(label))\" grew \(String(format: "%.1f", Double(largeHeight / normalHeight)))× at the largest text size.",
                        node: node
                    ))
                }
                results += grown.isEmpty
                    ? [ProbeEvaluation.make(
                        ruleID: "text-resize",
                        status: .pass,
                        message: "Text grew at the largest text size (median size change \(String(format: "%.2f", median))x across \(ratios.count) elements).",
                        node: normal
                    )]
                    : grown
            }
        }

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
        ["text-resize", "text-clipping", "text-truncation", "text-overlap"].map {
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

        if ProbeNodes.contentScrolled(from: before, to: afterSlide) {
            try? await appium.pressAndSlideAway(from: end, to: start)
            try? await Task.sleep(nanoseconds: 500_000_000)
            return []
        }

        if ProbeNodes.contentSignature(in: afterSlide) != beforeSignature {
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
