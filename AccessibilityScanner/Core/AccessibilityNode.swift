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
    let focused: Bool

    var children: [AccessibilityNode]
    var platform: MobilePlatform = .ios
    var roleOverride: AccessibilityRole? = nil
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

nonisolated struct PlatformSemantics: Hashable {
    var visibleText: String? = nil
    var hint: String? = nil
    var tooltip: String? = nil
    var importantForAccessibility: Bool? = nil
    var isHeading: Bool? = nil
    var liveRegion: Int? = nil
    var errorText: String? = nil
    var contentInvalid: Bool? = nil
    var inputType: Int? = nil
    var textSizePoints: Double? = nil
    var paneTitle: String? = nil
    var customActions: [String] = []
    var roleInferred: Bool = false
    var partiallyVisible: Bool = false
    var insideActionable: Bool = false
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
                let touchesVertical = abs(frame.minY - scrollFrame.minY) < 0.75 || abs(frame.maxY - scrollFrame.maxY) < 0.75
                let touchesHorizontal = abs(frame.minX - scrollFrame.minX) < 0.75 || abs(frame.maxX - scrollFrame.maxX) < 0.75
                let spansHeight = frame.height >= scrollFrame.height - 1
                let spansWidth = frame.width >= scrollFrame.width - 1
                node.semantics.partiallyVisible = (touchesVertical && !spansHeight) ||
                    (touchesHorizontal && !spansWidth && frame.minX > scrollFrame.minX + 0.75)
            }
        }

        if platform == .android, role == .staticText, frame.height > 0, frame.height < 9 {
            node.semantics.partiallyVisible = true
        }

        node.semantics.insideActionable = controlAncestor
        node.semantics.mergedIntoAncestor = platform == .android
            ? actionableAncestor && !isActionable
            : elementAncestor

        let childScroll = isScrollingContainer && frame.width > 0 && frame.height > 0 ? frame : scrollFrame
        let childActionable = actionableAncestor || isActionable
        let childControl = controlAncestor || isActionable ||
            AccessibilityRole.controls.contains(role) || role == .cell
        let childElement = elementAncestor ||
            (platform == .ios && accessible && type != "XCUIElementTypeApplication" && !hasAccessibleDescendant)
        node.children = children.filter { $0.identifier != "A11YScannerIgnore" }.map {
            $0.annotated(scrollFrame: childScroll, actionableAncestor: childActionable, controlAncestor: childControl,
                         elementAncestor: childElement, bars: bars, insideBar: insideBar || isBar)
        }
        return node
    }
}
