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
