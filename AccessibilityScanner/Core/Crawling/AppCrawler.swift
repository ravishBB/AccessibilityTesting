//
//  AppCrawler.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 25/09/26.
//

import Foundation
import CoreGraphics
import AppKit

nonisolated struct ScrollableViewportCapture {
    let snapshot: StableScanSnapshot
    let evaluations: [AccessibilityRuleEvaluation]
}

nonisolated struct CrawledScreen {
    let signature: String
    let rootNode: AccessibilityNode

    let evaluations: [AccessibilityRuleEvaluation]
    let screenshotEvaluations: [AccessibilityRuleEvaluation]

    let actions: [NavigationAction]
    var transitions: [NavigationTransition]

    let screenshotData: Data
    let screenshotWidth: Double
    let screenshotHeight: Double
    let viewportCaptures: [ScrollableViewportCapture]
    let keyboardFocusEvaluations: [AccessibilityRuleEvaluation]
}

nonisolated struct ScrollableScreenScanResult {
    
    let topSnapshot: StableScanSnapshot
    let evaluations: [AccessibilityRuleEvaluation]
    let topEvaluations: [AccessibilityRuleEvaluation]
    let viewportCaptures: [ScrollableViewportCapture]
    let viewportCount: Int
}

struct AppCrawlerConfiguration {

    let maximumScreens: Int
    let maximumDepth: Int
    let maximumActionsPerScreen: Int
    let settleDelayNanoseconds: UInt64

    static let `default` =
        AppCrawlerConfiguration(
            maximumScreens: 100,
            maximumDepth: 20,
            maximumActionsPerScreen: 30,
            settleDelayNanoseconds: 500_000_000
        )
}

final class AppCrawler {

    private let appium: AppiumClient
    private let scanner: AccessibilityScanner
    private let configuration: AppCrawlerConfiguration
    private let probeEnvironment: RuntimeProbeEnvironment?
    private let notes: ScanNotes

    private var visitedScreens:
        Set<String> = []

    private var discoveredScreens:
        [CrawledScreen] = []

    private var exploredSharedActions = Set<String>()
    private var firstScreenSharedActions = Set<String>()
    private var probedControlKeys = Set<String>()

    private var orientationProbed = false
    private var pointerCancellationRuns = 0
    private let pointerCancellationScreens = 2
    private var isLost = false

    /// Every label seen on a scanned screen, at all its scroll positions:
    /// returning to a screen often lands part-way down it.
    private var screenContentLabels: [String: Set<String>] = [:]
    
    private static let overlayPackages: Set<String> = [
        "com.android.permissioncontroller",
        "com.google.android.permissioncontroller",
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
        "com.android.systemui"
    ]

    init(
        appium: AppiumClient,
        scanner: AccessibilityScanner = AccessibilityScanner(),
        configuration: AppCrawlerConfiguration =
            .default,
        notes: ScanNotes = ScanNotes(),
        probeEnvironment: RuntimeProbeEnvironment? = nil
    ) {
        self.notes = notes

        self.appium = appium
        self.scanner = scanner
        self.configuration = configuration
        self.probeEnvironment = probeEnvironment
    }

    func crawl(
        initialSnapshot: StableScanSnapshot,
        statusHandler: @escaping (String) -> Void,
        screenHandler: ((CrawledScreen) -> Void)? = nil
    ) async throws -> [CrawledScreen] {

        visitedScreens.removeAll()
        exploredSharedActions.removeAll()
        firstScreenSharedActions.removeAll()
        discoveredScreens.removeAll()
        probedControlKeys.removeAll()
        orientationProbed = false
        pointerCancellationRuns = 0
        isLost = false

        statusHandler(
            "Scanning initial screen..."
        )

        try await explore(
            snapshot: initialSnapshot,
            depth: 0,
            statusHandler: statusHandler,
            screenHandler: screenHandler
        )

        return discoveredScreens
    }

