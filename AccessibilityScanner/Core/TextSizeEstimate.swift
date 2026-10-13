//
//  TextSizeEstimate.swift
//  AccessibilityScanner
//
//  Neither XCUITest nor UiAutomator exposes font size or weight, so the
//  contrast rules estimate the font size from the element frame and its text
//  length to decide between the standard-text and large-text thresholds.
//
//  WCAG large text is at least 18pt, or 14pt bold. iOS points and Android sp
//  are used directly as pt, as Accessibility Inspector and Android
//  Accessibility Scanner do. Weight is unknown, so text between 14pt and 18pt
//  is "possiblyLarge": it is held to the standard threshold, and a result that
//  only passes the large-text threshold goes to manual review.
//

import Foundation
import CoreGraphics

enum TextSizeClass {
    case standard
    case possiblyLarge
    case large
}

enum TextSizeEstimate {

    static let largeTextPoints: CGFloat = 18
    static let largeBoldTextPoints: CGFloat = 14

    /// Line height is roughly 1.2× the font size.
    private static let lineHeightFactor: CGFloat = 1.2
    /// Average glyph advance is roughly 0.5× the font size for Latin text.
    private static let averageCharacterWidthFactor: CGFloat = 0.5

    /// Estimated font size in points/sp, or nil when it cannot be estimated.
    ///
    /// Single line: frame height / 1.2. Multi-line: from area, since
    /// characters × 0.5 × size × 1.2 × size ≈ width × height. The smaller of
    /// the two is used: the first overestimates wrapped text and the second
    /// overestimates a short label in a wide frame.
    static func fontSize(frame: CGRect, text: String) -> CGFloat? {
        let characters = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard characters > 0, frame.width > 0, frame.height > 0 else { return nil }

        let singleLine = frame.height / lineHeightFactor
        let fromArea = sqrt(
            (frame.width * frame.height) /
            (CGFloat(characters) * averageCharacterWidthFactor * lineHeightFactor)
        )
        return min(singleLine, fromArea)
    }

    static func classify(frame: CGRect, text: String, role: AccessibilityRole) -> TextSizeClass {
        // Input frames include padding, and the typed text is body size.
        if role == .textField || role == .secureTextField {
            return .standard
        }
        guard let size = fontSize(frame: frame, text: text) else { return .standard }
        if size >= largeTextPoints { return .large }
        if size >= largeBoldTextPoints { return .possiblyLarge }
        return .standard
    }

    static func classify(_ node: AccessibilityNode) -> TextSizeClass {
        classify(frame: node.frame, text: node.label, role: node.role)
    }

    static func classify(_ evaluation: AccessibilityRuleEvaluation) -> TextSizeClass {
        classify(frame: evaluation.frame, text: evaluation.elementLabel, role: evaluation.elementRole)
    }
}
