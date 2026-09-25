//
//  AppCrawler.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 25/09/26.
//

import Foundation
import CoreGraphics
import AppKit

struct CrawledScreen {
    let signature: ScreenSignature
    let rootNode: AccessibilityNode
    let evaluations: [AccessibilityRuleEvaluation]
    let actions: [NavigationAction]

    let screenshotData: Data
    let screenshotWidth: Double
    let screenshotHeight: Double
}

struct ScrollableScreenScanResult {
    let topSnapshot: StableScanSnapshot
    let evaluations: [AccessibilityRuleEvaluation]
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

    private var visitedScreens:
        Set<ScreenSignature> = []

    private var discoveredScreens:
        [CrawledScreen] = []

    init(
        appium: AppiumClient,
        scanner: AccessibilityScanner = AccessibilityScanner(),
        configuration: AppCrawlerConfiguration =
            .default
    ) {

        self.appium = appium
        self.scanner = scanner
        self.configuration = configuration
    }

    func crawl(
        initialSnapshot: StableScanSnapshot,
        statusHandler: @escaping (String) -> Void
    ) async throws -> [CrawledScreen] {

        visitedScreens.removeAll()
        discoveredScreens.removeAll()

        statusHandler(
            "Scanning initial screen..."
        )

        try await explore(
            snapshot: initialSnapshot,
            depth: 0,
            statusHandler: statusHandler
        )

        return discoveredScreens
    }

    private func explore(
        snapshot: StableScanSnapshot,
        depth: Int,
        statusHandler: @escaping (String) -> Void
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
            ScreenSignature(
                rootNode: snapshot.rootNode
            )

        if visitedScreens.contains(signature) {
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

        let actions =
            navigationActions(
                from: topSnapshot.rootNode
            )
        
        print("""
        ==========================================
        CRAWLER SCREEN
        ==========================================

        Screen:
            \(discoveredScreens.count + 1)

        Actions found:
            \(actions.count)

        ==========================================
        """)

        for (index, action) in actions.enumerated() {

            print("""
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
            """)
        }

        let screen = CrawledScreen(
            signature: signature,
            rootNode: topSnapshot.rootNode,
            evaluations: evaluations,
            actions: actions,
            screenshotData: topSnapshot.screenshotData,
            screenshotWidth: topSnapshot.screenshotWidth,
            screenshotHeight: topSnapshot.screenshotHeight
        )
        discoveredScreens.append(screen)

        statusHandler(
            "Screen \(discoveredScreens.count) scanned — " +
            "\(actions.count) navigation actions found."
        )

        guard depth <
                configuration.maximumDepth
        else {
            return
        }

        let actionsToExplore =
            Array(
                actions.prefix(
                    configuration.maximumActionsPerScreen
                )
            )

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

            let currentSignature =
                ScreenSignature(
                    rootNode: snapshot.rootNode
                )

            do {

                guard let xpath = action.xpath else {

                    statusHandler(
                        "Skipping action without identifier or label: " +
                        action.displayName
                    )

                    continue
                }

                print("""
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
                """)

                do {

                    try await appium.tapElement(
                        usingXPath: xpath
                    )

                } catch {

                    print("""
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
                    """)

                    continue
                }

            } catch {

                print("""
                ==========================================
                CRAWLER ACTION FAILED
                ==========================================
                Action:
                    \(action.displayName)

                Type:
                    \(action.type)

                Error:
                    \(error.localizedDescription)
                ==========================================
                """)

                continue
            }

            try await Task.sleep(
                nanoseconds:
                    configuration.settleDelayNanoseconds
            )

            do {

                let nextSnapshot =
                    try await captureStableSnapshot()

                let nextSignature =
                    ScreenSignature(
                        rootNode:
                            nextSnapshot.rootNode
                    )

                if nextSignature ==
                    currentSignature {

                    statusHandler(
                        "Action did not change the screen: " +
                        action.displayName
                    )

                } else if !visitedScreens.contains(
                    nextSignature
                ) {

                    try await explore(
                        snapshot: nextSnapshot,
                        depth: depth + 1,
                        statusHandler: statusHandler
                    )

                } else {

                    statusHandler(
                        "Screen already visited — skipping."
                    )
                }

            } catch {

                print("""
                ==========================================
                CRAWLER SNAPSHOT FAILED
                ==========================================
                Action:
                    \(action.displayName)

                Error:
                    \(error.localizedDescription)
                ==========================================
                """)
            }

            if discoveredScreens.count >=
                configuration.maximumScreens {

                break
            }

            do {
                try await appium.goBack()

                print("""
                ==========================================
                CRAWLER BACK
                ==========================================
                Returned to previous screen.
                ==========================================
                """)

                try await Task.sleep(
                    nanoseconds:
                        configuration.settleDelayNanoseconds
                )

                let backSnapshot =
                    try await captureStableSnapshot()

                let backSignature =
                    ScreenSignature(
                        rootNode:
                            backSnapshot.rootNode
                    )

                if backSignature != currentSignature {
                    statusHandler(
                        "Back navigation did not return to the previous screen."
                    )

                    break
                }

                statusHandler(
                    "Returned to previous screen — continuing with next action."
                )

            } catch {
                statusHandler(
                    "Could not return to previous screen: " +
                    error.localizedDescription
                )

                break
            }
        }
    }
    
