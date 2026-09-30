//
//  AccessibilityRule.swift
//  AccessibilityScannerDemo
//
//  Created by Ravish Kumar on 21/09/26.
//


import Foundation

protocol AccessibilityRule {

    var id: String { get }

    var title: String { get }

    var description: String { get }

    func evaluate(
        node: AccessibilityNode
    ) -> AccessibilityRuleEvaluation?
}

// Rules that require the complete accessibility hierarchy rather than a
// single element implement this protocol. These rules are evaluated once
// after the normal per-node rules have finished.
protocol ScreenAccessibilityRule: AccessibilityRule {

    func evaluate(
        rootNode: AccessibilityNode
    ) -> [AccessibilityRuleEvaluation]
}
