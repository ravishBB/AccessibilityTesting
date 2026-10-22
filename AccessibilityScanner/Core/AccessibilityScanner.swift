//
//  AccessibilityScanner.swift
//  AccessibilityScannerDemo
//
//  Created by Ravish Kumar on 21/09/26.

import Foundation

nonisolated final class AccessibilityScanner {
    private let rules: [AccessibilityRule]
    

    init(
        rules: [AccessibilityRule] = AccessibilityRules.all
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
        rootNode: AccessibilityNode,
        context: AccessibilityRuleContext? = nil
    ) -> [AccessibilityRuleEvaluation] {

        var evaluations: [AccessibilityRuleEvaluation] = []

        evaluateNode(
            rootNode,
            evaluations: &evaluations,
            context: context
        )

        // Evaluate hierarchy-wide rules once. These rules need sibling or
        // geometric context and cannot be implemented correctly per element.
        for rule in rules {
            if let context, let contextualRule = rule as? ContextualScreenAccessibilityRule {
                evaluations.append(contentsOf: contextualRule.evaluate(rootNode: rootNode, context: context))
                continue
            }
            guard let screenRule = rule as? ScreenAccessibilityRule else { continue }
            evaluations.append(contentsOf: screenRule.evaluate(rootNode: rootNode))
        }

        return evaluations
    }

    private func evaluateNode(
        _ node: AccessibilityNode,
        evaluations: inout [AccessibilityRuleEvaluation],
        context: AccessibilityRuleContext?
    ) {
        guard node.exists else {
            return
        }

        // Run every rule against this element.
        for rule in rules {
            let evaluation: AccessibilityRuleEvaluation?

            if let contextualRule = rule as? ContextualAccessibilityRule,
               let context {
                evaluation = contextualRule.evaluate(
                    node: node,
                    context: context
                )
            } else {
                evaluation = rule.evaluate(
                    node: node
                )
            }

            if let evaluation {
                evaluations.append(evaluation)
            }
        }

        // Recursively evaluate children.
        for child in node.children {
            evaluateNode(
                child,
                evaluations: &evaluations,
                context: context
            )
        }
    }

    // MARK: - Report

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

    private func findVisibleTextElements(
        _ node: AccessibilityNode
    ) -> [String] {

        var result: [String] = []

        if node.visible {

            let textRoles: Set<AccessibilityRole> = [
                .staticText,
                .navigationBar
            ]

            if textRoles.contains(
                node.role
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
