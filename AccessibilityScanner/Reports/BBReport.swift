//
//  BBReport.swift
//  AccessibilityScanner
//
//  The scan as the BB sheet sees it: results grouped by BB issue, each with
//  the sheet's category (Element column), status (Type) and severity, and
//  every affected element numbered. Laid out like the A11yInspect panel:
//  an overview by category and a list of issues with their items.

import Foundation

nonisolated struct BBReport {

    struct Item: Identifiable {
        let id: UUID
        /// Running number across the whole report ("ID 12").
        let number: Int
        let screenName: String
        let category: String
        /// What was found: the element, and the measurement when there is one.
        let attribute: String
        let detail: String
        let evaluation: AccessibilityRuleEvaluation
    }

    struct Group: Identifiable {
        /// BB code, or "confirm:BBxxxxx" for Validate results that become
        /// that Fail code if the tester confirms them.
        let id: String
        let code: String
        let title: String
        let status: RuleResultStatus
        let severity: String
        let category: String
        let wcag: String?
        /// Validate results logged under this Fail code once confirmed.
        let ifConfirmed: Bool
        let items: [Item]
    }

    struct Category: Identifiable {
        let name: String
        let fails: Int
        let validates: Int
        let passes: Int

        var id: String { name }
        var total: Int { fails + validates + passes }
    }

    let groups: [Group]
    let categories: [Category]

    var itemCount: Int { groups.reduce(0) { $0 + $1.items.count } }

    init(report: AccessibilityScanResult) {
        struct Pending {
            var code: String
            var title: String
            var status: RuleResultStatus
            var wcag: String?
            var ifConfirmed: Bool
            var entries: [(screen: String, evaluation: AccessibilityRuleEvaluation)] = []
        }

        var pending: [String: Pending] = [:]
        // The same element seen in several scroll positions counts once.
        var seen = Set<String>()
        for screen in report.screens {
            for evaluation in screen.evaluations {
                let identity = [screen.name, evaluation.ruleID, evaluation.status.rawValue, evaluation.elementType,
                                evaluation.elementLabel, evaluation.identifier,
                                "\(Int(evaluation.frameWidth.rounded()))x\(Int(evaluation.frameHeight.rounded()))"]
                    .joined(separator: "|")
                guard seen.insert(identity).inserted else { continue }
                let status: RuleResultStatus
                switch evaluation.status {
                case .fail: status = .fail
                case .validate, .warning: status = .validate
                case .pass: status = .pass
                case .notTested: continue
                }
                let key: String
                if let issue = BBIssueCatalog.issue(for: evaluation) {
                    key = issue.id + "|" + status.rawValue
                    if pending[key] == nil {
                        pending[key] = Pending(code: issue.id, title: issue.title, status: status,
                                               wcag: issue.wcag, ifConfirmed: false)
                    }
                } else if let confirm = BBIssueCatalog.ifConfirmed(for: evaluation) {
                    key = "confirm:" + confirm.id
                    if pending[key] == nil {
                        pending[key] = Pending(code: confirm.id, title: confirm.title, status: .validate,
                                               wcag: confirm.wcag, ifConfirmed: true)
                    }
                } else if status != .pass {
                    // A finding with no code in the BB sheet is still shown,
                    // under the scanner's rule name.
                    key = "rule:" + evaluation.ruleID + "|" + status.rawValue
                    if pending[key] == nil {
                        pending[key] = Pending(code: "", title: evaluation.ruleName, status: status,
                                               wcag: AccessibilityRuleCatalog.metadata(for: evaluation.ruleID).wcagCriterion,
                                               ifConfirmed: false)
                    }
                } else {
                    continue
                }
                pending[key]?.entries.append((screen.name, evaluation))
            }
        }

        let statusOrder: [RuleResultStatus: Int] = [.fail: 0, .validate: 1, .pass: 2]
        let ordered = pending.map { key, value in (key, value) }.sorted { lhs, rhs in
            let l = lhs.1, r = rhs.1
            if statusOrder[l.status] != statusOrder[r.status] {
                return (statusOrder[l.status] ?? 9) < (statusOrder[r.status] ?? 9)
            }
            let lc = Self.category(for: l.code, status: l.status), rc = Self.category(for: r.code, status: r.status)
            if lc != rc { return lc < rc }
            return l.code < r.code
        }

        var number = 0
        var groups: [Group] = []
        for (key, value) in ordered {
            let category = Self.category(for: value.code, status: value.status)
            let items: [Item] = value.entries.map { entry in
                number += 1
                return Item(
                    id: entry.evaluation.id,
                    number: number,
                    screenName: entry.screen,
                    category: category,
                    attribute: Self.attribute(for: entry.evaluation),
                    detail: entry.evaluation.message,
                    evaluation: entry.evaluation
                )
            }
            groups.append(Group(
                id: key,
                code: value.code,
                title: value.title,
                status: value.status,
                severity: value.status == .pass ? "N/A" : value.code.isEmpty ? "—" : Self.severity(for: value.code, status: value.status),
                category: category,
                wcag: value.wcag,
                ifConfirmed: value.ifConfirmed,
                items: items
            ))
        }
        self.groups = groups

        var counts: [String: (Int, Int, Int)] = [:]
        for group in groups {
            var c = counts[group.category] ?? (0, 0, 0)
            switch group.status {
            case .fail: c.0 += group.items.count
            case .validate: c.1 += group.items.count
            default: c.2 += group.items.count
            }
            counts[group.category] = c
        }
        self.categories = counts
            .map { Category(name: $0.key, fails: $0.value.0, validates: $0.value.1, passes: $0.value.2) }
            .sorted { $0.name < $1.name }
    }

    // MARK: Sheet lookups

    /// The sheet row for a code; BB40034 is both a Pass and a Fail row.
    private static func rule(for code: String, status: RuleResultStatus) -> BBRule? {
        let rows = BBRuleset.rules.filter { $0.id == code }
        let type: BBRuleType = status == .pass ? .pass : status == .validate ? .validate : .fail
        return rows.first { $0.type == type } ?? rows.first
    }

    /// The sheet's Element column, tidied ("Text resize" → "Text Resize").
    static func category(for code: String, status: RuleResultStatus) -> String {
        if code.isEmpty { return "Not in BB sheet" }
        let element = rule(for: code, status: status)?.element.trimmingCharacters(in: .whitespaces) ?? ""
        if element.isEmpty { return code == "BB40136" || code == "BB40137" ? "Pointer" : "Other" }
        return element.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private static func severity(for code: String, status: RuleResultStatus) -> String {
        let severity = rule(for: code, status: status)?.severity ?? ""
        return severity.isEmpty ? "—" : severity
    }

    /// The element as testers identify it: its label (or type for unnamed
    /// ones), plus the measured contrast for colour results.
    private static func attribute(for evaluation: AccessibilityRuleEvaluation) -> String {
        if ScreenshotAnnotation.isScreenLevel(evaluation) {
            return "Whole screen"
        }
        let label = evaluation.elementLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = evaluation.elementType
            .replacingOccurrences(of: "XCUIElementType", with: "")
            .split(separator: ".").last.map(String.init) ?? evaluation.elementType
        var text = label.isEmpty ? "Unnamed \(type)" : "\(label) (\(type))"
        if let ratio = evaluation.message.range(of: #"\d+\.\d+:1( \(FG #[0-9A-F]{6}, BG #[0-9A-F]{6}\))?"#, options: .regularExpression) {
            text += " — " + evaluation.message[ratio]
        }
        return text
    }
}
