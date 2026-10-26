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
    /// What tapping rows with no role did on this screen (nil: not tested).
    var rowTap: RowTaps? = nil
}

/// What tapping a list row with no role did (BB40282). The hierarchy cannot
/// show whether a row is selectable; the tap can.
nonisolated enum RowTapResult {
    /// It opened another screen (named): rows of this kind are interactive.
    case opened(String)
    /// Nothing changed: rows of this kind are not interactive.
    case inert
}

/// Row taps on one screen: one tap per kind of row, since a profile header
/// and the article rows under it behave differently. Rows of a kind are
/// rows of about the same height in the same list.
nonisolated struct RowTaps {
    struct Verdict {
        let rowHeight: Double
        let result: RowTapResult
    }

    var verdicts: [Verdict] = []

    static func sameKind(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= max(a, b) * 0.12
    }

    /// Row results with the taps' verdicts: Fail where a row of that kind
    /// opened a screen, dropped where it did nothing, unchanged for kinds
    /// not tapped. Applied wherever results are produced, including the
    /// report's per-viewport rerun of the rules.
    func settle(_ evaluations: [AccessibilityRuleEvaluation]) -> [AccessibilityRuleEvaluation] {
        evaluations.compactMap { evaluation in
            guard evaluation.ruleID == "row-role", evaluation.status == .validate,
                  let verdict = verdicts.first(where: { Self.sameKind($0.rowHeight, evaluation.frameHeight) })
            else { return evaluation }
            switch verdict.result {
            case .inert:
                return nil
            case .opened(let name):
                let target = name.hasPrefix("Screen ") ? "another screen" : "\"\(name)\""
                return evaluation.settled(
                    as: .fail,
                    message: evaluation.message.replacingOccurrences(
                        of: TableRowRoleRule.unconfirmedNote,
                        with: "Tapping a row like this one opened \(target), so these rows are interactive, but VoiceOver users are not told they can be activated."
                    )
                )
            }
        }
    }
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
        route: [NavigationAction],
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

        results += try await timedProbe("Orientation", ruleIDs: ["orientation-support"], rootNode: rootNode) {
            try await OrientationProbe(appium: appium).test(rootNode: rootNode)
        }

        // Larger text relaunches the app: screens up to two taps from the
        // first one are reached again by replaying those taps.
        let routeXPaths = route.compactMap(\.xpath)
        if let environment = probeEnvironment,
           isFirstScreen || (routeXPaths.count == route.count && route.count <= 2) {
            results += try await timedProbe("Larger text", ruleIDs: ["text-resize", "text-clipping"], rootNode: rootNode) {
                try await TextSizeProbe(
                    appium: appium,
                    environment: environment,
                    scanner: scanner,
                    route: isFirstScreen ? [] : routeXPaths
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

    /// `route`: the taps that led here from the first screen, replayed by
    /// checks that relaunch the app (larger text).
    private func explore(
        snapshot: StableScanSnapshot,
        depth: Int,
        route: [NavigationAction] = [],
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

        let scannedEvaluations = scrollResult.evaluations
        let scannedScreenshotEvaluations = scrollResult.topEvaluations

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
            route: route,
            focusResult: focusResult
        )

        // Tab scrolls the screen to each focused control; the actions below
        // use positions from the top of the screen.
        if focusResult?.evidenceAvailable == true {
            _ = try? await scrolledToTop(topSnapshot, statusHandler: statusHandler)
        }

        let rowTap = try await testRowTaps(
            on: topSnapshot.rootNode,
            viewportRoots: scrollResult.viewportCaptures.map(\.snapshot.rootNode),
            depth: depth,
            statusHandler: statusHandler
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
            evaluations: scannedEvaluations,
            screenshotEvaluations: scannedScreenshotEvaluations,
            actions: actions,
            transitions: [],
            screenshotData: topSnapshot.screenshotData,
            screenshotWidth: topSnapshot.screenshotWidth,
            screenshotHeight: topSnapshot.screenshotHeight,
            viewportCaptures: scrollResult.viewportCaptures,
            keyboardFocusEvaluations: keyboardFocusEvaluations + runtimeEvaluations,
            rowTap: rowTap
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
                        route: route + [action],
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

    // MARK: - Row tap (BB40282)

    /// Taps one row of each kind that has no role (the rows `row-role`
    /// reports), up to three kinds, on its title away from any button in the
    /// row, and goes back. nil: no such rows, or interaction not allowed.
    private func testRowTaps(
        on screen: AccessibilityNode,
        viewportRoots: [AccessibilityNode],
        depth: Int,
        statusHandler: @escaping (String) -> Void
    ) async throws -> RowTaps? {
        let rule = TableRowRoleRule()
        guard probeEnvironment?.allowAppInteraction != false else { return nil }

        // Kinds of row, from everywhere on the screen, in reading order.
        var kinds: [Double] = []
        for root in [screen] + viewportRoots {
            for row in ProbeNodes.all(in: root) where rule.evaluate(node: row) != nil {
                let height = Double(row.frame.height)
                if !kinds.contains(where: { RowTaps.sameKind($0, height) }) { kinds.append(height) }
            }
        }
        guard !kinds.isEmpty else { return nil }

        let started = Date()
        defer { trace("Runtime probe Row tap: \(String(format: "%.1f", Date().timeIntervalSince(started)))s", Log.crawler) }
        statusHandler("Checking whether list rows open something...")

        var taps = RowTaps()
        var scrolledDown = 0
        for kind in kinds.prefix(3) {
            try Task.checkCancellation()
            guard !isLost else { break }
            if let result = try await tapRow(ofHeight: kind, on: screen, depth: depth, scrolledDown: &scrolledDown, statusHandler: statusHandler) {
                taps.verdicts.append(RowTaps.Verdict(rowHeight: kind, result: result))
            }
        }
        // The actions explored next use positions from the top of the screen.
        for _ in 0..<scrolledDown { try? await appium.scrollUp() }
        return taps.verdicts.isEmpty ? nil : taps
    }

    /// Taps one row of the given kind. nil: no such row could be reached, or
    /// the result was unclear (the row changed in place), so rows of this
    /// kind stay Validate.
    private func tapRow(
        ofHeight kind: Double,
        on screen: AccessibilityNode,
        depth: Int,
        scrolledDown: inout Int,
        statusHandler: @escaping (String) -> Void
    ) async throws -> RowTapResult? {
        let rule = TableRowRoleRule()

        /// A row of this kind and the text to tap on, where they are now.
        func candidate(in root: AccessibilityNode) -> (row: AccessibilityNode, title: AccessibilityNode)? {
            ProbeNodes.all(in: root).filter {
                RowTaps.sameKind(Double($0.frame.height), kind) && rule.evaluate(node: $0) != nil
            }.lazy.compactMap { row in
                let texts = ProbeNodes.all(in: row).dropFirst().filter {
                    AccessibilityRole.textual.contains($0.role) && $0.visible && !ProbeNodes.clean($0.label).isEmpty
                }
                // A row that reads like "Delete account" is not tapped.
                guard texts.allSatisfy(ActionSafety.isSafeToExplore),
                      let title = texts.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
                else { return nil }
                return (row, title)
            }.first
        }

        // Earlier checks may have left the screen (the larger-text check
        // relaunches the app) or scrolled it.
        var current = try? await readRoot()
        if current.map({ !matchesScreen($0, screen) }) ?? true {
            guard try await returnToScreen(screen, depth: depth, statusHandler: statusHandler) else {
                trace("Row tap skipped: could not get back to the screen", Log.crawler)
                return nil
            }
            current = try? await readRoot()
        }
        var found = current.flatMap(candidate)
        // Screens are checked from the top: look further down first, then
        // back up past the starting point.
        for step in 0..<7 where found == nil && current != nil {
            if step < 4 {
                try? await appium.scrollDown()
                scrolledDown += 1
            } else {
                try? await appium.scrollUp()
                scrolledDown = max(0, scrolledDown - 1)
            }
            try await Task.sleep(nanoseconds: configuration.settleDelayNanoseconds)
            current = try? await readRoot()
            found = current.flatMap(candidate)
        }
        guard let current, let (_, title) = found else {
            trace("Row tap skipped: no \(Int(kind)) pt row with readable text on screen", Log.crawler)
            return nil
        }

        do {
            try await appium.tap(at: CGPoint(x: title.frame.midX, y: title.frame.midY))
            try await Task.sleep(nanoseconds: configuration.settleDelayNanoseconds)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            trace("Row tap skipped: tap on \"\(title.label)\" failed: \(error.localizedDescription)", Log.crawler)
            return nil
        }
        guard let after = try? await readRoot() else {
            trace("Row tap: screen unreadable after tapping \"\(title.label)\"", Log.crawler)
            _ = try await returnToScreen(screen, depth: depth, statusHandler: statusHandler)
            return nil
        }

        // Compared with the screen as it was just before the tap, not with
        // everything seen on it while scrolling: an article screen repeats
        // its row's title, author and category, and the tab bar.
        func hasBack(_ root: AccessibilityNode) -> Bool {
            ProbeNodes.all(in: root).contains { $0.visible && ActionSafety.isBackButton($0) }
        }
        let openedScreen = !isSameScreen(after, current) || (hasBack(after) && !hasBack(current))
        if !openedScreen {
            // Still here with the same text: the tap did nothing. A row only
            // drawn highlighted is UIKit's selection highlight, which shows
            // even when nothing handles the selection. Changed text (a row
            // that expands or updates) is unclear.
            let sameText = ProbeNodes.contentLabels(in: after) == ProbeNodes.contentLabels(in: current)
            trace("Row tap: \"\(title.label)\" (\(Int(kind)) pt rows) stayed on the screen, text \(sameText ? "unchanged" : "changed")", Log.crawler)
            return sameText ? .inert : nil
        }

        let opened = ScreenNaming.name(for: after, number: 0)
        trace("Row tap: \"\(title.label)\" (\(Int(kind)) pt rows) opened \(opened)", Log.crawler)
        guard try await navigateBack(to: screen, statusHandler: statusHandler) else {
            notes.record(.lostNavigation, example: "after tapping a list row")
            isLost = true
            return .opened(opened)
        }
        return .opened(opened)
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
        var carouselsDone = Set<String>()

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

            // Rows that scroll sideways hide items past the right edge.
            for capture in try await carouselCaptures(in: currentSnapshot, done: &carouselsDone, statusHandler: statusHandler) {
                for evaluation in capture.evaluations where seenEvaluationKeys.insert(evaluationKey(for: evaluation)).inserted {
                    collectedEvaluations.append(evaluation)
                }
                if seenScreenshotData.insert(capture.snapshot.screenshotData).inserted {
                    viewportCaptures.append(capture)
                }
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
    
    /// Swipes each sideways-scrolling row (chips, carousels) on this
    /// viewport left until its last items have been on screen, captures
    /// what appeared, and swipes it back. A row is handled once per screen.
    private func carouselCaptures(
        in snapshot: StableScanSnapshot,
        done: inout Set<String>,
        statusHandler: @escaping (String) -> Void
    ) async throws -> [ScrollableViewportCapture] {
        let root = snapshot.rootNode
        let screen = root.frame
        let carousels = ProbeNodes.all(in: root).filter { node in
            let frame = node.frame
            guard node.visible, node.role == .scrollView || node.type.contains("CollectionView") ||
                    node.traits.split(separator: " ").contains("scrollable"),
                  frame.width >= screen.width * 0.6, frame.height <= screen.height * 0.4,
                  frame.minY >= screen.minY + 40, frame.maxY <= screen.maxY - 90,
                  !node.semantics.partiallyVisible
            else { return false }
            // Named content past the right edge.
            return ProbeNodes.all(in: node).dropFirst().contains {
                $0.frame.minX >= screen.maxX - 2 && !ProbeNodes.clean($0.label).isEmpty
            }
        }

        var captures: [ScrollableViewportCapture] = []
        for carousel in carousels.prefix(3) {
            try Task.checkCancellation()
            let key = ProbeNodes.all(in: carousel).dropFirst().map { ProbeNodes.clean($0.label) }
                .filter { !$0.isEmpty }.prefix(8).joined(separator: "|")
            guard done.insert(key).inserted else { continue }

            statusHandler("Scrolling a row sideways to check its hidden items...")
            let frame = carousel.frame
            var swipes = 0
            var previous = contentFingerprint(from: root)
            for _ in 0..<3 {
                guard (try? await appium.horizontalDrag(atY: frame.midY, fromX: frame.maxX - 24, toX: frame.minX + 24)) != nil else { break }
                swipes += 1
                try await Task.sleep(nanoseconds: configuration.settleDelayNanoseconds)
                let next = try await captureStableSnapshot()
                let fingerprint = contentFingerprint(from: next.rootNode)
                if fingerprint == previous { break }
                previous = fingerprint
                captures.append(ScrollableViewportCapture(snapshot: next, evaluations: scanner.evaluateForReport(rootNode: next.rootNode)))
            }
            for _ in 0..<swipes {
                try? await appium.horizontalDrag(atY: frame.midY, fromX: frame.minX + 24, toX: frame.maxX - 24)
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            trace("Carousel at y \(Int(frame.minY)): \(swipes) swipe(s), \(captures.count) capture(s)", Log.crawler)
        }
        return captures
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

