//
//  AccessibilityNode.swift
//  AccessibilityScannerDemo
//
//  Created by Ravish Kumar on 21/09/26.
//

import Foundation
import CoreGraphics

nonisolated struct AccessibilityNode {

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

    /// Semantics only some platforms expose. Unknown values stay nil, so a
    /// rule can tell "not exposed" apart from "false".
    var semantics = PlatformSemantics()

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

/// Accessibility data beyond the common XCUITest/UiAutomator2 fields.
/// UiAutomator2 exposes most of these on Android (native, React Native and
/// Flutter); WebDriverAgent exposes only custom actions on iOS.
nonisolated struct PlatformSemantics: Hashable {
    /// Visible text of the view when it differs from its accessible name
    /// (Android `text` when `content-desc` is also set).
    var visibleText: String? = nil
    /// Android `hint` on a view that is not a text input, and `tooltip-text`.
    var hint: String? = nil
    var tooltip: String? = nil
    /// Android `a11y-important`: false means TalkBack skips the view.
    var importantForAccessibility: Bool? = nil
    /// Android `heading`.
    var isHeading: Bool? = nil
    /// Android `live-region`: 0 none, 1 polite, 2 assertive.
    var liveRegion: Int? = nil
    /// Android `error` (error text set on a field) and `content-invalid`.
    var errorText: String? = nil
    var contentInvalid: Bool? = nil
    /// Android `input-type` (android.text.InputType flags).
    var inputType: Int? = nil
    /// Rendered font size in sp (Android `text-size`, converted from px).
    var textSizePoints: Double? = nil
    /// Android `pane-title`: the title of a window or screen pane.
    var paneTitle: String? = nil
    /// Custom accessibility actions (iOS `customActions`, Android custom
    /// entries in `actions`).
    var customActions: [String] = []
    /// True when the role was guessed from behaviour (a clickable generic
    /// view) rather than exposed by the app: the role is missing.
    var roleInferred: Bool = false
}