    private func runtimeProbeEvaluations(
        rootNode: AccessibilityNode,
        isFirstScreen: Bool,
        focusResult: KeyboardFocusTester.Result?
    ) async throws -> [AccessibilityRuleEvaluation] {

        var results: [AccessibilityRuleEvaluation] = []

        if let environment = probeEnvironment, !environment.allowAppInteraction {
            let skipped: [(String, String)] = [
                ("state-updates-after-interaction", "State updates"),
                ("keyboard-activation", "Keyboard activation"),
                ("error-message-suggestion", "Form error messages"),
                ("orientation-support", "Orientation"),
                ("touch-up-cancellation", "Pointer cancellation"),
                ("text-resize", "Larger text"),
                ("text-clipping", "Larger text")
            ]
            return skipped.map { ruleID, name in
                ProbeEvaluation.make(
                    ruleID: ruleID,
                    status: .notTested,
                    message: "\(name) was not tested: in Current Page mode the scanner does not tap, toggle, submit or rotate, so the open page is left as the tester had it.",
                    remediation: "Run a Limited or Full App scan to test this automatically, or check it manually.",
                    node: rootNode
                )
            }
        }

        let stateProbe = StateUpdateProbe(appium: appium, alreadyTested: probedControlKeys)
        results += try await timedProbe("State update", ruleIDs: ["state-updates-after-interaction"], rootNode: rootNode) {
            try await stateProbe.test(rootNode: rootNode)
        }
        probedControlKeys.formUnion(stateProbe.testedKeys)

        let activationProbe = KeyboardActivationProbe(
            appium: appium,
            focusResult: focusResult,
            alreadyTested: probedControlKeys
        )
        results += try await timedProbe("Keyboard activation", ruleIDs: ["keyboard-activation"], rootNode: rootNode) {
            try await activationProbe.test(rootNode: rootNode)
        }
        probedControlKeys.formUnion(activationProbe.testedKeys)

        if pointerCancellationRuns < pointerCancellationScreens {
            let cancellationProbe = PointerCancellationProbe(appium: appium, alreadyTested: probedControlKeys)
            let found = try await timedProbe("Pointer cancellation", ruleIDs: ["touch-up-cancellation"], rootNode: rootNode) {
                try await cancellationProbe.test(rootNode: rootNode)
            }
            results += found
            if !found.isEmpty { pointerCancellationRuns += 1 }
            probedControlKeys.formUnion(cancellationProbe.testedKeys)
        }

        let errorProbe = ErrorMessageProbe(appium: appium, alreadyTested: probedControlKeys)
        results += try await timedProbe("Form errors", ruleIDs: ["error-message-suggestion"], rootNode: rootNode) {
            try await errorProbe.test(rootNode: rootNode)
        }
        probedControlKeys.formUnion(errorProbe.testedKeys)

        if !orientationProbed {
            orientationProbed = true
            results += try await timedProbe("Orientation", ruleIDs: ["orientation-support"], rootNode: rootNode) {
                try await OrientationProbe(appium: appium).test(rootNode: rootNode)
            }
        }

        if isFirstScreen, let environment = probeEnvironment {
            results += try await timedProbe("Larger text", ruleIDs: ["text-resize", "text-clipping"], rootNode: rootNode) {
                try await TextSizeProbe(
                    appium: appium,
                    environment: environment,
                    scanner: scanner
                ).test(rootNode: rootNode)
            }
        }

        return results
    }

    private func timedProbe(
        _ name: String,
        ruleIDs: [String],
        rootNode: AccessibilityNode,
        _ body: () async throws -> [AccessibilityRuleEvaluation]
    ) async throws -> [AccessibilityRuleEvaluation] {
        let started = Date()
        defer {
            trace("Runtime probe \(name): \(String(format: "%.1f", Date().timeIntervalSince(started)))s", Log.crawler)
        }
        do {
            return try await body()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ruleIDs.map { ruleID in
                ProbeEvaluation.make(
                    ruleID: ruleID,
                    status: .notTested,
                    message: "\(name) was not tested: \(error.localizedDescription)",
                    node: rootNode
                )
            }
        }
    }

