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

    // Set by `annotatingLayout()` from the node's ancestors.

    /// Cut off by the edge of a scrolling container, so its size and colours
    /// in this snapshot are not the real ones. Another viewport shows it whole.
    var partiallyVisible: Bool = false
    /// Inside a control or clickable row, so its text is part of that
    /// control's name rather than standalone text.
    var insideActionable: Bool = false
    /// Not focusable or clickable itself but inside one that is (a Compose
    /// Checkbox inside a toggleable Row): screen readers and touch treat the
    /// ancestor as the control, so this node is not checked on its own.
    var mergedIntoAncestor: Bool = false
}

extension AccessibilityNode {

    /// Fills the layout-dependent semantics that need the ancestors.
    nonisolated func annotatingLayout() -> AccessibilityNode {
        var bars: [CGRect] = []
        func collectBars(_ node: AccessibilityNode) {
            if node.isBar, node.visible, node.frame.width > 0, node.frame.height > 0 {
                bars.append(node.frame)
                return
            }
            node.children.forEach(collectBars)
        }
        collectBars(self)
        return annotated(scrollFrame: nil, actionableAncestor: false, controlAncestor: false, elementAncestor: false,
                         bars: bars, insideBar: false)
    }

    /// Navigation bar, tab bar or toolbar: fixed chrome that scrolling
    /// content passes under.
    private nonisolated var isBar: Bool {
        role == .navigationBar || role == .tabBar || role == .statusBar || type == "XCUIElementTypeToolbar"
    }

    private nonisolated var isActionable: Bool {
        if platform == .android {
            let words = Set(traits.split(separator: " "))
            return words.contains("clickable") || words.contains("long-clickable") || words.contains("focusable")
        }
        return hittable && AccessibilityRole.controls.contains(role)
    }

    /// Any element below this one is exposed to assistive technology.
    nonisolated var hasAccessibleDescendant: Bool {
        children.contains { $0.accessible || $0.hasAccessibleDescendant }
    }

    private nonisolated var isScrollingContainer: Bool {
        role == .scrollView || role == .table ||
            type.contains("ScrollView") || type.contains("RecyclerView") ||
            type.contains("CollectionView") || type.contains("ListView") ||
            Set(traits.split(separator: " ")).contains("scrollable")
    }

    private nonisolated func annotated(
        scrollFrame: CGRect?,
        actionableAncestor: Bool,
        controlAncestor: Bool,
        elementAncestor: Bool,
        bars: [CGRect],
        insideBar: Bool
    ) -> AccessibilityNode {
        var node = self

        // Scrolled under a navigation or tab bar: partly hidden by it.
        if !insideBar, !isBar, frame.width > 0, frame.height > 0,
           bars.contains(where: { bar in
               let overlap = bar.intersection(frame)
               return !overlap.isNull && overlap.width > 1 && overlap.height > 1 && !bar.contains(frame) || bar.contains(frame) && scrollFrame != nil
           }) {
            node.semantics.partiallyVisible = true
        }

        if let scrollFrame, frame.width > 0, frame.height > 0, frame != scrollFrame {
            if !scrollFrame.insetBy(dx: -0.5, dy: -0.5).contains(frame) {
                node.semantics.partiallyVisible = true
            } else if platform == .android {
                // UiAutomator2 clips bounds to the visible area, so a node cut
                // off by the container ends exactly on its edge.
                let touchesVertical = abs(frame.minY - scrollFrame.minY) < 0.75 || abs(frame.maxY - scrollFrame.maxY) < 0.75
                let touchesHorizontal = abs(frame.minX - scrollFrame.minX) < 0.75 || abs(frame.maxX - scrollFrame.maxX) < 0.75
                let spansHeight = frame.height >= scrollFrame.height - 1
                let spansWidth = frame.width >= scrollFrame.width - 1
                node.semantics.partiallyVisible = (touchesVertical && !spansHeight) ||
                    (touchesHorizontal && !spansWidth && frame.minX > scrollFrame.minX + 0.75)
            }
        }

        // A line of text is never under 9 dp tall; shorter text bounds were
        // clipped by a parent (a card or list item cut off by the viewport).
        if platform == .android, role == .staticText, frame.height > 0, frame.height < 9 {
            node.semantics.partiallyVisible = true
        }

        node.semantics.insideActionable = controlAncestor
        // Android: TalkBack and touch use the clickable parent. iOS: inside
        // an accessibility element (a SwiftUI Toggle's inner UISwitch, a
        // combined cell) VoiceOver only reaches the element itself.
        node.semantics.mergedIntoAncestor = platform == .android
            ? actionableAncestor && !isActionable
            : elementAncestor

        let childScroll = isScrollingContainer && frame.width > 0 && frame.height > 0 ? frame : scrollFrame
        let childActionable = actionableAncestor || isActionable
        let childControl = controlAncestor || isActionable ||
            AccessibilityRole.controls.contains(role) || role == .cell
        // A real VoiceOver element hides its subtree: WDA still lists the
        // children, but as not accessible. A UIKit table cell is reported
        // accessible while its labels and buttons are accessible too: it is
        // a container VoiceOver moves into, not one stop.
        let childElement = elementAncestor ||
            (platform == .ios && accessible && type != "XCUIElementTypeApplication" && !hasAccessibleDescendant)
        // The A11yInspect framework's floating scan button is a testing
        // overlay, not part of the app under test.
        node.children = children.filter { $0.identifier != "A11YScannerIgnore" }.map {
            $0.annotated(scrollFrame: childScroll, actionableAncestor: childActionable, controlAncestor: childControl,
                         elementAncestor: childElement, bars: bars, insideBar: insideBar || isBar)
        }
        return node
    }
}
