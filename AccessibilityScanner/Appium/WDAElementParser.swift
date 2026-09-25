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
            accessible: Bool
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
        }

        func toAccessibilityNode() -> AccessibilityNode {

            AccessibilityNode(
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
                children: children.map {
                    $0.toAccessibilityNode()
                }
            )
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

        return root.toAccessibilityNode()
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
            accessible: accessible
        )

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
