//
//  RuleResultStatus.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 24/09/26.
//

import Foundation

enum RuleResultStatus: String, Codable, CaseIterable {
    case pass
    case fail
    case warning
    case validate

    var displayName: String {
        switch self {
        case .pass:
            return "PASS"
        case .fail:
            return "FAIL"
        case .warning:
            return "WARNING"
        case .validate:
            return "VALIDATE"
        }
    }
}