    private func explore(
        snapshot: StableScanSnapshot,
        depth: Int,
        statusHandler: @escaping (String) -> Void,
        screenHandler: ((CrawledScreen) -> Void)? = nil
    ) async throws {

        if discoveredScreens.count >=
            configuration.maximumScreens {

            statusHandler(
                "Maximum screen limit reached."
            )

            return
        }

        if depth >
            configuration.maximumDepth {

            statusHandler(
                "Maximum navigation depth reached."
            )

            return
        }

        let signature =
            contentFingerprint(
                from: snapshot.rootNode
            )

        if isVisited(snapshot.rootNode) {

            return
        }

        visitedScreens.insert(signature)

        statusHandler(
            "Scanning screen \(discoveredScreens.count + 1)..."
        )

        let scrollResult =
            try await scanScrollableScreen(
                initialSnapshot: snapshot,
                statusHandler: statusHandler
            )

        let topSnapshot =
            scrollResult.topSnapshot

        let everyLabel = ([snapshot.rootNode, topSnapshot.rootNode] + scrollResult.viewportCaptures.map(\.snapshot.rootNode))
            .reduce(into: Set<String>()) { $0.formUnion(ProbeNodes.contentLabels(in: $1)) }
        screenContentLabels[contentFingerprint(from: snapshot.rootNode)] = everyLabel
        screenContentLabels[contentFingerprint(from: topSnapshot.rootNode)] = everyLabel

        let evaluations =
            scrollResult.evaluations

        let screenshotEvaluations =
            scrollResult.topEvaluations

        statusHandler("Testing keyboard focus on screen \(discoveredScreens.count + 1)...")
        let keyboardFocusEvaluations: [AccessibilityRuleEvaluation]
        var focusResult: KeyboardFocusTester.Result?
        let focusStarted = Date()
        do {
            focusResult = try await KeyboardFocusTester(appium: appium).test(
                rootNode: topSnapshot.rootNode,
                viewportRoots: scrollResult.viewportCaptures.map(\.snapshot.rootNode)
            )
            keyboardFocusEvaluations = focusResult?.evaluations ?? []
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            keyboardFocusEvaluations = [
                KeyboardFocusTester(appium: appium).unavailableEvaluation(
                    rootNode: topSnapshot.rootNode,
                    error: error
                )
            ]
            trace("Keyboard focus probe unavailable: \(error.localizedDescription)", Log.crawler)
        }

        trace("Runtime probe Keyboard focus: \(String(format: "%.1f", Date().timeIntervalSince(focusStarted)))s", Log.crawler)

        statusHandler("Running runtime checks on screen \(discoveredScreens.count + 1)...")
        let runtimeEvaluations = try await runtimeProbeEvaluations(
            rootNode: topSnapshot.rootNode,
            isFirstScreen: discoveredScreens.isEmpty,
            focusResult: focusResult
        )

        // Tab scrolls the screen to each focused control; the actions below
        // use positions from the top of the screen.
        if focusResult?.evidenceAvailable == true {
            _ = try? await scrolledToTop(topSnapshot, statusHandler: statusHandler)
        }

        let actions =
            navigationActions(
                from: topSnapshot.rootNode
            )

        for (index, action) in actions.enumerated() {

            trace("""
            ACTION #\(index + 1)
                Type:
                    \(action.type)

                Label:
                    \(action.label)

                Identifier:
                    \(action.identifier)

                Frame:
                    \(action.frame)

                XPath:
                    \(action.xpath ?? "NONE")
            """, Log.crawler)
        }

        let screenIndex = discoveredScreens.count

        let screen = CrawledScreen(
            signature: signature,
            rootNode: topSnapshot.rootNode,
            evaluations: evaluations,
            screenshotEvaluations: screenshotEvaluations,
            actions: actions,
            transitions: [],
            screenshotData: topSnapshot.screenshotData,
            screenshotWidth: topSnapshot.screenshotWidth,
            screenshotHeight: topSnapshot.screenshotHeight,
            viewportCaptures: scrollResult.viewportCaptures,
            keyboardFocusEvaluations: keyboardFocusEvaluations + runtimeEvaluations
        )
        discoveredScreens.append(screen)
        screenHandler?(screen)

        statusHandler(
            "Screen \(discoveredScreens.count) scanned — " +
            "\(actions.count) navigation actions found."
        )

        guard depth <
                configuration.maximumDepth
        else {
            return
        }

        // Runtime checks tap, submit, rotate and relaunch. Make sure the crawl
        // carries on from this screen and not from wherever they left the app.
        guard try await returnToScreen(topSnapshot.rootNode, depth: depth, statusHandler: statusHandler) else {
            return
        }

        let actionsToExplore =
            Array(
                actions.prefix(
                    configuration.maximumActionsPerScreen
                )
            )

        if depth == 0 {
            firstScreenSharedActions = Set(actionsToExplore
                .filter { isSharedNavigation($0, in: snapshot.rootNode) }
                .compactMap(\.xpath))
        }

        // The same action repeated on every list item ("Bookmark article",
        // "Share article") leads to the same kind of result: try it once.
        var triedActionKinds = Set<String>()

        for (index, action)
            in actionsToExplore.enumerated() {

            if discoveredScreens.count >=
                configuration.maximumScreens {

                break
            }

            let kind = [action.type, action.identifier, action.label].joined(separator: "|")
            guard triedActionKinds.insert(kind).inserted else {
                statusHandler("Skipping \(action.displayName): the same action was already tried on this screen.")
                continue
            }

            statusHandler(
                "Exploring action " +
                "\(index + 1)/\(actionsToExplore.count): " +
                action.displayName
            )

            guard let xpath = action.xpath else {

                    statusHandler(
                        "Skipping action without identifier or label: " +
                        action.displayName
                    )

                    continue
                }

            if isSharedNavigation(action, in: snapshot.rootNode) {
                let alreadyExplored = exploredSharedActions.contains(xpath) ||
                    (depth > 0 && firstScreenSharedActions.contains(xpath))
                guard !alreadyExplored else {
                    statusHandler("Skipping \(action.displayName): shared navigation already explored.")
                    continue
                }
                exploredSharedActions.insert(xpath)
            }

                trace("""
                ==========================================
                CRAWLER TAP
                ==========================================

                Action:
                    \(action.displayName)

                Type:
                    \(action.type)

                Identifier:
                    \(action.identifier)

                XPath:
                    \(xpath)

                Frame:
                    \(action.frame)

                ==========================================
                """, Log.crawler)

                do {

                    try await appium.tapElement(
                        usingXPath: xpath
                    )

                } catch is CancellationError {
                    throw CancellationError()
                } catch {

                    notes.record(.tapFailed, example: action.displayName)
                    trace("""
                    ==========================================
                    CRAWLER TAP FAILED
                    ==========================================

                    Action:
                        \(action.displayName)

                    XPath:
                        \(xpath)

                    Error:
                        \(error.localizedDescription)

                    ==========================================
                    """, Log.crawler)

                    continue
                }

            try await Task.sleep(
                nanoseconds:
                    configuration.settleDelayNanoseconds
            )

            // A link that opens a browser, the dialer, Settings or a share
            // sheet must not be crawled: bring the app under test back.
            if try await returnToTargetAppIfNeeded(
                after: action,
                statusHandler: statusHandler
            ) {
                let returned = try? await captureStableSnapshot()
                if let returned,
                   isSameScreen(returned.rootNode, snapshot.rootNode) {
                    continue
                }
                statusHandler("Could not get back to the screen after leaving the app; stopping exploration of this branch.")
                notes.record(.lostNavigation, example: action.displayName)
                isLost = true
                return
            }

            var didNavigate = true

            do {

                // One page-source read decides what the tap did; the full
                // snapshot (two reads and a screenshot) is only needed for a
                // new screen that will be scanned.
                let quickRoot = try await readRoot()

                let nextSignature =
                    contentFingerprint(
                        from:
                            quickRoot
                    )

                let navigated = !isSameScreen(snapshot.rootNode, quickRoot)
                trace("Crawl tap \"\(action.displayName)\": \(navigated ? (isVisited(quickRoot) ? "opened an already scanned screen" : "opened a new screen") : "no change")", Log.crawler)

                if navigated {
                    discoveredScreens[screenIndex].transitions.append(
                        NavigationTransition(
                            sourceSignature: signature,
                            targetSignature: nextSignature,
                            action: action
                        )
                    )
                }

                if !navigated {
                    didNavigate = false

                    trace("""
                    ==========================================
                    CRAWLER NO-OP TAP
                    ==========================================
                    Action did not change the screen: \
                    \(action.displayName)
                    ==========================================
                    """, Log.crawler)

                    statusHandler(
                        "Action did not change the screen: " +
                        action.displayName
                    )

                } else if !isVisited(quickRoot) {

                    let nextSnapshot = try await captureStableSnapshot()
                    try await explore(
                        snapshot: nextSnapshot,
                        depth: depth + 1,
                        statusHandler: statusHandler,
                        screenHandler: screenHandler
                    )

                } else {

                    trace("""
                    ==========================================
                    CRAWLER DUPLICATE SCREEN SKIPPED
                    ==========================================
                    Tap navigated to an already-visited screen \
                    — not re-scanned or re-screenshotted.
                    ==========================================
                    """, Log.crawler)

                    statusHandler(
                        "Screen already visited — skipping."
                    )
                }

            } catch is CancellationError {
                throw CancellationError()
            } catch {

                notes.record(.snapshotFailed, example: action.displayName)
                trace("""
                ==========================================
                CRAWLER SNAPSHOT FAILED
                ==========================================
                Action:
                    \(action.displayName)

                Error:
                    \(error.localizedDescription)
                ==========================================
                """, Log.crawler)
            }

            if discoveredScreens.count >=
                configuration.maximumScreens {

                break
            }

            // A deeper screen could not navigate back to where it expected.
            // Find out where we are before pressing Back again.
            if isLost {
                if await isShowing(snapshot.rootNode) {
                    isLost = false
                    statusHandler("Found the way back to the previous screen — continuing.")
                    continue
                }
                if try await returnViaTabBar(to: snapshot.rootNode) {
                    isLost = false
                    statusHandler("Found the way back to the previous screen — continuing.")
                    continue
                }
                // On the first screen the remaining actions are mostly tabs,
                // reachable from anywhere: keep going rather than end the scan.
                if depth == 0 {
                    isLost = false
                    continue
                }
                return
            }

            guard didNavigate else {

                statusHandler(
                    "No back navigation needed — continuing with next action."
                )

                continue
            }

            // A tab has no Back: pressing it on a tab screen goes somewhere
            // unpredictable. Return by re-selecting this screen's tab.
            if isSharedNavigation(action, in: snapshot.rootNode) {
                if try await returnViaTabBar(to: snapshot.rootNode) {
                    statusHandler("Returned to the previous screen through its tab.")
                    continue
                }
                notes.record(.lostNavigation, example: action.displayName)
                isLost = true
                if depth == 0 { isLost = false; continue }
                return
            }

            if try await navigateBack(to: snapshot.rootNode, statusHandler: statusHandler) {
                statusHandler("Returned to previous screen — continuing with next action.")
                continue
            }
            statusHandler("Back navigation did not return to the previous screen.")
            notes.record(.lostNavigation, example: action.displayName)
            isLost = true
            break
        }
    }

