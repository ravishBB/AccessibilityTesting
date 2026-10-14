//
//  MobilePlatform.swift
//  AccessibilityScanner


import Foundation

nonisolated enum MobilePlatform: String, Codable, Hashable, CaseIterable {

    case ios
    case android

    var displayName: String {
        switch self {
        case .ios: return "iOS"
        case .android: return "Android"
        }
    }

    var sizeUnit: String {
        switch self {
        case .ios: return "pt"
        case .android: return "dp"
        }
    }

    var recommendedTargetSize: Double {
        switch self {
        case .ios: return 44
        case .android: return 48
        }
    }

    var minimumTargetSize: Double { 24 }

    static func infer(fromElementType type: String) -> MobilePlatform {
        if type.hasPrefix("XCUIElementType") { return .ios }
        if type.contains(".") || type == "hierarchy" { return .android }
        return .ios
    }
}
