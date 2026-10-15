//
//  WDAElementParser.swift
//  AccessibilityScannerDemo
//
//  Created by Ravish Kumar on 22/09/26.
//

import Foundation
import CoreGraphics

final class WDAElementParser: NSObject, XMLParserDelegate {

    // MARK: - Mutable Node

    private final class MutableNode {

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

        var customActions: [String] = []

        var children: [MutableNode] = []

        init(
            type: String,
            identifier: String,
            label: String,
            value: String?,
            placeholderValue: String?,
            traits: String,
            frame: CGRect,
            exists: Bool,
            hittable: Bool,
            enabled: Bool,
            visible: Bool,
            accessible: Bool,
            focused: Bool
        ) {
            self.type = type
            self.identifier = identifier
            self.label = label
            self.value = value

            self.placeholderValue = placeholderValue
            self.traits = traits

            self.frame = frame

            self.exists = exists
            self.hittable = hittable
            self.enabled = enabled
            self.visible = visible
            self.accessible = accessible
            self.focused = focused
        }

        func toAccessibilityNode() -> AccessibilityNode {

            var result = AccessibilityNode(
                type: type,
                identifier: identifier,
                label: label,
                value: value,
                placeholderValue: placeholderValue,
                traits: traits,
                frame: frame,
                exists: exists,
                hittable: hittable,
                enabled: enabled,
                visible: visible,
                accessible: accessible,
                focused: focused,
                // UIKit's scroll indicators are system chrome, not app
                // content; rules would otherwise flag them on every scroll view.
                children: children
                    .filter { !$0.isScrollIndicator }
                    .map { $0.toAccessibilityNode() }
            )

            // Cross-platform frameworks can expose a generic XCUI element
            // while preserving the semantic role in accessibility traits.
            if result.role == .other, let role = roleFromTraits(traits) {
                result.roleOverride = role
            }

            result.semantics.customActions = customActions

            return result
        }

        var isScrollIndicator: Bool {
            type == "XCUIElementTypeOther" &&
                (label.hasPrefix("Vertical scroll bar") || label.hasPrefix("Horizontal scroll bar"))
        }

        private func roleFromTraits(_ traits: String) -> AccessibilityRole? {
            let value = traits.lowercased()
            if value.contains("button") { return .button }
            if value.contains("link") { return .link }
            if value.contains("adjustable") { return .slider }
            return nil
        }
    }

    // MARK: - Parser State

    private var stack: [MutableNode] = []

    private var parsedRoot: MutableNode?

    // MARK: - Parse

    func parse(
        _ xml: String
    ) throws -> AccessibilityNode {

        stack.removeAll()
        parsedRoot = nil

        guard let data = xml.data(
            using: .utf8
        ) else {
            throw WDAParserError.invalidXML
        }

        let parser = XMLParser(
            data: data
        )

        parser.delegate = self

        guard parser.parse() else {

            throw parser.parserError
                ?? WDAParserError.invalidXML
        }

        guard let root = parsedRoot else {
            throw WDAParserError.noRootElement
        }

        return root.toAccessibilityNode().annotatingLayout()
    }

    // MARK: - XML Start Element

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {

        // AppiumAUT is only a container.
        // We don't want it represented as an AccessibilityNode.
        if elementName == "AppiumAUT" {
            return
        }

        let type =
            attributeDict["type"]
            ?? elementName

        let identifier =
            attributeDict["name"]
            ?? ""

        let label =
            attributeDict["label"]
            ?? ""

        let value =
            attributeDict["value"]

        let placeholderValue =
            attributeDict["placeholderValue"]

        let traits =
            attributeDict["traits"]
            ?? ""

        let x =
            Double(
                attributeDict["x"] ?? "0"
            )
            ?? 0

        let y =
            Double(
                attributeDict["y"] ?? "0"
            )
            ?? 0

        let width =
            Double(
                attributeDict["width"] ?? "0"
            )
            ?? 0

        let height =
            Double(
                attributeDict["height"] ?? "0"
            )
            ?? 0

        let frame = CGRect(
            x: x,
            y: y,
            width: width,
            height: height
        )

        let enabled =
            parseBool(
                attributeDict["enabled"]
            )

        let visible =
            parseBool(
                attributeDict["visible"]
            )

        let accessible =
            parseBool(
                attributeDict["accessible"]
            )

        let focused =
            parseBool(
                attributeDict["focused"]
            )

        let hittable =
            parseBool(
                attributeDict["hittable"]
            )

        let node = MutableNode(
            type: type,
            identifier: identifier,
            label: label,
            value: value,
            placeholderValue: placeholderValue,
            traits: traits,
            frame: frame,
            exists: true,
            hittable: hittable,
            enabled: enabled,
            visible: visible,
            accessible: accessible,
            focused: focused
        )

        // Present when includeCustomActionsInPageSource is on.
        if let actions = attributeDict["customActions"], !actions.isEmpty {
            node.customActions = actions
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        if let parent = stack.last {

            parent.children.append(
                node
            )

        } else {

            parsedRoot = node
        }

        stack.append(
            node
        )
    }

    // MARK: - XML End Element

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {

        if elementName == "AppiumAUT" {
            return
        }

        if !stack.isEmpty {
            stack.removeLast()
        }
    }

    // MARK: - Boolean Parsing

    private func parseBool(
        _ value: String?
    ) -> Bool {

        guard let value else {
            return false
        }

        return value
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased() == "true"
    }
}

// MARK: - Parser Errors

enum WDAParserError: Error, LocalizedError {

    case invalidXML
    case noRootElement

    var errorDescription: String? {

        switch self {

        case .invalidXML:
            return "The WebDriverAgent XML could not be parsed."

        case .noRootElement:
            return "No root accessibility element was found."
        }
    }
}