    /// One page-source read, no screenshot: enough to tell which screen is
    /// showing.
    private func readRoot() async throws -> AccessibilityNode {
        try appium.makeParser().parse(try await appium.getSource())
    }

    private func isShowing(_ screen: AccessibilityNode) async -> Bool {
        guard let root = try? await readRoot() else { return false }
        return matchesScreen(root, screen)
    }

    /// The same screen as `screen`, at any scroll position: most of what is
    /// showing now was seen somewhere on that screen.
    private func matchesScreen(_ current: AccessibilityNode, _ screen: AccessibilityNode) -> Bool {
        if isSameScreen(current, screen) { return true }
        guard let known = screenContentLabels[contentFingerprint(from: screen)] else { return false }
        let labels = ProbeNodes.contentLabels(in: current)
        guard labels.count >= 3 else { return false }
        return Double(labels.intersection(known).count) / Double(labels.count) >= 0.7
    }

    /// Returns to `screen` after an action opened something on top of it.
    /// Back only works for pushed screens (it taps the navigation bar's back
    /// button on iOS); sheets and full-screen covers need their close button
    /// or a swipe down, and tab roots need their tab.
    private func navigateBack(to screen: AccessibilityNode, statusHandler: @escaping (String) -> Void) async throws -> Bool {
        let settle = configuration.settleDelayNanoseconds

        if (try? await appium.goBack()) != nil {
            try await Task.sleep(nanoseconds: settle)
            if await isShowing(screen) { trace("Crawl back: Back", Log.crawler); return true }
        }

        // A close control near the top: Close, Done, Cancel, Back, or an
        // xmark / chevron icon.
        if let current = try? await readRoot() {
            let top = current.frame.minY + current.frame.height * 0.25
            let closeWords: Set<String> = ["close", "done", "cancel", "dismiss", "back"]
            let closeIcons = ["xmark", "chevron.left", "chevron.backward", "arrow.left", "arrow.backward"]
            let close = ProbeNodes.all(in: current).first { node in
                node.role == .button && node.visible && node.frame.minY < top &&
                    (closeWords.contains(ProbeNodes.clean(node.label).lowercased()) ||
                     closeIcons.contains { node.identifier.lowercased().hasPrefix($0) })
            }
            if let close, let xpath = NavigationAction(node: close).xpath,
               (try? await appium.tapElement(usingXPath: xpath)) != nil {
                try await Task.sleep(nanoseconds: settle)
                if await isShowing(screen) {
                    trace("Crawl back: close button \(close.label.isEmpty ? close.identifier : close.label)", Log.crawler)
                    statusHandler("Closed the opened screen with \"\(close.label.isEmpty ? close.identifier : close.label)\".")
                    return true
                }
            }

            // An iOS sheet closes with a swipe down from its top.
            if appium.platform == .ios {
                let frame = current.frame
                let start = CGPoint(x: frame.midX, y: frame.minY + frame.height * 0.12)
                let end = CGPoint(x: frame.midX, y: frame.minY + frame.height * 0.9)
                if (try? await appium.pressAndSlideAway(from: start, to: end)) != nil {
                    try await Task.sleep(nanoseconds: settle)
                    if await isShowing(screen) {
                        trace("Crawl back: swipe down", Log.crawler)
                        statusHandler("Closed the opened sheet with a swipe down.")
                        return true
                    }
                }
            }
        }

        if try await returnViaTabBar(to: screen) {
            trace("Crawl back: tab bar", Log.crawler)
            statusHandler("Returned to the previous screen through its tab.")
            return true
        }
        let here = (try? await readRoot()).map { ProbeNodes.contentLabels(in: $0).sorted().prefix(6).joined(separator: ", ") } ?? "unreadable"
        trace("Crawl back FAILED. Showing: \(here)", Log.crawler)
        return false
    }
    
