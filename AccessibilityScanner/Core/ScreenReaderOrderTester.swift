//
//  ScreenReaderOrderTester.swift
//  AccessibilityScanner

import Foundation
import CoreGraphics

@MainActor
final class ScreenReaderOrderTester {

    struct Outcome {
        let evaluations: [AccessibilityRuleEvaluation]
        let skipAll: Bool
    }

    private let appium: AppiumClient
    private let guide: GuidedChecks?

    init(appium: AppiumClient, guide: GuidedChecks?) {
        self.appium = appium
        self.guide = guide
    }

    func test(screen: AccessibilityNode, name: String) async throws -> Outcome {
        let isIOS = appium.platform == .ios
        let reader = isIOS ? "VoiceOver" : "TalkBack"
        let shortcut = isIOS ? "triple-click the side button" : "hold both volume keys"

        if isIOS, let automatic = try await automaticVoiceOver(screen: screen) {
            return Outcome(evaluations: automatic, skipAll: false)
        }
        guard let guide else { return Outcome(evaluations: [], skipAll: false) }

        guard let baseData = try? await appium.getScreenshot(),
              let base = KeyboardFocusTester.image(baseData) else {
            return Outcome(evaluations: [], skipAll: false)
        }
  
        
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccessibilityScanner/ScreenReaderSteps")
            .appendingPathComponent(name.filter { $0.isLetter || $0.isNumber })
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? baseData.write(to: folder.appendingPathComponent("00-before.png"))
        var shots = 0
        let step = GuidedChecks.Step(
            title: "\(reader) reading order",
            message: "On the \"\(name)\" screen: turn on \(reader) (\(shortcut), or in Settings › Accessibility), then swipe right with one finger, once each time this card says Swipe right. When \(reader) reaches the end of the screen, turn \(reader) off and press Done.",
            actions: [GuidedChecks.Action(reply: .skipAll, title: "Skip \(reader) for this scan"),
                      GuidedChecks.Action(reply: .skip, title: "Skip this screen"),
                      GuidedChecks.Action(reply: .done, title: "Done, \(reader) is off")],
            progress: "Turn on \(reader)"
        )
        guide.present(step)

        var last = base
        var previous: CGImage?
        var colour: [Int]?
        var order: [AccessibilityNode] = []
        var lastChange = Date()

        while guide.isWaiting(step.id) {
            try await Task.sleep(nanoseconds: 300_000_000)
            if Date().timeIntervalSince(lastChange) > 120 { guide.finish(.done); break }
            guard guide.isWaiting(step.id),
                  let shot = KeyboardFocusTester.image(try? await appium.getScreenshot()),
                  KeyboardFocusTester.screenChanged(last, shot) else { continue }
            // Let the cursor finish moving (and the screen finish scrolling).
            try await Task.sleep(nanoseconds: 350_000_000)
            let settledData = try? await appium.getScreenshot()
            let settled = KeyboardFocusTester.image(settledData) ?? shot
            shots += 1
            try? settledData?.write(to: folder.appendingPathComponent(String(format: "%02d-step.png", shots)))
            previous = last
            last = settled
            lastChange = Date()
            guard let root = try? appium.makeParser().parse(try await appium.getSource()) else {
                trace("Screen reader step \(shots): page source could not be read", Log.probes)
                continue
            }

            let located = locate(in: root, shot: settled, previous: previous, base: base, colour: &colour)
            trace("Screen reader step \(shots): \(located.map { "\"\(ProbeNodes.clean($0.label))\"" } ?? "no element") colour \(colour.map { "\($0)" } ?? "unknown")", Log.probes)
            if let found = located,
               Self.key(found) != order.last.map(Self.key) {
                order.append(found)
                guide.update(progress: "Recorded \(order.count): \"\(ProbeNodes.clean(found.label))\". Swipe right")
            } else if colour == nil {
                guide.update(progress: "Waiting for the \(reader) cursor. Swipe right")
            }
        }

