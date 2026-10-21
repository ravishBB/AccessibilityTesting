//
//  ScreenScanResult.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 24/09/26.
//

import Foundation

nonisolated struct ScreenScanResult: Identifiable, Codable {
    let id: UUID
    let name: String
    let signature: String
    let elementCount: Int
    let evaluations: [AccessibilityRuleEvaluation]
    let transitions: [NavigationTransition]

    // Screenshot information
    let screenshot: ScanScreenshot?

    // Elements highlighted on the screenshot
    let annotations: [ScreenshotAnnotation]

    let viewportScreenshots: [ScreenshotViewport]

    init(
        name: String,
        signature: String = "",
        elementCount: Int,
        evaluations: [AccessibilityRuleEvaluation],
        transitions: [NavigationTransition] = [],
        screenshot: ScanScreenshot? = nil,
        annotations: [ScreenshotAnnotation] = [],
        viewportScreenshots: [ScreenshotViewport] = []
    ) {
        self.id = UUID()
        self.name = name
        self.signature = signature
        self.elementCount = elementCount
        self.evaluations = evaluations
        self.transitions = transitions
        self.screenshot = screenshot
        self.annotations = annotations
        self.viewportScreenshots = viewportScreenshots
    }

    /// Results about the whole screen, which the screenshot cannot mark:
    /// Fail first, then Validate, then Pass.
    var screenLevelResults: [AccessibilityRuleEvaluation] {
        let order: [RuleResultStatus: Int] = [.fail: 0, .warning: 0, .validate: 1, .pass: 2]
        return evaluations
            .filter { ScreenshotAnnotation.isScreenLevel($0) && order[$0.status] != nil }
            .sorted { (order[$0.status] ?? 9, $0.ruleName) < (order[$1.status] ?? 9, $1.ruleName) }
    }

    var failures: Int {
        evaluations.filter {
            $0.status == .fail
        }.count
    }

    var warnings: Int {
        evaluations.filter {
            $0.status == .warning
        }.count
    }

    var validations: Int {
        evaluations.filter {
            $0.status == .validate
        }.count
    }

    var passes: Int {
        evaluations.filter {
            $0.status == .pass
        }.count
    }

    var affectedElements: Int {
        Set(
            evaluations
                .filter {
                    $0.status != .pass
                }
                .map {
                    $0.identifier +
                    "|" +
                    $0.elementType +
                    "|" +
                    $0.elementLabel
                }
        ).count
    }
}