    /// Returns to `screen` by tapping its tab-bar buttons (selected tab first)
    /// until it is showing again. Tab roots have no Back, so after exploring
    /// another tab Back cannot return. Tab buttons only switch tabs, so trying
    /// them is safe. Works for native tab bars and custom bottom bars.
    private func returnViaTabBar(to screen: AccessibilityNode) async throws -> Bool {
        let height = screen.frame.height
        guard height > 0 else { return false }

        var tabs: [AccessibilityNode] = []
        func collect(_ node: AccessibilityNode, inTabBar: Bool) {
            let inside = inTabBar || node.role == .tabBar
            let atBottom = node.frame.minY >= screen.frame.minY + height * 0.8
            if node.role == .button, node.visible, inside || atBottom,
               ActionSafety.isSafeToExplore(node), NavigationAction(node: node).xpath != nil {
                tabs.append(node)
            }
            node.children.forEach { collect($0, inTabBar: inside) }
        }
        collect(screen, inTabBar: false)
        guard !tabs.isEmpty else { return false }

        let selected = tabs.filter { $0.traits.lowercased().contains("selected") || $0.value == "1" }
        let ordered = selected + tabs.filter { tab in !selected.contains { $0.frame == tab.frame } }
            .sorted { $0.frame.minX < $1.frame.minX }

        for tab in ordered.prefix(6) {
            try Task.checkCancellation()
            guard let xpath = NavigationAction(node: tab).xpath,
                  (try? await appium.tapElement(usingXPath: xpath)) != nil else { continue }
            try await Task.sleep(nanoseconds: configuration.settleDelayNanoseconds)
            if await isShowing(screen) {
                return true
            }
        }
        return false
    }

    /// Already scanned: the same fingerprint, or mostly the same content as a
    /// discovered screen (moving carousels and clocks change fingerprints).
    private func isVisited(_ root: AccessibilityNode) -> Bool {
        if visitedScreens.contains(contentFingerprint(from: root)) { return true }
        return discoveredScreens.contains { isSameScreen($0.rootNode, root) }
    }

