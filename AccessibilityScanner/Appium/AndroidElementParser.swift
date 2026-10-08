//
//  AndroidElementParser.swift
//  AccessibilityScanner
//
//  Parses the UiAutomator2 page source (`GET /session/:id/source`) into an
//  AccessibilityNode tree.
//
//  Conventions used so the existing rules keep working:
//   - Frames are converted from pixels to dp (pixels / displayScale) so they
//     are comparable with iOS points.
//   - `label`      = accessible name as TalkBack announces it
//                    (content-desc, falling back to text for non-input views).
//   - `identifier` = resource-id.
//   - `value`      = typed text for inputs, "1"/"0" for checkable controls.
//   - `placeholderValue` = hint.
//   - `traits`     = space separated Android state tokens (clickable, selected…).
//

import Foundation
import CoreGraphics

final class AndroidElementParser: NSObject, XMLParserDelegate {

    // MARK: - Configuration

    /// Pixels per dp (density dpi / 160).
    private let displayScale: CGFloat

    /// Packages that belong to the system, not the app under test.
    private let ignoredPackageFragments = [
        "com.android.systemui",
        "inputmethod"
    ]

    init(displayScale: CGFloat = 1) {
        self.displayScale = displayScale > 0 ? displayScale : 1
    }

    // MARK: - Mutable node

    private final class MutableNode {

        let className: String
        let resourceID: String
        let text: String
        let contentDesc: String
        let hint: String
        let frame: CGRect

        let clickable: Bool
        let longClickable: Bool
        let checkable: Bool
        let checked: Bool
        let enabled: Bool
        let focusable: Bool
        let focused: Bool
        let scrollable: Bool
        let selected: Bool
        let password: Bool
        let displayed: Bool
        let roleDescription: String

        var children: [MutableNode] = []

        init(
            className: String,
            resourceID: String,
            text: String,
            contentDesc: String,
            hint: String,
            frame: CGRect,
            clickable: Bool,
            longClickable: Bool,
            checkable: Bool,
            checked: Bool,
            enabled: Bool,
            focusable: Bool,
            focused: Bool,
            scrollable: Bool,
            selected: Bool,
            password: Bool,
            displayed: Bool,
            roleDescription: String
        ) {
            self.className = className
            self.resourceID = resourceID
            self.text = text
            self.contentDesc = contentDesc
            self.hint = hint
            self.frame = frame
            self.clickable = clickable
            self.longClickable = longClickable
            self.checkable = checkable
            self.checked = checked
            self.enabled = enabled
            self.focusable = focusable
            self.focused = focused
            self.scrollable = scrollable
            self.selected = selected
            self.password = password
            self.displayed = displayed
            self.roleDescription = roleDescription
        }
    }

    // MARK: - Parser state

    private var stack: [MutableNode] = []
    private var parsedRoot: MutableNode?
    private var skipDepth = 0

    // MARK: - Parse

    func parse(_ xml: String) throws -> AccessibilityNode {

        stack.removeAll()
        parsedRoot = nil
        skipDepth = 0

        guard let data = xml.data(using: .utf8) else {
            throw AndroidParserError.invalidXML
        }

        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            throw parser.parserError ?? AndroidParserError.invalidXML
        }

        guard let root = parsedRoot else {
            throw AndroidParserError.noRootElement
        }

