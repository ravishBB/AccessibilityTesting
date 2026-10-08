//
//  AccessibilityNode.swift
//  AccessibilityScannerDemo
//
//  Created by Ravish Kumar on 21/09/26.
//

import Foundation
import CoreGraphics

struct AccessibilityNode {

    let type: String
    let identifier: String
    let label: String
    let value: String?

    let placeholderValue: String?
    let traits: String

    let frame: CGRect

    let exists: Bool
    let hittable: Bool
    let enabled: Bool
    let visible: Bool
    let accessible: Bool
    /// Whether XCTest/WDA currently reports keyboard focus on this element.
    /// Older/non-iOS parsers default this to false.
    let focused: Bool

    var children: [AccessibilityNode]

    /// Platform the node was captured on. Defaults to iOS so existing
    /// call sites keep working.
    var platform: MobilePlatform = .ios

    /// Set by platform parsers when the role cannot be derived from `type`
    /// alone (for example a clickable generic Android `View`).
    var roleOverride: AccessibilityRole? = nil

    // MARK: - Role

    var role: AccessibilityRole {
        roleOverride ?? AccessibilityRole.resolve(type: type)
    }

    /// Android `ImageButton` / FAB: the control itself is the image.
    var isImageButtonClass: Bool {
        type.hasSuffix("ImageButton") || type.contains("FloatingActionButton")
    }

    // MARK: - Accessibility Helpers

    var isInteractive: Bool {
        AccessibilityRole.controls.contains(role)
    }

    /// Native/platform focusability exposed by Appium. This is especially
    /// important for Flutter Semantics nodes and React Native `accessible`
    /// views, where the raw Android class may remain a generic View.
    var isKeyboardFocusable: Bool {
        traits.localizedCaseInsensitiveContains("focusable")
    }

    var hasAccessibleName: Bool {

        !label
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty
    }

    var hasValue: Bool {

        guard let value else {
            return false
        }

        return !value
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty
    }

    var isButton: Bool {
        role == .button
    }

    var isImage: Bool {
        role == .image
    }

    var isAdjustable: Bool {

        role == .slider ||
        traits.localizedCaseInsensitiveContains("adjustable")
    }

    var isHiddenFromAccessibility: Bool {

        !visible || !accessible
    }
}
