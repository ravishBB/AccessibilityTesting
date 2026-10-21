//
//  BBReportView.swift
//  AccessibilityScanner
//
//  The scan grouped the way the BB sheet and A11yInspect present it: an
//  overview by category and a list of BB issues with numbered items.

import SwiftUI

/// The report's one status filter, used by the BB Report and the Issue
/// Explorer alike.
enum ReportFilter: String, CaseIterable, Identifiable, Hashable {
    case all, fail, validate, pass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .fail: return "Fail"
        case .validate: return "Validate"
        case .pass: return "Pass"
        }
    }

    /// "results", "fail", "validate", "pass": for "3 fail", "No pass checks".
    var noun: String { self == .all ? "results" : title.lowercased() }

    var color: Color {
        switch self {
        case .all: return .accentColor
        case .fail: return .red
        case .validate: return .orange
        case .pass: return .green
        }
    }

    var symbol: String {
        switch self {
        case .all: return "list.bullet"
        case .fail: return "xmark.octagon.fill"
        case .validate: return "exclamationmark.circle.fill"
        case .pass: return "checkmark.circle.fill"
        }
    }

    func includes(_ status: RuleResultStatus) -> Bool {
        switch self {
        case .all: return status != .notTested
        case .fail: return status == .fail || status == .warning
        case .validate: return status == .validate
        case .pass: return status == .pass
        }
    }

    init(_ status: RuleResultStatus) {
        switch status {
        case .pass: self = .pass
        case .validate, .notTested: self = .validate
        case .fail, .warning: self = .fail
        }
    }
}

struct BBReportView: View {

    let report: BBReport
    /// Shows the element on the screenshot in the Issue Explorer.
    /// Shared with the Issue Explorer: one filter for the whole report.
    @Binding var statusFilter: ReportFilter
    var onSelect: (AccessibilityRuleEvaluation) -> Void = { _ in }

    private enum Tab: Hashable { case overview, issues }

    @State private var tab: Tab = .overview
    @State private var category: String?
    @State private var expanded = Set<String>()

    private var visibleGroups: [BBReport.Group] {
        report.groups.filter { group in
            (category == nil || group.category == category) &&
                statusFilter.includes(group.status)
        }
    }

    /// Items the current status and category filters show, as A11yInspect
    /// counts them.
    private var visibleItemCount: Int {
        visibleGroups.reduce(0) { $0 + $1.items.count }
    }

    /// Categories with items under the current status filter, counted for
    /// that status only.
    private var visibleCategories: [BBReport.Category] {
        report.categories.compactMap { category in
            let fails = statusFilter == .all || statusFilter == .fail ? category.fails : 0
            let validates = statusFilter == .all || statusFilter == .validate ? category.validates : 0
            let passes = statusFilter == .all || statusFilter == .pass ? category.passes : 0
            guard fails + validates + passes > 0 else { return nil }
            return BBReport.Category(name: category.name, fails: fails, validates: validates, passes: passes)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BB Report")
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 16) {
                // Plain SwiftUI segments: AppKit's segmented control inside
                // the report's lazy list crashed while rows were prefetched
                // (NSSegmentedCell "index beyond bounds").
                SegmentButtons(
                    options: [(Tab.overview, "Overview (\(visibleCategories.count))"),
                              (Tab.issues, "Issues (\(visibleItemCount))")],
                    selection: $tab,
                    label: "View"
                )

                SegmentButtons(
                    options: ReportFilter.allCases.map { ($0, $0.title) },
                    selection: $statusFilter,
                    label: "Status"
                )

                if let category {
                    Button {
                        self.category = nil
                    } label: {
                        Label(category, systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .help("Show all categories")
                }
                Spacer()
            }

            switch tab {
            case .overview: overview
            case .issues: issues
            }
        }
    }

    // MARK: Overview

    private var overview: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
            ForEach(visibleCategories) { item in
                Button {
                    category = item.name
                    tab = .issues
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.name)
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("\(item.total) result\(item.total == 1 ? "" : "s")")
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                if item.fails > 0 { countChip("\(item.fails) fail", .red) }
                                if item.validates > 0 { countChip("\(item.validates) validate", .orange) }
                                if item.passes > 0 { countChip("\(item.passes) pass", .green) }
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Issues

    private var issues: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            if visibleGroups.isEmpty {
                Text("No results for this filter.")
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
            ForEach(visibleGroups) { group in
                groupCard(group)
            }
        }
    }

    private func groupCard(_ group: BBReport.Group) -> some View {
        // Passes can number in the hundreds: show a few until expanded.
        let isExpanded = expanded.contains(group.id) || group.status != .pass
        let shown = isExpanded ? group.items : Array(group.items.prefix(3))

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                statusBadge(group.status)
                Spacer()
                Text("Severity:")
                    .foregroundStyle(.secondary)
                Text(group.severity)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(severityColor(group.severity)))
            }

            VStack(alignment: .leading, spacing: 4) {
                if group.ifConfirmed {
                    Text("Record as a failure if confirmed")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                }
                (Text(group.title).font(.title3).fontWeight(.semibold)
                    + Text("  (\(group.items.count) issue\(group.items.count == 1 ? "" : "s"))").foregroundColor(.secondary))
                HStack(spacing: 8) {
                    Text(group.category)
                    if let wcag = group.wcag { Text("· WCAG \(wcag)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ForEach(shown) { item in
                itemRow(item)
            }

            if group.items.count > shown.count || (expanded.contains(group.id) && group.status == .pass) {
                Button(expanded.contains(group.id) ? "Show fewer" : "Show all \(group.items.count)") {
                    if expanded.contains(group.id) { expanded.remove(group.id) } else { expanded.insert(group.id) }
                }
                .buttonStyle(.link)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.15)))
    }

    private func itemRow(_ item: BBReport.Item) -> some View {
        Button {
            onSelect(item.evaluation)
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ID \(String(format: "%02d", item.number))")
                        .font(.headline)
                    (Text("Element: ").fontWeight(.semibold) + Text(item.category))
                    (Text("Attribute: ").fontWeight(.semibold) + Text(item.attribute))
                    Text("\(item.screenName) · \(item.detail)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show this element on the screenshot")
    }

    // MARK: Styling

    private func statusBadge(_ status: RuleResultStatus) -> some View {
        let (text, symbol, color): (String, String, Color) = {
            switch status {
            case .fail: return ("Fail", "xmark.octagon", .red)
            case .pass: return ("Pass", "checkmark.circle", .green)
            default: return ("Validate", "exclamationmark.circle", .orange)
            }
        }()
        return Label(text, systemImage: symbol)
            .font(.callout.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private func countChip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
            .lineLimit(1)
            .fixedSize()
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "blocker", "critical": return .orange
        case "major": return .blue
        case "minor": return .secondary
        default: return .secondary.opacity(0.5)
        }
    }
}

/// A segmented switch drawn with plain SwiftUI buttons. AppKit's segmented
/// control (Picker .segmented) crashes inside lazy stacks when rows are
/// prefetched ("NSSegmentedCell … index beyond bounds"), and the report is
/// one long lazy stack.
struct SegmentButtons<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    let label: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = selection == option.0
                Button {
                    selection = option.0
                } label: {
                    Text(option.1)
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.secondary.opacity(0.12)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
