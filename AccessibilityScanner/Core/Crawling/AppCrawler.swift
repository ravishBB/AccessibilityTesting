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

        let evaluations =
            scrollResult.evaluations

        let screenshotEvaluations =
            scrollResult.topEvaluations

        statusHandler("Testing keyboard focus on screen \(discoveredScreens.count + 1)...")
        let keyboardFocusEvaluations: [AccessibilityRuleEvaluation]
        var focusResult: KeyboardFocusTester.Result?
        let focusStarted = Date()
        do {
            focusResult = try await KeyboardFocusTester(appium: appium).test(rootNode: topSnapshot.rootNode)
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

        for (index, action)
            in actionsToExplore.enumerated() {

            if discoveredScreens.count >=
                configuration.maximumScreens {

                break
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

                let nextSnapshot =
                    try await captureStableSnapshot()

                let nextSignature =
                    contentFingerprint(
                        from:
                            nextSnapshot.rootNode
                    )

                let navigated = !isSameScreen(snapshot.rootNode, nextSnapshot.rootNode)

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

                } else if !isVisited(nextSnapshot.rootNode) {

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
                if let here = try? await captureStableSnapshot(),
                   isSameScreen(here.rootNode, snapshot.rootNode) {
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

            do {
                try await appium.goBack()

                trace("""
                ==========================================
                CRAWLER BACK
                ==========================================
                Returned to previous screen.
                ==========================================
                """, Log.crawler)

                try await Task.sleep(
                    nanoseconds:
                        configuration.settleDelayNanoseconds
                )

                let backSnapshot =
                    try await captureStableSnapshot()

                if !isSameScreen(backSnapshot.rootNode, snapshot.rootNode) {
                    // Tabs have no Back: re-select the screen's tab instead.
                    if try await returnViaTabBar(to: snapshot.rootNode) {
                        statusHandler("Returned to the previous screen through its tab.")
                        continue
                    }
                    statusHandler(
                        "Back navigation did not return to the previous screen."
                    )

                    notes.record(.lostNavigation, example: action.displayName)
                    isLost = true
                    break
                }

                statusHandler(
                    "Returned to previous screen — continuing with next action."
                )

            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if (try? await returnViaTabBar(to: snapshot.rootNode)) == true {
                    statusHandler("Returned to the previous screen through its tab.")
                    continue
                }
                statusHandler(
                    "Could not return to previous screen: " +
                    error.localizedDescription
                )

                notes.record(.lostNavigation, example: action.displayName)
                isLost = true
                break
            }
        }
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
            if let here = try? await captureStableSnapshot(), isSameScreen(here.rootNode, screen) {
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
        func isHere() async -> Bool {
            guard let current = try? await captureStableSnapshot() else { return false }
            return isSameScreen(current.rootNode, screen)
        }

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

        try? await appium.goBack()
        try await Task.sleep(nanoseconds: configuration.settleDelayNanoseconds)
        if await isHere() { return true }

        if try await returnViaTabBar(to: screen) { return true }

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
            
            if scrollIndex == maximumScrolls {

                statusHandler(
                    "Maximum scroll limit reached."
                )

                break
            }

            statusHandler(
                "Scrolling down..."
            )

            do {

                try await appium.scrollDown()

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

