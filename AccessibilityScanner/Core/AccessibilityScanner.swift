//
//  AccessibilityScanner.swift
//  AccessibilityScannerDemo
//
//  Created by Ravish Kumar on 21/09/26.
//

import Foundation

final class AccessibilityScanner {
    private let rules: [AccessibilityRule]
    

    init(
        rules: [AccessibilityRule] = [
            AccessibleNameRule(),
            TouchTargetRule()
        ]
    ) {
        self.rules = rules
    }

    // MARK: - Public Scan

    func scan(
        rootNode: AccessibilityNode
    ) -> [AccessibilityFinding] {

        let evaluations = evaluateForReport(
            rootNode: rootNode
        )

        return evaluations.compactMap { evaluation in
            guard
                evaluation.status == .fail ||
                evaluation.status == .warning
            else {
                return nil
            }

            return AccessibilityFinding(
                ruleID: evaluation.ruleID,
                severity: evaluation.severity,
                message: evaluation.message,
                elementType: evaluation.elementType,
                elementLabel: evaluation.elementLabel,
                identifier: evaluation.identifier,
                value: evaluation.value,
                frame: evaluation.frame,
                remediation: evaluation.remediation
            )
        }
    }

    // MARK: - Evaluation

    func evaluateForReport(
        rootNode: AccessibilityNode
    ) -> [AccessibilityRuleEvaluation] {

        var evaluations: [AccessibilityRuleEvaluation] = []

        evaluateNode(
            rootNode,
            evaluations: &evaluations
        )

        return evaluations
    }

    private func evaluateNode(
        _ node: AccessibilityNode,
        evaluations: inout [AccessibilityRuleEvaluation]
    ) {
        guard node.exists else {
            return
        }

        // Run every rule against this element.
        for rule in rules {
            if let evaluation = rule.evaluate(
                node: node
            ) {
                evaluations.append(evaluation)
            }
        }

        // Recursively evaluate children.
        for child in node.children {
            evaluateNode(
                child,
                evaluations: &evaluations
            )
        }
    }

    // MARK: - Report

    func scanReport(
        rootNode: AccessibilityNode,
        applicationName: String,
        bundleID: String,
        deviceName: String,
        deviceUDID: String,
        screenName: String? = nil,
        screenshot: ScanScreenshot? = nil,
        annotations: [ScreenshotAnnotation] = []
    ) -> AccessibilityScanResult {

        let startedAt = Date()

        // Evaluate the hierarchy once.
        let evaluations = evaluateForReport(
            rootNode: rootNode
        )

        let elementCount = countRelevantElements(
            rootNode
        )

        let resolvedScreenName =
            screenName ??
            inferScreenName(
                rootNode: rootNode,
                applicationName: applicationName
            )

        let screen = ScreenScanResult(
            name: resolvedScreenName,
            elementCount: elementCount,
            evaluations: evaluations,
            screenshot: screenshot,
            annotations: annotations
        )

        let finishedAt = Date()

        return AccessibilityScanResult(
            applicationName: applicationName,
            bundleID: bundleID,
            deviceName: deviceName,
            deviceUDID: deviceUDID,
            startedAt: startedAt,
            finishedAt: finishedAt,
            screens: [screen],
            rulesExecuted: rules.count
        )
    }

    // MARK: - Element Count

    private func countRelevantElements(
        _ node: AccessibilityNode
    ) -> Int {

        var count = 0

        if node.exists,
           node.visible {
            count += 1
        }

        for child in node.children {
            count += countRelevantElements(
                child
            )
        }

        return count
    }

    // MARK: - Screen Name

    private func inferScreenName(
        rootNode: AccessibilityNode,
        applicationName: String
    ) -> String {

        let candidates =
            findVisibleTextElements(
                rootNode
            )

        for candidate in candidates {
            let text =
                candidate.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

            if !text.isEmpty,
               text.count <= 60 {
                return text
            }
        }

        return "Current Screen"
    }

    private func findVisibleTextElements(
        _ node: AccessibilityNode
    ) -> [String] {

        var result: [String] = []

        if node.visible {

            let textTypes: Set<String> = [
                "XCUIElementTypeStaticText",
                "XCUIElementTypeNavigationBar"
            ]

            if textTypes.contains(
                node.type
            ) {

                let label =
                    node.label.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

                if !label.isEmpty {
                    result.append(label)
                }
            }
        }

        for child in node.children {
            result.append(
                contentsOf:
                    findVisibleTextElements(
                        child
                    )
            )
        }

        return result
    }
}