    /// Tab-bar items and buttons in a bottom bar: navigation repeated on
    /// every screen.
    private func isSharedNavigation(_ action: NavigationAction, in screen: AccessibilityNode) -> Bool {
        if action.type.contains("TabBar") { return true }
        let height = screen.frame.height
        guard height > 0 else { return false }
        return action.frame.minY >= screen.frame.minY + height * 0.85 && action.frame.height <= 100
    }

    /// Whether two snapshots show the same screen: at least 60% of their
    /// visible text and control labels in common. An exact fingerprint
    /// treats a toggled bookmark, a selected chip or a clock as a different
    /// screen, which made the crawler think it was lost and stop.
    private func isSameScreen(_ a: AccessibilityNode, _ b: AccessibilityNode) -> Bool {
        let labelsA = ProbeNodes.contentLabels(in: a)
        let labelsB = ProbeNodes.contentLabels(in: b)
        guard !labelsA.isEmpty || !labelsB.isEmpty else {
            return contentFingerprint(from: a) == contentFingerprint(from: b)
        }
        let shared = Double(labelsA.intersection(labelsB).count)
        let total = Double(labelsA.union(labelsB).count)
        return shared / total >= 0.6
    }

    private func returnToScreen(
        _ screen: AccessibilityNode,
        depth: Int,
        statusHandler: @escaping (String) -> Void
    ) async throws -> Bool {
        func isHere() async -> Bool { await isShowing(screen) }

        if await isHere() { return true }

        if let target = probeEnvironment?.bundleID,
           let foreground = await appium.foregroundAppID(), foreground != target {
            await appium.activateApp(bundleID: target)
            try await Task.sleep(nanoseconds: configuration.settleDelayNanoseconds)
            if await isHere() { return true }
        }

        // Back on the first screen could leave the app (Android).
        guard depth > 0 else {
            statusHandler("The screen changed during runtime checks; continuing from the current screen.")
            return true
        }

        if try await navigateBack(to: screen, statusHandler: statusHandler) { return true }

        statusHandler("Runtime checks left this screen and it could not be found again; skipping its actions.")
        notes.record(.lostNavigation, example: "after runtime checks")
        isLost = true
        return false
    }

    private func returnToTargetAppIfNeeded(
        after action: NavigationAction,
        statusHandler: @escaping (String) -> Void
    ) async throws -> Bool {
        guard let target = probeEnvironment?.bundleID,
              let foreground = await appium.foregroundAppID(),
              foreground != target,
              !Self.overlayPackages.contains(foreground)
        else {
            return false
        }

        statusHandler("\(action.displayName) opened \(foreground); returning to the app under test.")
        notes.record(.leftApp, example: action.displayName)
        await appium.activateApp(bundleID: target)
        try await Task.sleep(nanoseconds: configuration.settleDelayNanoseconds)
        return true
    }

