//
//  ScannerBuildInfo.swift
//  AccessibilityScanner
//
//  Identifies which scanner build and rule set produced a report, so results
//  can be reproduced and compared across versions.
//

import Foundation

enum ScannerBuildInfo {

    static let productName = "Accessibility Scanner"

    /// Marketing version from the app bundle, e.g. "1.0".
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    /// Build number from the app bundle, e.g. "1".
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var displayVersion: String {
        "\(version) (\(build))"
    }

    static var ruleSetVersion: String {
        AccessibilityRuleCatalog.version
    }

    /// WCAG version the catalog maps to.
    static let wcagVersion = "WCAG 2.2"
}
