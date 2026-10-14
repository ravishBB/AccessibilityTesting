//
//  AccessibilityRule.swift
//  AccessibilityScannerDemo
//
//  Created by Ravish Kumar on 21/09/26.
//


import Foundation

nonisolated protocol AccessibilityRule {

    var id: String { get }

    var title: String { get }

    var description: String { get }

    func evaluate(
        node: AccessibilityNode
    ) -> AccessibilityRuleEvaluation?
}

nonisolated protocol ScreenAccessibilityRule: AccessibilityRule {

    func evaluate(
        rootNode: AccessibilityNode
    ) -> [AccessibilityRuleEvaluation]
}

nonisolated protocol ContextualScreenAccessibilityRule {

    func evaluate(
        rootNode: AccessibilityNode,
        context: AccessibilityRuleContext
    ) -> [AccessibilityRuleEvaluation]
}
