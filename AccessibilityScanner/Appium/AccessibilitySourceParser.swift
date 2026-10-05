//
//  AccessibilitySourceParser.swift
//  AccessibilityScanner
//
//  Common interface for turning an Appium page-source XML string into the
//  scanner's platform-neutral AccessibilityNode tree.
//

import Foundation

protocol AccessibilitySourceParser {
    func parse(_ xml: String) throws -> AccessibilityNode
}

extension WDAElementParser: AccessibilitySourceParser {}
extension AndroidElementParser: AccessibilitySourceParser {}
