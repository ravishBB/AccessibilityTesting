//
//  ScreenNaming.swift
//  AccessibilityScanner
//
//  Names screens the way the app does ("Home", "Settings", an article's
//  title) instead of "Screen 1", for the report, the map and the exports.

import Foundation
import CoreGraphics

nonisolated enum ScreenNaming {

    /// The screen's own title: Android pane title, the navigation bar's
    /// title, the first heading near the top, then the selected tab.
    /// "Screen N" only when the screen shows none of these.
    static func name(for root: AccessibilityNode, number: Int) -> String {
        let nodes = all(root)
        let top = root.frame.minY + root.frame.height * 0.3

        if let pane = nodes.lazy.compactMap({ $0.semantics.paneTitle.map(clean) }).first(where: usable) {
            return pane
        }

        for bar in nodes where bar.role == .navigationBar && bar.visible {
            let candidates = [clean(bar.label)]
                + all(bar).dropFirst().filter { $0.role == .staticText && $0.visible }.map { clean($0.label) }
                + [clean(bar.identifier)]
            if let title = candidates.first(where: usable) { return title }
        }

        let headings = nodes.filter {
            $0.visible && $0.frame.minY < top && $0.role == .staticText &&
                ($0.traits.lowercased().contains("header") || $0.traits.lowercased().contains("heading") ||
                 $0.semantics.isHeading == true)
        }
        if let heading = headings.map({ clean($0.label) }).first(where: usable) {
            return heading
        }

        let tabs = nodes.filter { node in
            node.visible && node.role == .button &&
                (node.traits.lowercased().contains("selected") || node.value == "1") &&
                all(root).contains { $0.role == .tabBar && $0.frame.contains(CGPoint(x: node.frame.midX, y: node.frame.midY)) }
        }
        if let tab = tabs.map({ clean($0.label) }).first(where: usable) {
            return tab
        }

        return "Screen \(number)"
    }

    /// Screens that share a name get a number: "Article", "Article 2".
    static func uniquified(_ screens: [ScreenScanResult]) -> [ScreenScanResult] {
        var seen: [String: Int] = [:]
        return screens.map { screen in
            var screen = screen
            let count = (seen[screen.name] ?? 0) + 1
            seen[screen.name] = count
            if count > 1 { screen.name = "\(screen.name) \(count)" }
            return screen
        }
    }

    // MARK: Helpers

    private static func all(_ node: AccessibilityNode) -> [AccessibilityNode] {
        [node] + node.children.flatMap(all)
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A title, not an empty label, a long sentence or a generic word.
    private static func usable(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 40 else { return false }
        let generic: Set<String> = ["back", "close", "done", "cancel", "more", "menu", "navigation", "tab bar"]
        return !generic.contains(text.lowercased())
    }
}