    // MARK: - Scrollable Screen Scan
    private func scanScrollableScreen(
        initialSnapshot: StableScanSnapshot,
        statusHandler: @escaping (String) -> Void
    ) async throws -> ScrollableScreenScanResult {

        // The screen may open part-way down (left scrolled by an earlier run
        // or by keyboard focus). Capture starts from the top so nothing above
        // the current position is missed.
        let initialSnapshot = try await scrolledToTop(initialSnapshot, statusHandler: statusHandler)

        var currentSnapshot = initialSnapshot

        var collectedEvaluations:
            [AccessibilityRuleEvaluation] = []
        
        let topEvaluations =
            scanner.evaluateForReport(
                rootNode: initialSnapshot.rootNode
            )

        var seenEvaluationKeys:
            Set<String> = []
        var viewportCaptures: [ScrollableViewportCapture] = []
        var seenScreenshotData: Set<Data> = []

        let maximumScrolls = 20

        var previousViewportSignature =
            ScreenSignature(
                rootNode: initialSnapshot.rootNode
            )

        var viewportCount = 0

        for scrollIndex in 0...maximumScrolls {

            viewportCount += 1

            statusHandler(
                "Scanning viewport \(viewportCount)..."
            )
            let viewportStarted = Date()

            let evaluations: [AccessibilityRuleEvaluation]

            if scrollIndex == 0 {
                evaluations = topEvaluations
            } else {
                evaluations =
                    scanner.evaluateForReport(
                        rootNode: currentSnapshot.rootNode
                    )
            }

            for evaluation in evaluations {

                let key =
                    evaluationKey(
                        for: evaluation
                    )

                if !seenEvaluationKeys.contains(key) {

                    seenEvaluationKeys.insert(key)

                    collectedEvaluations.append(
                        evaluation
                    )
                }
            }

            // Store only visually unique screenshots. This prevents the same
            // viewport from being shown repeatedly while still preserving
            // screenshots for newly revealed scroll content.
            if !seenScreenshotData.contains(currentSnapshot.screenshotData) {
                seenScreenshotData.insert(currentSnapshot.screenshotData)
                viewportCaptures.append(
                    ScrollableViewportCapture(
                        snapshot: currentSnapshot,
                        evaluations: evaluations
                    )
                )
            }
            
            trace("Crawl timing: viewport \(viewportCount) rules \(String(format: "%.1f", Date().timeIntervalSince(viewportStarted)))s", Log.crawler)

            if scrollIndex == maximumScrolls {

                statusHandler(
                    "Maximum scroll limit reached."
                )

                break
            }

            statusHandler(
                "Scrolling down..."
            )

            let scrollStarted = Date()
            do {

                try await appium.scrollDown()
                trace("Crawl timing: scroll \(String(format: "%.1f", Date().timeIntervalSince(scrollStarted)))s", Log.crawler)

            } catch {

                statusHandler(
                    "Scrolling stopped: " +
                    error.localizedDescription
                )

                break
            }

            try await Task.sleep(
                nanoseconds:
                    configuration.settleDelayNanoseconds
            )

            let nextSnapshot =
                try await captureStableSnapshot()

            let nextViewportSignature =
                ScreenSignature(
                    rootNode:
                        nextSnapshot.rootNode
                )

            if nextViewportSignature ==
                previousViewportSignature {

                statusHandler(
                    "Reached the bottom of the screen."
                )

                break
            }

            currentSnapshot =
                nextSnapshot

            previousViewportSignature =
                nextViewportSignature
        }

        statusHandler(
            "Returning to top of screen..."
        )

        var previousTopFingerprint =
            contentFingerprint(
                from: currentSnapshot.rootNode
            )

        var reachedTop = false

        let maximumTopAttempts = 10

        for attempt in 1...maximumTopAttempts {

            try await appium.scrollUp()

            try await Task.sleep(
                nanoseconds:
                    configuration.settleDelayNanoseconds
            )

            let topSnapshot =
                try await captureStableSnapshot()

            let currentTopFingerprint =
                contentFingerprint(
                    from: topSnapshot.rootNode
                )

            trace("""
            Attempt:
                \(attempt)

            Content changed:
                \(currentTopFingerprint != previousTopFingerprint)
            ==========================================
            """, Log.crawler)

            if currentTopFingerprint ==
                previousTopFingerprint {

                reachedTop = true

                statusHandler(
                    "Reached top of screen."
                )

                break
            }

            previousTopFingerprint =
                currentTopFingerprint

            statusHandler(
                "Returning to top — step \(attempt)..."
            )
        }

        if reachedTop {

            statusHandler(
                "Returned to top — " +
                "\(viewportCount) viewport(s) scanned."
            )

        } else {

            statusHandler(
                "Could not verify the exact top position after " +
                "\(maximumTopAttempts) attempts."
            )
        }

        return ScrollableScreenScanResult(
            topSnapshot: initialSnapshot,
            evaluations: collectedEvaluations,
            topEvaluations: topEvaluations,
            viewportCaptures: viewportCaptures,
            viewportCount: viewportCount
        )
    }
    
    private func scrolledToTop(
        _ snapshot: StableScanSnapshot,
        statusHandler: @escaping (String) -> Void
    ) async throws -> StableScanSnapshot {
        let scrolls = ProbeNodes.all(in: snapshot.rootNode).contains { node in
            node.visible && (node.role == .scrollView || node.role == .table ||
                node.traits.split(separator: " ").contains("scrollable"))
        }
        guard scrolls else { return snapshot }

        var current = snapshot
        var fingerprint = contentFingerprint(from: snapshot.rootNode)
        for _ in 1...10 {
            do {
                try await appium.scrollUp()
            } catch {
                return current
            }
            try await Task.sleep(nanoseconds: configuration.settleDelayNanoseconds)
            let next = try await captureStableSnapshot()
            let nextFingerprint = contentFingerprint(from: next.rootNode)
            if nextFingerprint == fingerprint { return next }
            statusHandler("Screen opened part-way down; scrolling to the top...")
            current = next
            fingerprint = nextFingerprint
        }
        return current
    }

    private func contentFingerprint(
        from rootNode: AccessibilityNode
    ) -> String {

        var values: [String] = []

        func collect(
            _ node: AccessibilityNode
        ) {

            if node.identifier ==
                "A11YScannerIgnore" {
                return
            }
            if node.role == .statusBar {
                return
            }
            
            if node.exists && node.visible {

                let identifier =
                    node.identifier
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )

                let label =
                    node.label
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )

                let value =
                    node.value?
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ) ?? ""

