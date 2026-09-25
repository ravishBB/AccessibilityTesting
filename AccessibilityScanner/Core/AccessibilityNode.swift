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

    var children: [AccessibilityNode]

    // MARK: - Accessibility Helpers

    var isInteractive: Bool {

        let interactiveTypes: Set<String> = [
            "XCUIElementTypeButton",
            "XCUIElementTypeTextField",
            "XCUIElementTypeSecureTextField",
            "XCUIElementTypeSlider",
            "XCUIElementTypeSwitch",
            "XCUIElementTypeStepper",
            "XCUIElementTypePickerWheel"
        ]

        return interactiveTypes.contains(type)
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
        type == "XCUIElementTypeButton"
    }

    var isImage: Bool {
        type == "XCUIElementTypeImage"
    }

    var isAdjustable: Bool {

        type == "XCUIElementTypeSlider" ||
        traits.localizedCaseInsensitiveContains("adjustable")
    }

    var isHiddenFromAccessibility: Bool {

        !visible || !accessible
    }
}
