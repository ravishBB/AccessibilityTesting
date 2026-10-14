//
//  AccessibilitySourceParser.swift
//  AccessibilityScanner
//


import Foundation

protocol AccessibilitySourceParser {
    func parse(_ xml: String) throws -> AccessibilityNode
}

extension WDAElementParser: AccessibilitySourceParser {}
extension AndroidElementParser: AccessibilitySourceParser {}