                values.append(
                    [
                        node.type,
                        identifier,
                        label,
                        value
                    ]
                    .joined(separator: "|")
                )
            }

            for child in node.children {

                collect(child)
            }
        }

        collect(rootNode)

        return values.joined(
            separator: "||"
        )
    }
    
    private func evaluationKey(
        for evaluation: AccessibilityRuleEvaluation
    ) -> String {

        let identifier =
            evaluation.identifier
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        let label =
            evaluation.elementLabel
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        let value =
            evaluation.value?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            ?? ""

        return [
            evaluation.ruleID,
            evaluation.elementType,
            identifier,
            label,
            value
        ]
        .joined(separator: "|")
    }

    // MARK: - Navigation Actions

    private func navigationActions(
        from rootNode: AccessibilityNode
    ) -> [NavigationAction] {

        var nodes:
            [AccessibilityNode] = []

        collectNavigationNodes(
            node: rootNode,
            into: &nodes
        )

        // Taps go through the XPath, which always hits its first match, so a
        // second action with the same XPath would only repeat the first.
        var seenXPaths = Set<String>()
        return nodes
            .map { NavigationAction(node: $0) }
            .filter { action in
                guard let xpath = action.xpath else { return true }
                return seenXPaths.insert(xpath).inserted
            }
    }

    private func collectNavigationNodes(
        node: AccessibilityNode,
        into nodes: inout [AccessibilityNode]
    ) {

        if node.identifier ==
            "A11YScannerIgnore" {

            return
        }

        if isSafeNavigationNode(node) {
            nodes.append(node)
        }

        for child in node.children {

            collectNavigationNodes(
                node: child,
                into: &nodes
            )
        }
    }

    private func isSafeNavigationNode(
        _ node: AccessibilityNode
    ) -> Bool {

        guard node.exists else {
            return false
        }

        guard node.visible else {
            return false
        }

        guard node.enabled else {
            return false
        }

        guard node.frame.width > 0,
              node.frame.height > 0
        else {
            return false
        }

        if node.identifier ==
            "A11YScannerIgnore" {

            return false
        }

        // The navigation bar's back button (iOS BackButton, labelled with
        // the previous screen's title; Android "Navigate up") only returns
        // to the screen the crawler came from.
        if ActionSafety.isBackButton(node) {
            return false
        }

        let supportedRoles: Set<AccessibilityRole> = [
            .button,
            .link,
            .cell
        ]

        guard supportedRoles.contains(node.role) else {
            return false
        }

        let text =
            (
                node.label + " " +
                node.identifier
            )
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !text.isEmpty else {
            return false
        }

        // Whole-word matching against the shared deny-lists, so "display" is
        // not blocked as "pay" and "btnTrash" is blocked as "trash".
        guard ActionSafety.isSafeToExplore(node) else {
            return false
        }

        return true
    }

    // MARK: - Stable Snapshot

    private func captureStableSnapshot()
        async throws
        -> StableScanSnapshot {

        var lastCapture: StableScanSnapshot?

        for attempt in 1...3 {

            let sourceBefore =
                try await appium.getSource()

            let parserBefore =
                appium.makeParser()

            let rootBefore =
                try parserBefore.parse(
                    sourceBefore
                )

            let screenshotData =
                try await appium.getScreenshot()

            let dimensions =
                try screenshotDimensions(
                    from: screenshotData
                )

            let sourceAfter =
                try await appium.getSource()

            let parserAfter =
                appium.makeParser()

            let rootAfter =
                try parserAfter.parse(
                    sourceAfter
                )

            let beforeSignature =
                ScreenSignature(
                    rootNode: rootBefore
                )

            let afterSignature =
                ScreenSignature(
                    rootNode: rootAfter
                )

            lastCapture = StableScanSnapshot(
                rootNode: rootBefore,
                screenshotData: screenshotData,
                screenshotWidth: dimensions.width,
                screenshotHeight: dimensions.height
            )

            if beforeSignature ==
                afterSignature {

                trace("""
                ==========================================
                CRAWLER STABLE SNAPSHOT
                ==========================================

                Attempt:
                    \(attempt)

                Screenshot:
                    \(dimensions.width) × \
                \(dimensions.height)

                Hierarchy:
                    \(rootBefore.frame.width) × \
                \(rootBefore.frame.height)

                Result:
                    STABLE

                ==========================================
                """, Log.crawler)

                return StableScanSnapshot(
                    rootNode: rootBefore,
                    screenshotData: screenshotData,
                    screenshotWidth: dimensions.width,
                    screenshotHeight: dimensions.height
                )
            }

            if attempt < 3 {

                try await Task.sleep(
                    nanoseconds: 300_000_000
                )
            }
        }

        // A screen that never holds still (animation, live content) is
        // scanned from its last capture instead of being skipped.
        if let lastCapture {
            notes.record(.unstableScreen)
            return lastCapture
        }

        throw AppCrawlerError.unstableScreen
    }

    private func screenshotDimensions(
        from data: Data
    ) throws -> (
        width: Double,
        height: Double
    ) {

        guard
            let image =
                NSImage(data: data)
        else {

            throw
                AppCrawlerError.invalidScreenshot
        }

        let size = image.size

        guard
            size.width > 0,
            size.height > 0
        else {

            throw
                AppCrawlerError.invalidScreenshot
        }

        return (
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Errors

enum AppCrawlerError:
    Error,
    LocalizedError {

    case unstableScreen
    case invalidScreenshot

    var errorDescription: String? {

        switch self {

        case .unstableScreen:

            return """
            The application UI did not become stable during crawling.
            """

        case .invalidScreenshot:

            return """
            Appium returned an invalid screenshot during crawling.
            """
        }
    }
}

// MARK: - CGRect

private extension CGRect {

    var center: CGPoint {

        CGPoint(
            x: midX,
            y: midY
        )
    }
}