        let reply = await guide.waitForReply()
        if reply == .skipAll { return Outcome(evaluations: [], skipAll: true) }
        if reply == .skip { return Outcome(evaluations: [], skipAll: false) }
        return Outcome(evaluations: verdict(order: order, screen: screen, reader: reader, spokenCount: nil), skipAll: false)
    }

    // MARK: VoiceOver driven by XCTest (iOS 27+)
    private func automaticVoiceOver(screen: AccessibilityNode) async throws -> [AccessibilityRuleEvaluation]? {
        guard (try? await appium.enableVoiceOver()) != nil else { return nil }
        let appium = appium
        var spoken: [String] = []
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            // VoiceOver starts wherever it lands; back to the first element,
            // where a user starts reading.
            var last = try? await appium.voiceOverCurrentSpeech()
            for _ in 0..<80 {
                try Task.checkCancellation()
                guard let previous = try? await appium.voiceOverMove("backward"), !previous.isEmpty, previous != last else { break }
                last = previous
            }
            if let first = try? await appium.voiceOverCurrentSpeech(), !first.isEmpty { spoken.append(first) }
            var repeats = 0
            for _ in 0..<80 {
                try Task.checkCancellation()
                guard let utterance = try? await appium.voiceOverMove("forward"), !utterance.isEmpty else { break }
                if utterance == spoken.last { repeats += 1; if repeats >= 2 { break } else { continue } }
                if spoken.count > 2, utterance == spoken.first { break }
                repeats = 0
                spoken.append(utterance)
            }
        } catch {
            await DeviceRestore.run { try? await appium.disableVoiceOver() }
            throw error
        }
        await DeviceRestore.run { try? await appium.disableVoiceOver() }
        trace("VoiceOver read \(spoken.count) items: \(spoken.prefix(8).joined(separator: " | "))", Log.probes)

        let elements = readable(in: screen).filter { !ProbeNodes.clean($0.label).isEmpty }
        var order: [AccessibilityNode] = []
        var used = Set<String>()
        for utterance in spoken {
            let said = utterance.lowercased()
            // Its label, then the end of a word: "Tech" is not "Technology".
            let matching = elements.filter { node in
                let label = ProbeNodes.clean(node.label).lowercased()
                guard said.hasPrefix(label) else { return false }
                return said.dropFirst(label.count).first.map { !($0.isLetter || $0.isNumber) } ?? true
            }
            guard let length = matching.map({ ProbeNodes.clean($0.label).count }).max() else { continue }
            // Elements sharing the name (the "Tech" filter and a card's
            // "TECH" tag): the one not read yet that follows what was read
            // last, as VoiceOver reads; else the first on screen.
            let candidates = matching.filter { ProbeNodes.clean($0.label).count == length }
                .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
            let fresh = candidates.filter { !used.contains(Self.key($0)) }
            let previous = order.last
            let chosen = fresh.first { node in previous.map { !VisualOrder.mustPrecedeVertically(node.frame, $0.frame) } ?? true }
                ?? fresh.first ?? candidates.first
            if let chosen {
                used.insert(Self.key(chosen))
                order.append(chosen)
            }
        }
        return verdict(order: order, screen: screen, reader: "VoiceOver", spokenCount: spoken.count)
    }

    // MARK: Following the cursor

    private func readable(in root: AccessibilityNode) -> [AccessibilityNode] {
        let screenArea = root.frame.width * root.frame.height
        return ProbeNodes.all(in: root).filter { node in
            node.visible && node.accessible && node.role != .application &&
                !node.semantics.mergedIntoAncestor &&
                node.frame.width > 0 && node.frame.height > 0 &&
                node.frame.width * node.frame.height < screenArea * 0.5
        }
    }

    private func locate(in root: AccessibilityNode, shot: CGImage, previous: CGImage?, base: CGImage, colour: inout [Int]?) -> AccessibilityNode? {
        let size = root.frame.size
        let candidates = readable(in: root)
        guard let known = colour else {
            let reference = previous ?? base
            guard let first = candidates
                .map({ ($0, KeyboardFocusTester.changeRatio(before: reference, after: shot, node: $0, hierarchySize: size)) })
                .filter({ $0.1 >= 0.015 })
                // The cursor rings one element: the smallest of those that
                // changed most is the one inside it.
                .max(by: { ($0.1, -$0.0.frame.width * $0.0.frame.height) < ($1.1, -$1.0.frame.width * $1.0.frame.height) })?.0,
                  let learned = KeyboardFocusTester.ringColor(before: reference, after: shot, node: first, hierarchySize: size)
            else { return nil }
            colour = learned
            return first
        }
        return candidates
            .map { node -> (AccessibilityNode, Double, Double) in
                let now = KeyboardFocusTester.ringMatch(shot, node: node, color: known, hierarchySize: size)
                let before = previous.map { KeyboardFocusTester.ringMatch($0, node: node, color: known, hierarchySize: size) } ?? 0
                return (node, now, now - before)
            }
            .filter { $0.1 >= KeyboardFocusTester.ringPresent && $0.2 >= KeyboardFocusTester.ringArrived }
            .max { $0.2 < $1.2 }?.0
    }

    private static func key(_ node: AccessibilityNode) -> String {
        [node.type, ProbeNodes.clean(node.identifier), ProbeNodes.clean(node.label),
         "\(Int((node.frame.width / 4).rounded())):\(Int((node.frame.height / 4).rounded()))"].joined(separator: "|")
    }

    // MARK: Verdict

    private func verdict(order: [AccessibilityNode], screen: AccessibilityNode, reader: String, spokenCount: Int?) -> [AccessibilityRuleEvaluation] {
        // Positions from the screen at its top, so elements read after a
        // scroll compare in the same coordinates.
        let topElements = Dictionary(readable(in: screen).map { (Self.key($0), $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let read = order.compactMap { node -> AccessibilityNode? in
            let key = Self.key(node)
            guard seen.insert(key).inserted else { return nil }
            return topElements[key]
        }

        guard read.count >= 3, let assessment = VisualOrder.assess(frames: read.map(\.frame), precedes: VisualOrder.mustPrecedeVertically) else {
            return [ProbeEvaluation.make(
                ruleID: "reading-order", status: .notTested,
                message: spokenCount.map { "\(reader) spoke \($0) item\($0 == 1 ? "" : "s") on this screen, of which \(read.count) could be matched to elements at the top of the screen: too few to judge the reading order." }
                    ?? "Only \(read.count) \(reader) step\(read.count == 1 ? " was" : "s were") seen on this screen, too few to judge the reading order.",
                remediation: "Swipe through the screen with \(reader) and confirm it reads in a logical order.",
                node: screen)]
        }

        let names = read.map { "\"\(ProbeNodes.clean($0.label).prefix(40))\"" }
        if assessment.ratio >= VisualOrder.passThreshold {
            let message = "\(reader) read the screen's \(read.count) elements in visual order (top to bottom): \(names.prefix(4).joined(separator: ", "))…"
            return [
                ProbeEvaluation.make(ruleID: "reading-order", status: .pass, message: message, node: screen),
                ProbeEvaluation.make(ruleID: "screen-reader-focus-order", status: .pass, message: message, node: screen)
            ]
        }

        // The first place it read something that comes earlier on screen.
        var example = ""
        for index in read.indices.dropFirst() where VisualOrder.mustPrecedeVertically(read[index].frame, read[index - 1].frame) {
            example = " For example, it read \(names[index]) after \(names[index - 1]), though \(names[index]) comes first on screen."
            break
        }
        return [
            ProbeEvaluation.make(
                ruleID: "reading-order", status: .fail,
                message: "\(reader) read \(assessment.outOfOrder) of \(read.count) elements out of visual order.\(example)",
                remediation: "Order the elements so the screen reader reads them as they appear (accessibilityElements or view order on iOS, traversalBefore/After on Android).",
                node: screen),
            ProbeEvaluation.make(
                ruleID: "screen-reader-focus-order", status: .validate,
                message: "\(reader) moved through \(read.count) elements in an order that differs from the screen's layout.\(example) Check the order still makes sense.",
                remediation: "Make the screen reader's focus order follow the meaning and layout of the screen.",
                node: screen)
        ]
    }
}
