import SwiftUI

struct AccessibilityDiffView: View {
    let diff: AccessibilityDiffResult

    @State private var expandedSections: Set<String> = []
    private let previewLimit = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if !diff.hasBaseline {
                Text("No previous scan is available for a detailed comparison. Run another scan to create the first baseline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                summary
                if !diff.newIssues.isEmpty {
                    issueSection(title: "New Findings", issues: diff.newIssues)
                }
                if !diff.fixedIssues.isEmpty {
                    issueSection(title: "Fixed Findings", issues: diff.fixedIssues)
                }
                screenSection

                if diff.newIssues.isEmpty && diff.fixedIssues.isEmpty && diff.addedScreens.isEmpty && diff.removedScreens.isEmpty {
                    Label("No accessibility changes detected since the previous baseline.", systemImage: "checkmark.circle")
                        .font(.subheadline)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Accessibility Diff")
                    .font(.headline)
                Text("Exact finding and screen changes compared with the previous scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if diff.hasBaseline {
                Text("BASELINE")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 24) {
            metric("New", diff.newIssues.count)
            metric("Fixed", diff.fixedIssues.count)
            metric("Added screens", diff.addedScreens.count)
            metric("Removed screens", diff.removedScreens.count)
        }
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func issueSection(title: String, issues: [AccessibilityDiffIssue]) -> some View {
        let showAll = expandedSections.contains(title)
        let visible = showAll ? issues : Array(issues.prefix(previewLimit))

        return VStack(alignment: .leading, spacing: 8) {
            Text("\(title) (\(issues.count))")
                .font(.subheadline)
                .fontWeight(.semibold)

            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(visible) { change in
                    diffRow(change)
                }
            }

            if issues.count > previewLimit {
                Button(showAll ? "Show fewer" : "Show all \(issues.count)") {
                    if showAll {
                        expandedSections.remove(title)
                    } else {
                        expandedSections.insert(title)
                    }
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    private func diffRow(_ change: AccessibilityDiffIssue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(change.issue.severity == .error ? Color.red : Color.orange)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 3) {
                    Text(change.issue.ruleName)
                        .fontWeight(.semibold)
                    Text(change.issue.message)
                        .font(.subheadline)
                    Text("\(change.issue.screenName) • \(change.issue.elementType)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Text(change.issue.status.displayName)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(Capsule())
            }

            if !change.issue.elementLabel.isEmpty || !change.issue.identifier.isEmpty {
                HStack(spacing: 12) {
                    if !change.issue.elementLabel.isEmpty {
                        Label(change.issue.elementLabel, systemImage: "textformat")
                    }
                    if !change.issue.identifier.isEmpty {
                        Label(change.issue.identifier, systemImage: "number")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if !change.issue.remediation.isEmpty {
                Text("Fix: \(change.issue.remediation)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
    }

    @ViewBuilder
    private var screenSection: some View {
        if !diff.addedScreens.isEmpty || !diff.removedScreens.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Screen Changes")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                ForEach(diff.addedScreens) { screen in
                    screenRow(screen, status: "Added")
                }
                ForEach(diff.removedScreens) { screen in
                    screenRow(screen, status: "Removed")
                }
            }
        }
    }

    private func screenRow(_ screen: AccessibilityDiffScreenChange, status: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: status == "Added" ? "plus.circle" : "minus.circle")
            VStack(alignment: .leading, spacing: 2) {
                Text(screen.screenName)
                    .fontWeight(.medium)
                Text(screen.signature)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
