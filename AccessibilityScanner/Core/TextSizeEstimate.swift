//
//  TextSizeEstimate.swift
//  AccessibilityScanner
//


import Foundation
import CoreGraphics

nonisolated enum TextSizeClass {
    case standard
    case possiblyLarge
    case large
}

nonisolated enum TextSizeEstimate {

    static let largeTextPoints: CGFloat = 18
    static let largeBoldTextPoints: CGFloat = 14

    /// Line height is roughly 1.2× the font size.
    private static let lineHeightFactor: CGFloat = 1.2
    /// Average glyph advance is roughly 0.5× the font size for Latin text.
    private static let averageCharacterWidthFactor: CGFloat = 0.5


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

    static func classify(points: Double) -> TextSizeClass {
        if CGFloat(points) >= largeTextPoints { return .large }
        if CGFloat(points) >= largeBoldTextPoints { return .possiblyLarge }
        return .standard
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

    /// Uses the real font size when the platform exposes it (Android).
    static func classify(_ node: AccessibilityNode) -> TextSizeClass {
        if let points = node.semantics.textSizePoints { return classify(points: points) }
        return classify(frame: node.frame, text: node.label, role: node.role)
    }

    static func classify(_ evaluation: AccessibilityRuleEvaluation) -> TextSizeClass {
        if let points = evaluation.textSizePoints { return classify(points: points) }
        return classify(frame: evaluation.frame, text: evaluation.elementLabel, role: evaluation.elementRole)
    }
}
