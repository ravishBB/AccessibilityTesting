//
//  ScreenResultBuilder.swift
//  AccessibilityScanner


import Foundation
import CoreGraphics

nonisolated enum ScreenResultBuilder {

    static func build(
        _ crawledScreen: CrawledScreen,
        number: Int,
        scanner: AccessibilityScanner = AccessibilityScanner()
    ) -> ScreenScanResult {

        let elementCount = countNodes(
            crawledScreen.rootNode
        )
        
        let screenshotContext = AccessibilityRuleContext(
            screenshotData: crawledScreen.screenshotData,
            screenshotWidth: crawledScreen.screenshotWidth,
            screenshotHeight: crawledScreen.screenshotHeight,
            hierarchyWidth: crawledScreen.rootNode.frame.width,
            hierarchyHeight: crawledScreen.rootNode.frame.height
        )

        // Build screenshot evidence for every unique viewport discovered
        // while scrolling this screen. This fixes two report problems: the
        // top screenshot being repeated and newly revealed scroll content
        // having no screenshot evidence.
        var viewportScreenshots: [ScreenshotViewport] = []
        var viewportEvaluations: [AccessibilityRuleEvaluation] = []

        for (viewportIndex, capture) in crawledScreen.viewportCaptures.enumerated() {
                                let viewportContext = AccessibilityRuleContext(
                screenshotData: capture.snapshot.screenshotData,
                screenshotWidth: capture.snapshot.screenshotWidth,
                screenshotHeight: capture.snapshot.screenshotHeight,
                hierarchyWidth: capture.snapshot.rootNode.frame.width,
                hierarchyHeight: capture.snapshot.rootNode.frame.height
            )

            let contextualEvaluations = scanner.evaluateForReport(
                rootNode: capture.snapshot.rootNode,
                context: viewportContext
            )

            let evaluations = settled(mergeEvaluations(
                capture.evaluations,
                contextualEvaluations
            ), crawledScreen)
            viewportEvaluations.append(contentsOf: evaluations)

            let annotations = ScreenshotAnnotation.makeAnnotations(
                from: evaluations
            )

            let annotatedImageData = ScreenshotAnnotator().annotate(
                imageData: capture.snapshot.screenshotData,
                screenshotWidth: capture.snapshot.screenshotWidth,
                screenshotHeight: capture.snapshot.screenshotHeight,
                hierarchyWidth: capture.snapshot.rootNode.frame.width,
                hierarchyHeight: capture.snapshot.rootNode.frame.height,
                evaluations: evaluations
            )

            viewportScreenshots.append(
                ScreenshotViewport(
                    index: viewportIndex + 1,
                    screenshot: ScanScreenshot(
                        imageData: storedImage(capture.snapshot.screenshotData),
                        annotatedImageData: annotatedImageData.map { storedImage($0) },
                        width: capture.snapshot.screenshotWidth,
                        height: capture.snapshot.screenshotHeight,
                        hierarchyWidth: capture.snapshot.rootNode.frame.width,
                        hierarchyHeight: capture.snapshot.rootNode.frame.height
                    ),
                    annotations: annotations,
                    checks: ScreenshotAnnotation.makeAnnotations(from: evaluations, statuses: Self.checkStatuses)
                )
            )
        }

        // Defensive fallback for screens that were captured before the
        // viewport capture path existed.
        if viewportScreenshots.isEmpty {
            let contextualEvaluations = settled(scanner.evaluateForReport(
                rootNode: crawledScreen.rootNode,
                context: screenshotContext
            ), crawledScreen)
            viewportEvaluations.append(contentsOf: contextualEvaluations)

            let annotations = ScreenshotAnnotation.makeAnnotations(
                from: contextualEvaluations
            )
            let annotatedImageData = ScreenshotAnnotator().annotate(
                imageData: crawledScreen.screenshotData,
                screenshotWidth: crawledScreen.screenshotWidth,
                screenshotHeight: crawledScreen.screenshotHeight,
                hierarchyWidth: crawledScreen.rootNode.frame.width,
                hierarchyHeight: crawledScreen.rootNode.frame.height,
                evaluations: contextualEvaluations
            )

            viewportScreenshots.append(
                ScreenshotViewport(
                    index: 1,
                    screenshot: ScanScreenshot(
                        imageData: storedImage(crawledScreen.screenshotData),
                        annotatedImageData: annotatedImageData.map { storedImage($0) },
                        width: crawledScreen.screenshotWidth,
                        height: crawledScreen.screenshotHeight,
                        hierarchyWidth: crawledScreen.rootNode.frame.width,
                        hierarchyHeight: crawledScreen.rootNode.frame.height
                    ),
                    annotations: annotations,
                    checks: ScreenshotAnnotation.makeAnnotations(from: contextualEvaluations, statuses: Self.checkStatuses)
                )
            )
        }

        var nextAnnotationNumber = 1
        // Checks are numbered within their filter (Fail, Validate, Pass), so
        // the list for each filter reads 1, 2, 3… across all viewports.
        var nextCheckNumber: [ScreenshotCheckFilter: Int] = [:]
        // Runtime and whole-screen results join the first viewport's list so
        // the Fail / Validate / Pass filters show them with everything else.
        let screenLevelChecks = ScreenshotAnnotation.makeScreenLevelAnnotations(
            from: settled(mergeEvaluations(
                mergeEvaluations(crawledScreen.evaluations, viewportEvaluations),
                crawledScreen.keyboardFocusEvaluations
            ), crawledScreen),
            statuses: Self.checkStatuses
        )
        if !screenLevelChecks.isEmpty, let first = viewportScreenshots.first {
            viewportScreenshots[0] = ScreenshotViewport(
                index: first.index,
                screenshot: first.screenshot,
                annotations: first.annotations,
                checks: screenLevelChecks + (first.checks ?? [])
            )
        }

        var normalizedViewports: [ScreenshotViewport] = []
        var allAnnotations: [ScreenshotAnnotation] = []

        for viewport in viewportScreenshots {
            let normalizedAnnotations = viewport.annotations.map { annotation -> ScreenshotAnnotation in
                let normalized = annotation.renumbered(nextAnnotationNumber)
                nextAnnotationNumber += 1
                allAnnotations.append(normalized)
                return normalized
            }

            let normalizedChecks = viewport.checks?.map { check -> ScreenshotAnnotation in
                let filter = ScreenshotCheckFilter(check.displayStatus)
                let number = nextCheckNumber[filter, default: 1]
                nextCheckNumber[filter] = number + 1
                return check.renumbered(number)
            }

            normalizedViewports.append(
                ScreenshotViewport(
                    index: viewport.index,
                    screenshot: viewport.screenshot,
                    annotations: normalizedAnnotations,
                    checks: normalizedChecks
                )
            )
        }

        let evaluations = settled(mergeEvaluations(
            mergeEvaluations(
                crawledScreen.evaluations,
                viewportEvaluations
            ),
            crawledScreen.keyboardFocusEvaluations
        ), crawledScreen)

        let primaryScreenshot = normalizedViewports.first?.screenshot
            ?? ScanScreenshot(
                imageData: storedImage(crawledScreen.screenshotData),
                width: crawledScreen.screenshotWidth,
                height: crawledScreen.screenshotHeight,
                hierarchyWidth: crawledScreen.rootNode.frame.width,
                hierarchyHeight: crawledScreen.rootNode.frame.height
            )

        return ScreenScanResult(
            name: ScreenNaming.name(for: crawledScreen.rootNode, number: number),
            signature: crawledScreen.signature,
            elementCount: elementCount,
            evaluations: evaluations,
            transitions: crawledScreen.transitions,
            screenshot: primaryScreenshot,
            annotations: allAnnotations,
            viewportScreenshots: normalizedViewports
        )
    }

    /// Screenshots kept in a finished report. Rules have already run on the
    /// full-resolution PNG; what is kept is only shown or exported (both at
    /// most 900 px), so a 1600 px JPEG cuts memory and saved-report size by
    /// roughly 85% with no visible loss.
    static let checkStatuses: Set<RuleResultStatus> = [.fail, .warning, .validate, .pass]

    static func storedImage(_ data: Data) -> Data {
        ReportImageEncoder.encode(data, maxPixelSize: 1600, quality: 0.82)?.data ?? data
    }

    /// Results in `additions` replace results in `base` for the same rule and
    /// element; the rest of `additions` is appended.
    static func mergeEvaluations(
        _ base: [AccessibilityRuleEvaluation],
        _ additions: [AccessibilityRuleEvaluation]
    ) -> [AccessibilityRuleEvaluation] {
        var replacementByKey: [String: AccessibilityRuleEvaluation] = [:]
        for evaluation in additions {
            replacementByKey[evaluationKey(evaluation)] = evaluation
        }

        var result: [AccessibilityRuleEvaluation] = []
        var consumed = Set<String>()
        let baseKeys = Set(base.map(evaluationKey))

        for evaluation in base {
            let key = evaluationKey(evaluation)
            if let replacement = replacementByKey[key] {
                result.append(replacement)
                consumed.insert(key)
            } else {
                result.append(evaluation)
            }
        }

        for evaluation in additions {
            let key = evaluationKey(evaluation)
            if !consumed.contains(key) && !baseKeys.contains(key) {
                result.append(evaluation)
                consumed.insert(key)
            }
        }

        return result
    }

    /// Results with the screen's runtime verdicts applied. The rules run
    /// again on every viewport here, so a verdict the crawler reached (a row
    /// that opened a screen) is applied after them, not before.
    private static func settled(_ evaluations: [AccessibilityRuleEvaluation], _ screen: CrawledScreen) -> [AccessibilityRuleEvaluation] {
        screen.rowTap?.settle(evaluations) ?? evaluations
    }

    static func evaluationKey(_ evaluation: AccessibilityRuleEvaluation) -> String {
        [
            evaluation.ruleID,
            evaluation.elementType,
            evaluation.identifier,
            evaluation.elementLabel,
            String(format: "%.1f", evaluation.frameX),
            String(format: "%.1f", evaluation.frameY),
            String(format: "%.1f", evaluation.frameWidth),
            String(format: "%.1f", evaluation.frameHeight)
        ].joined(separator: "|")
    }

    static func countNodes(_ node: AccessibilityNode) -> Int {
        if node.identifier == "A11YScannerIgnore" {
            return 0
        }
        return 1 + node.children.reduce(0) { $0 + countNodes($1) }
    }
}
