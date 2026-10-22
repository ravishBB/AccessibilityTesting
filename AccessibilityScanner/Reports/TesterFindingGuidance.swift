//
//  TesterFindingGuidance.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 25/09/26.
//


import Foundation

nonisolated extension AccessibilityRuleEvaluation {

    var targetDescription: String {
        let name = elementLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        if !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return identifier }
        return elementRole.rawValue
    }

}