        return build(root, isRoot: true)
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {

        if skipDepth > 0 {
            skipDepth += 1
            return
        }

        let package = attributeDict["package"] ?? ""
        if ignoredPackageFragments.contains(where: { package.contains($0) }) {
            skipDepth = 1
            return
        }

        let isHierarchyRoot = elementName == "hierarchy"

        let node = MutableNode(
            className: isHierarchyRoot ? "hierarchy" : (attributeDict["class"] ?? elementName),
            resourceID: attributeDict["resource-id"] ?? "",
            text: attributeDict["text"] ?? "",
            contentDesc: attributeDict["content-desc"] ?? "",
            hint: attributeDict["hint"] ?? "",
            frame: parseBounds(attributeDict["bounds"]),
            clickable: bool(attributeDict["clickable"]),
            longClickable: bool(attributeDict["long-clickable"]),
            checkable: bool(attributeDict["checkable"]),
            checked: bool(attributeDict["checked"]),
            enabled: attributeDict["enabled"] == nil ? true : bool(attributeDict["enabled"]),
            focusable: bool(attributeDict["focusable"]),
            focused: bool(attributeDict["focused"]),
            scrollable: bool(attributeDict["scrollable"]),
            selected: bool(attributeDict["selected"]),
            password: bool(attributeDict["password"]),
            // Older UiAutomator2 servers do not emit `displayed`; treat as visible.
            displayed: attributeDict["displayed"] == nil ? true : bool(attributeDict["displayed"]),
            roleDescription: parseRoleDescription(attributeDict["extras"])
        )

        if let parent = stack.last {
            parent.children.append(node)
        } else if parsedRoot == nil {
            parsedRoot = node
        }

        stack.append(node)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {

        if skipDepth > 0 {
            skipDepth -= 1
            return
        }

        if !stack.isEmpty {
            stack.removeLast()
        }
    }

    // MARK: - Build AccessibilityNode

    private func build(_ node: MutableNode, isRoot: Bool) -> AccessibilityNode {

        let children = node.children.map { build($0, isRoot: false) }

        // The synthetic <hierarchy> root has no bounds: use the union of its windows.
        var frame = node.frame
        if isRoot, node.className == "hierarchy" {
            frame = children.map(\.frame).reduce(CGRect.null) { $0.union($1) }
            if frame.isNull { frame = .zero }
        }

        let resolved = AccessibilityRole.resolve(type: node.className)
        let role = refinedRole(for: node, resolved: resolved)

        let isTextInput = role == .textField
            || role == .secureTextField
            || role == .textView

        // TalkBack announces contentDescription first, then text. For inputs the
        // text is the user's content, not the name.
        let label: String = {
            if !node.contentDesc.isEmpty { return node.contentDesc }
            if isTextInput { return "" }
            if !node.text.isEmpty { return node.text }

            // Clickable containers (rows/cards) and toolbars are announced
            // using their descendants' text; use the first one as the name.
            if role == .cell || role == .navigationBar {
                return firstDescendantLabel(in: children) ?? ""
            }
            return ""
        }()

        let value: String? = {
            if isTextInput { return node.password ? nil : (node.text.isEmpty ? nil : node.text) }
            if node.checkable { return node.checked ? "1" : "0" }
            return nil
        }()

        var traits: [String] = []
        if node.clickable { traits.append("clickable") }
        if node.longClickable { traits.append("long-clickable") }
        if node.checkable { traits.append("checkable") }
        if node.checked { traits.append("checked") }
        if node.selected { traits.append("selected") }
        if node.focusable { traits.append("focusable") }
        if node.focused { traits.append("focused") }
        if node.scrollable { traits.append("scrollable") }
        if node.password { traits.append("password") }

        let visible = node.displayed && frame.width > 0 && frame.height > 0

        let hasName = !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Containers are traversed by screen readers; they do not hide content.
        let accessible = visible && (
            !children.isEmpty
            || hasName
            || node.clickable
            || node.focusable
            || node.checkable
            || node.scrollable
            || isTextInput
        )

        var result = AccessibilityNode(
            type: node.className,
            identifier: node.resourceID,
            label: label,
            value: value,
            placeholderValue: node.hint.isEmpty ? nil : node.hint,
            traits: traits.joined(separator: " "),
            frame: frame,
            exists: true,
            hittable: node.clickable && node.enabled && visible,
            enabled: node.enabled,
            visible: visible,
            accessible: accessible,
            focused: node.focused,
            children: children
        )

        result.platform = .android
        if role != resolved {
            result.roleOverride = role
        }

        return result
    }

    /// Generic Android views (View, ViewGroup, LinearLayout, Compose nodes…)
    /// do not name their role in the class. Infer a role from behaviour.
    private func refinedRole(
        for node: MutableNode,
        resolved: AccessibilityRole
    ) -> AccessibilityRole {

        if resolved == .textField, node.password {
            return .secureTextField
        }

        guard resolved == .other else {
            return resolved
        }

        let isLeaf = node.children.isEmpty

        // React Native and other cross-platform frameworks can expose an
        // accessibility role through AccessibilityNodeInfo.roleDescription
        // while retaining a generic Android class. Prefer that semantic role.
        if let role = roleFromDescription(node.roleDescription) {
            return role
        }

        if node.checkable {
            return .checkBox
        }

        if node.clickable {
            // A clickable leaf with a name behaves like a button.
            // A clickable container (row/card) is a cell: its name comes from
            // its children, so it is not subject to the button-name rules.
            return isLeaf ? .button : .cell
        }

        if isLeaf, !node.text.isEmpty {
            return .staticText
        }

        return .other
    }


    private func roleFromDescription(_ description: String) -> AccessibilityRole? {
        switch description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "button", "imagebutton": return .button
        case "link": return .link
        case "checkbox": return .checkBox
        case "radio", "radiobutton": return .radioButton
        case "switch", "toggle": return .toggle
        case "slider", "adjustable": return .slider
        case "textfield", "text field", "search": return .textField
        case "image": return .image
        case "tab": return .tabBar
        case "list", "grid": return .table
        default: return nil
        }
    }

    private func parseRoleDescription(_ extras: String?) -> String {
        guard let extras else { return "" }
        for part in extras.split(separator: ";") {
            let value = String(part)
            let lower = value.lowercased()
            if lower.contains("roledescription=") || lower.contains("role_description=") {
                if let separator = value.firstIndex(of: "=") {
                    return String(value[value.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return ""
    }

    // MARK: - Helpers

    private func firstDescendantLabel(in nodes: [AccessibilityNode]) -> String? {

        for node in nodes {

            let label = node.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if node.visible, !label.isEmpty {
                return label
            }

            if let nested = firstDescendantLabel(in: node.children) {
                return nested
            }
        }

        return nil
    }

    /// "[left,top][right,bottom]" in pixels → CGRect in dp.
    private func parseBounds(_ value: String?) -> CGRect {

        guard let value else { return .zero }

        var numbers: [Double] = []
        var current = ""

        for character in value {
            if character.isNumber || character == "-" {
                current.append(character)
            } else if !current.isEmpty {
                if let number = Double(current) { numbers.append(number) }
                current = ""
            }
        }
        if !current.isEmpty, let number = Double(current) {
            numbers.append(number)
        }

        guard numbers.count == 4 else { return .zero }

        let scale = Double(displayScale)
        let left = numbers[0] / scale
        let top = numbers[1] / scale
        let right = numbers[2] / scale
        let bottom = numbers[3] / scale

        return CGRect(
            x: left,
            y: top,
            width: max(0, right - left),
            height: max(0, bottom - top)
        )
    }

    private func bool(_ value: String?) -> Bool {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "true"
    }
}

// MARK: - Errors

enum AndroidParserError: Error, LocalizedError {

    case invalidXML
    case noRootElement

    var errorDescription: String? {
        switch self {
        case .invalidXML:
            return "The UiAutomator2 page source could not be parsed."
        case .noRootElement:
            return "No root accessibility element was found in the Android hierarchy."
        }
    }
}
