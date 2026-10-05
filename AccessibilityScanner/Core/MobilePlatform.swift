//
//  MobilePlatform.swift
//  AccessibilityScanner
//
//  Platform abstraction so the scanner can drive iOS (XCUITest/WDA) and
//  Android (UiAutomator2) devices through the same Appium pipeline.
//

import Foundation

enum MobilePlatform: String, Codable, Hashable, CaseIterable {

    case ios
    case android

    var displayName: String {
        switch self {
        case .ios: return "iOS"
        case .android: return "Android"
        }
    }

    /// Unit used for frames after normalisation. Android pixel bounds are
    /// converted to density-independent pixels so they are comparable with
    /// iOS points.
    var sizeUnit: String {
        switch self {
        case .ios: return "pt"
        case .android: return "dp"
        }
    }

    /// Recommended minimum touch target.
    /// iOS: 44pt (Apple HIG). Android: 48dp (Material / Android guidance).
    var recommendedTargetSize: Double {
        switch self {
        case .ios: return 44
        case .android: return 48
        }
    }

    /// WCAG 2.5.8 minimum target size.
    var minimumTargetSize: Double { 24 }

    /// Infers the platform from a raw element type string.
    /// iOS types are `XCUIElementType*`; Android types are Java class names.
    static func infer(fromElementType type: String) -> MobilePlatform {
        if type.hasPrefix("XCUIElementType") { return .ios }
        if type.contains(".") || type == "hierarchy" { return .android }
        return .ios
    }
}
