//
//  ScreenSignature.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 25/09/26.
//

import Foundation
import CoreGraphics

struct ScreenSignature: Hashable {

    let value: String

    init(rootNode: AccessibilityNode) {
        self.value = ScreenSignature.buildSignature(
            from: rootNode
        )
    }

    private static func buildSignature(
        from node: AccessibilityNode
    ) -> String {

        var components: [String] = []

        appendSignature(
            node: node,
            to: &components
        )

        return components.joined(separator: "||")
    }

    private static func appendSignature(
        node: AccessibilityNode,
        to components: inout [String]
    ) {

        // Ignore the scanner's own UI.
        if node.identifier == "A11YScannerIgnore" {
            return
        }

        let type = node.type

        let identifier =
            normalize(node.identifier)

        let label =
            normalize(node.label)

        let placeholder =
            normalize(node.placeholderValue)

        let frame =
            String(
                format: "%.0f,%.0f,%.0f,%.0f",
                node.frame.origin.x,
                node.frame.origin.y,
                node.frame.width,
                node.frame.height
            )

        let component = [
            type,
            identifier,
            label,
            placeholder,
            frame,
            node.visible ? "v1" : "v0",
            node.accessible ? "a1" : "a0"
        ]
        .joined(separator: "|")

        components.append(component)

        for child in node.children {

            appendSignature(
                node: child,
                to: &components
            )
        }
    }

    private static func normalize(
        _ value: String
    ) -> String {

        value
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()
    }

    private static func normalize(
        _ value: String?
    ) -> String {

        normalize(value ?? "")
    }
}
