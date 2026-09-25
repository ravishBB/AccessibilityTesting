//
//  AccessibilityFinding.swift
//  AccessibilityScannerDemo
//
//  Created by Ravish Kumar on 21/09/26.
//

import Foundation
import CoreGraphics

struct AccessibilityFinding {

    let ruleID: String
    let severity: Severity
    let message: String

    let elementType: String
    let elementLabel: String
    let identifier: String
    let value: String?

    let frame: CGRect

    let remediation: String

    enum Severity: String, Codable, CaseIterable {
        case error
        case warning
        case info

        var displayName: String {
            switch self {
            case .error:
                return "Error"
            case .warning:
                return "Warning"
            case .info:
                return "Info"
            }
        }
    }

    init(
        ruleID: String,
        message: String,
        elementLabel: String
    ) {
        self.ruleID = ruleID
        self.severity = .error
        self.message = message
        self.elementType = "unknown"
        self.elementLabel = elementLabel
        self.identifier = ""
        self.value = nil
        self.frame = .zero
        self.remediation = ""
    }

    init(
        ruleID: String,
        severity: Severity,
        message: String,
        elementType: String,
        elementLabel: String,
        identifier: String,
        value: String?,
        frame: CGRect,
        remediation: String
    ) {
        self.ruleID = ruleID
        self.severity = severity
        self.message = message
        self.elementType = elementType
        self.elementLabel = elementLabel
        self.identifier = identifier
        self.value = value
        self.frame = frame
        self.remediation = remediation
    }
}
