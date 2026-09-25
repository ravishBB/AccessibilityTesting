//
//  NavigationAction.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 25/09/26.
//

import Foundation
import CoreGraphics

struct NavigationAction:
    Identifiable,
    Hashable {

    let id: String
    let label: String
    let identifier: String
    let type: String
    let frame: CGRect

    init(node: AccessibilityNode) {

        self.label = node.label
        self.identifier = node.identifier
        self.type = node.type
        self.frame = node.frame

        self.id =
            node.identifier +
            "|" +
            node.label +
            "|" +
            node.type +
            "|" +
            String(
                format: "%.1f",
                node.frame.origin.x
            ) +
            "|" +
            String(
                format: "%.1f",
                node.frame.origin.y
            )
    }

    var displayName: String {

        if !label
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty {

            return label
        }

        if !identifier
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty {

            return identifier
        }

        return type
    }

    var xpath: String? {

        let escapedIdentifier =
            Self.escapeXPath(identifier)

        if !identifier
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty {

            return
                "//*[@name=\(escapedIdentifier)]"
        }

        let escapedLabel =
            Self.escapeXPath(label)

        if !label
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty {

            return
                "//*[@label=\(escapedLabel)]"
        }

        return nil
    }

    private static func escapeXPath(
        _ value: String
    ) -> String {

        if !value.contains("'") {

            return "'\(value)'"
        }

        if !value.contains("\"") {

            return "\"\(value)\""
        }

        let pieces =
            value.components(
                separatedBy: "'"
            )

        let joined =
            pieces.enumerated().map {
                index,
                piece -> String in

                if index == pieces.count - 1 {
                    return "'\(piece)'"
                }

                return "'\(piece)', \"'\", "
            }
            .joined()

        return "concat(\(joined))"
    }
}