    // MARK: - Scrollable Screen Scan
    private func scanScrollableScreen(
        initialSnapshot: StableScanSnapshot,
        statusHandler: @escaping (String) -> Void
    ) async throws -> ScrollableScreenScanResult {

        var currentSnapshot = initialSnapshot

        var collectedEvaluations:
            [AccessibilityRuleEvaluation] = []

        var seenEvaluationKeys:
            Set<String> = []

        let maximumScrolls = 20

        // Used only for detecting downward viewport movement.
        var previousViewportSignature =
            ScreenSignature(
                rootNode: initialSnapshot.rootNode
            )

        var viewportCount = 0

        // ---------------------------------------------------------
        // 1. Scan all scrollable viewports
        // ---------------------------------------------------------

        for scrollIndex in 0...maximumScrolls {

            viewportCount += 1

            statusHandler(
                "Scanning viewport \(viewportCount)..."
            )

            // -----------------------------------------------------
            // Scan current viewport
            // -----------------------------------------------------

            let evaluations =
                scanner.evaluateForReport(
                    rootNode: currentSnapshot.rootNode
                )

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

            // -----------------------------------------------------
            // Maximum scroll protection
            // -----------------------------------------------------

            if scrollIndex == maximumScrolls {

                statusHandler(
                    "Maximum scroll limit reached."
                )

                break
            }

            // -----------------------------------------------------
            // Scroll down
            // -----------------------------------------------------

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

            // -----------------------------------------------------
            // Wait for UI to settle
            // -----------------------------------------------------

            try await Task.sleep(
                nanoseconds:
                    configuration.settleDelayNanoseconds
            )

            // -----------------------------------------------------
            // Capture next viewport
            // -----------------------------------------------------

            let nextSnapshot =
                try await captureStableSnapshot()

            let nextViewportSignature =
                ScreenSignature(
                    rootNode:
                        nextSnapshot.rootNode
                )

            // -----------------------------------------------------
            // Detect bottom
            // -----------------------------------------------------

            if nextViewportSignature ==
                previousViewportSignature {

                statusHandler(
                    "Reached the bottom of the screen."
                )

                break
            }

            // -----------------------------------------------------
            // Continue scanning next viewport
            // -----------------------------------------------------

            currentSnapshot =
                nextSnapshot

            previousViewportSignature =
                nextViewportSignature
        }

        // ---------------------------------------------------------
        // 2. Return to top
        // ---------------------------------------------------------

        statusHandler(
            "Returning to top of screen..."
        )

        /*
         IMPORTANT:

         Do NOT compare ScreenSignature here.

         ScreenSignature contains frame information and therefore
         is appropriate for detecting viewport movement, but it
         should not be used to decide whether the scroll view has
         reached its top.

         Instead, compare the logical content fingerprint before
         and after an upward scroll.
         */

        var previousTopFingerprint =
            viewportContentFingerprint(
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
                viewportContentFingerprint(
                    from: topSnapshot.rootNode
                )

            print("""
            ==========================================
            CRAWLER RESTORE TOP
            ==========================================
            Attempt:
                \(attempt)

            Content changed:
                \(currentTopFingerprint != previousTopFingerprint)
            ==========================================
            """)

            /*
             If another upward scroll produces exactly the same
             logical content, the scroll view is no longer moving.

             That means we have reached the top.
             */

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

        // ---------------------------------------------------------
        // 3. Report restoration result
        // ---------------------------------------------------------

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

        // ---------------------------------------------------------
        // IMPORTANT
        //
        // Navigation always uses the original top snapshot.
        //
        // The original snapshot represents the state before
        // scrolling started.
        // ---------------------------------------------------------

        return ScrollableScreenScanResult(
            topSnapshot: initialSnapshot,
            evaluations: collectedEvaluations,
            viewportCount: viewportCount
        )
    }
    
    private func viewportContentFingerprint(
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

            guard node.exists else {
                return
            }

            guard node.visible else {
                return
            }

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

        return nodes.map {
            NavigationAction(node: $0)
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

        let supportedTypes: Set<String> = [
            "XCUIElementTypeButton",
            "XCUIElementTypeLink",
            "XCUIElementTypeCell"
        ]

        guard supportedTypes.contains(node.type) else {
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
            .lowercased()

        guard !text.isEmpty else {
            return false
        }

        let blockedWords = [
            // Destructive actions
            "delete",
            "remove",
            "erase",
            "destroy",

            // Authentication/session actions
            "logout",
            "log out",
            "sign out",
            "signout",
            "login",
            "log in",
            "sign in",
            "signin",

            // Commerce/state-changing actions
            "add to cart",
            "add to bag",
            "remove from cart",
            "remove from bag",
            "add to favourites",
            "add to favorites",
            "remove from favourites",
            "remove from favorites",
            "purchase",
            "buy",
            "checkout",
            "pay",
            "payment",
            "place order",
            "order now",

            // Account/subscription changes
            "subscribe",
            "unsubscribe",
            "cancel subscription",
            "cancel account",
            "close account",

            // Common mutations
            "save",
            "submit",
            "confirm",
            "send",
            "post",
            "create",
            "update",
            "edit",
            "enable",
            "disable"
        ]

        for word in blockedWords {

            if text.contains(word) {
                return false
            }
        }

        return true
    }

    // MARK: - Stable Snapshot

    private func captureStableSnapshot()
        async throws
        -> StableScanSnapshot {

        for attempt in 1...3 {

            let sourceBefore =
                try await appium.getSource()

            let parserBefore =
                WDAElementParser()

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
                WDAElementParser()

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

            if beforeSignature ==
                afterSignature {

                print("""
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
                """)

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
