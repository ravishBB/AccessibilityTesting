import SwiftUI
import Foundation

// MARK: - Developer Fix Center

struct AccessibilityFixOpportunity: Identifiable, Codable, Hashable {
    let id: String
    let ruleID: String
    let ruleName: String
    let severity: AccessibilityFinding.Severity
    let occurrences: Int
    let affectedScreens: Int
    let screenNames: [String]
    let affectedElements: [String]
    let remediation: String
    let confidence: String
    let swiftUIExample: String?
    let uikitExample: String?

    // Impact-analysis fields shared with AccessibilityImpactCenter.
    let status: RuleResultStatus
    let affectedJourneys: Int
    let blockedJourneys: Int
    let impactScore: Int

    /// Platform the guidance applies to (drives code sample labels).
    let platform: MobilePlatform

    var primaryExampleTitle: String {
        platform == .android ? "Jetpack Compose" : "SwiftUI"
    }

    var secondaryExampleTitle: String {
        platform == .android ? "Android Views (Kotlin)" : "UIKit"
    }

    init(
        id: String,
        ruleID: String,
        ruleName: String,
        severity: AccessibilityFinding.Severity,
        occurrences: Int,
        affectedScreens: Int,
        screenNames: [String],
        affectedElements: [String],
        remediation: String,
        confidence: String,
        swiftUIExample: String?,
        uikitExample: String?,
        status: RuleResultStatus = .pass,
        affectedJourneys: Int = 0,
        blockedJourneys: Int = 0,
        impactScore: Int = 0,
        platform: MobilePlatform = .ios
    ) {
        self.id = id
        self.ruleID = ruleID
        self.ruleName = ruleName
        self.severity = severity
        self.occurrences = occurrences
        self.affectedScreens = affectedScreens
        self.screenNames = screenNames
        self.affectedElements = affectedElements
        self.remediation = remediation
        self.confidence = confidence
        self.swiftUIExample = swiftUIExample
        self.uikitExample = uikitExample
        self.status = status
        self.affectedJourneys = affectedJourneys
        self.blockedJourneys = blockedJourneys
        self.impactScore = impactScore
        self.platform = platform
    }

    var statusTitle: String {
        status.displayName
    }

    var priorityScore: Int {
        let severityWeight: Int
        switch severity {
        case .error: severityWeight = 5
        case .warning: severityWeight = 3
        case .info: severityWeight = 1
        }
        return severityWeight * max(1, affectedScreens) + min(occurrences, 10)
    }
}

struct AccessibilityFixCenter: Codable, Hashable {
    let opportunities: [AccessibilityFixOpportunity]
    let totalOpenFindings: Int
    let rulesWithFixGuidance: Int

    static let empty = AccessibilityFixCenter(
        opportunities: [],
        totalOpenFindings: 0,
        rulesWithFixGuidance: 0
    )

    static func analyze(report: AccessibilityScanResult) -> AccessibilityFixCenter {
        let findings = report.allEvaluations.filter {
            $0.status == .fail || $0.status == .warning || $0.status == .validate
        }

        guard !findings.isEmpty else { return .empty }

        let grouped = Dictionary(grouping: findings, by: \.ruleID)
        let opportunities = grouped.compactMap { ruleID, evaluations -> AccessibilityFixOpportunity? in
            guard let first = evaluations.first else { return nil }

            let screens = Set(
                report.screens.filter { screen in
                    screen.evaluations.contains { evaluation in
                        evaluations.contains { $0.id == evaluation.id }
                    }
                }.map(\.name)
            ).sorted()

            let elements = Array(Set(evaluations.map { evaluation in
                let label = evaluation.elementLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                let identifier = evaluation.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty { return label }
                if !identifier.isEmpty { return identifier }
                return evaluation.elementType
            })).sorted().prefix(5)

            let guidance = AccessibilityFixGuidance.forRule(ruleID: ruleID, first: first)

            return AccessibilityFixOpportunity(
                id: ruleID,
                ruleID: ruleID,
                ruleName: first.ruleName,
                severity: evaluations.map(\.severity).max(by: { $0.rank < $1.rank }) ?? first.severity,
                occurrences: evaluations.count,
                affectedScreens: screens.count,
                screenNames: screens,
                affectedElements: Array(elements),
                remediation: guidance.remediation,
                confidence: guidance.confidence,
                swiftUIExample: guidance.swiftUIExample,
                uikitExample: guidance.uikitExample,
                platform: first.platform
            )
        }
        .sorted {
            if $0.priorityScore != $1.priorityScore { return $0.priorityScore > $1.priorityScore }
            return $0.ruleName.localizedCaseInsensitiveCompare($1.ruleName) == .orderedAscending
        }

        return AccessibilityFixCenter(
            opportunities: opportunities,
            totalOpenFindings: findings.count,
            rulesWithFixGuidance: opportunities.filter { $0.swiftUIExample != nil || $0.uikitExample != nil }.count
        )
    }
}

struct AccessibilityFixGuidance {
    let remediation: String
    let confidence: String
    let swiftUIExample: String?
    let uikitExample: String?

    static func forRule(ruleID: String, first: AccessibilityRuleEvaluation) -> AccessibilityFixGuidance {

        if first.platform == .android {
            return forAndroidRule(ruleID: ruleID, first: first)
        }

        switch ruleID {
        case "accessible-name", "accessible-name-missing", "BB40002":
            return AccessibilityFixGuidance(
                remediation: "Give the interactive control a clear accessible name that describes its purpose.",
                confidence: "High",
                swiftUIExample: "Button(action: submit) {\n    Image(\"arrow.right\")\n}\n.accessibilityLabel(\"Submit\")",
                uikitExample: "button.accessibilityLabel = \"Submit\""
            )
        case "touch-target-size-44", "touch-target-size":
            return AccessibilityFixGuidance(
                remediation: "Increase the interactive area to at least the scanner's configured target size without reducing the visible control.",
                confidence: "High",
                swiftUIExample: "Button(action: submit) {\n    Image(\"arrow.right\")\n}\n.frame(minWidth: 44, minHeight: 44)",
                uikitExample: "button.frame.size = CGSize(width: 44, height: 44)"
            )
        case "text-clipping", "text-resize":
            return AccessibilityFixGuidance(
                remediation: "Allow text to resize or wrap without clipping and verify the layout at larger text sizes.",
                confidence: "Medium",
                swiftUIExample: "Text(title)\n    .fixedSize(horizontal: false, vertical: true)\n    .dynamicTypeSize(...DynamicTypeSize.accessibility5)",
                uikitExample: "label.numberOfLines = 0\nlabel.adjustsFontForContentSizeCategory = true"
            )
        case "hidden-interactive-element", "hidden-interactive":
            return AccessibilityFixGuidance(
                remediation: "Ensure an interactive control is exposed to accessibility services when it is available to the user.",
                confidence: "High",
                swiftUIExample: "Button(action: submit) {\n    Text(\"Submit\")\n}\n.accessibilityHidden(false)",
                uikitExample: "button.isAccessibilityElement = true"
            )
        case "role-state", "role-state-validation":
            return AccessibilityFixGuidance(
                remediation: "Expose the control's correct role and current state so assistive technology can describe it accurately.",
                confidence: "Medium",
                swiftUIExample: "Toggle(\"Remember me\", isOn: $rememberMe)",
                uikitExample: "control.accessibilityTraits = [.button]\ncontrol.accessibilityValue = currentState"
            )
        case "focus-order":
            return AccessibilityFixGuidance(
                remediation: "Review the visual and accessibility reading order and ensure controls are encountered in a logical sequence.",
                confidence: "Manual review",
                swiftUIExample: "VStack {\n    title\n    field\n    submitButton\n}",
                uikitExample: "Review accessibilityElements order for the containing view."
            )
        default:
            return AccessibilityFixGuidance(
                remediation: first.remediation.isEmpty ? "Review the finding evidence and update the affected control according to the rule requirement." : first.remediation,
                confidence: first.status == .fail ? "Medium" : "Manual review",
                swiftUIExample: nil,
                uikitExample: nil
            )
        }
    }

    // MARK: - Android guidance

    /// `swiftUIExample` carries the Jetpack Compose sample and `uikitExample`
    /// the Android Views (Kotlin) sample for Android findings.
    private static func forAndroidRule(ruleID: String, first: AccessibilityRuleEvaluation) -> AccessibilityFixGuidance {
        switch ruleID {
        case "accessible-name", "button-name-descriptive", "image-button-name",
             "interactive-name-descriptive", "image-accessible-label", "image-name-descriptive":
            return AccessibilityFixGuidance(
                remediation: "Give the control a clear accessible name that describes its purpose (contentDescription).",
                confidence: "High",
                swiftUIExample: "IconButton(onClick = onSubmit) {\n    Icon(\n        imageVector = Icons.Default.Send,\n        contentDescription = \"Submit\"\n    )\n}",
                uikitExample: "imageButton.contentDescription = \"Submit\"\n// or in XML: android:contentDescription=\"@string/submit\""
            )
        case "touch-target-size-44", "touch-target-size-24", "touch-target-size":
            return AccessibilityFixGuidance(
                remediation: "Increase the touch target to at least 48dp x 48dp without changing the visible icon size.",
                confidence: "High",
                swiftUIExample: "IconButton(\n    onClick = onClick,\n    modifier = Modifier.minimumInteractiveComponentSize()\n) { Icon(icon, contentDescription = \"Close\") }",
                uikitExample: "// XML\nandroid:minWidth=\"48dp\"\nandroid:minHeight=\"48dp\"\n// or enlarge the hit area:\nview.touchDelegate = TouchDelegate(expandedRect, view)"
            )
        case "text-clipping", "text-resize":
            return AccessibilityFixGuidance(
                remediation: "Use sp for text sizes, let text wrap, and verify the layout with the largest system font size.",
                confidence: "Medium",
                swiftUIExample: "Text(\n    text = title,\n    fontSize = 16.sp,\n    maxLines = Int.MAX_VALUE,\n    overflow = TextOverflow.Visible\n)",
                uikitExample: "textView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)\ntextView.maxLines = Int.MAX_VALUE\ntextView.ellipsize = null"
            )
        case "interactive-screen-reader-hidden":
            return AccessibilityFixGuidance(
                remediation: "Make sure the control is exposed to TalkBack unless it is intentionally decorative.",
                confidence: "High",
                swiftUIExample: "Modifier.semantics { /* remove clearAndSetSemantics / invisibleToUser on interactive nodes */ }",
                uikitExample: "view.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES"
            )
        case "role-trait-consistency", "role-state", "state-trait-consistency":
            return AccessibilityFixGuidance(
                remediation: "Expose the correct role and state so TalkBack announces the control accurately.",
                confidence: "Medium",
                swiftUIExample: "Modifier\n    .clickable(role = Role.Button, onClick = onClick)\n    .semantics { stateDescription = if (checked) \"On\" else \"Off\" }",
                uikitExample: "ViewCompat.setAccessibilityDelegate(view, object : AccessibilityDelegateCompat() {\n    override fun onInitializeAccessibilityNodeInfo(host: View, info: AccessibilityNodeInfoCompat) {\n        super.onInitializeAccessibilityNodeInfo(host, info)\n        info.className = Button::class.java.name\n    }\n})"
            )
        case "focus-order", "reading-order":
            return AccessibilityFixGuidance(
                remediation: "Review the TalkBack traversal order and make it follow the visual reading order.",
                confidence: "Manual review",
                swiftUIExample: "Modifier.semantics { traversalIndex = 1f }",
                uikitExample: "view.accessibilityTraversalAfter = previousView.id"
            )
        default:
            return AccessibilityFixGuidance(
                remediation: first.remediation.isEmpty ? "Review the finding evidence and update the affected control according to the rule requirement." : first.remediation,
                confidence: first.status == .fail ? "Medium" : "Manual review",
                swiftUIExample: nil,
                uikitExample: nil
            )
        }
    }
}

private extension AccessibilityFinding.Severity {
    var rank: Int {
        switch self {
        case .error: return 3
        case .warning: return 2
        case .info: return 1
        }
    }
}

// MARK: - Developer Fix Center View

struct AccessibilityFixCenterView: View {
    let fixCenter: AccessibilityFixCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Developer Fix Center")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Developer-ready guidance grouped by accessibility rule.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(fixCenter.opportunities.count) rules")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 18) {
                metric("Open findings", fixCenter.totalOpenFindings)
                metric("Rules", fixCenter.opportunities.count)
                metric("With code", fixCenter.rulesWithFixGuidance)
            }

            if fixCenter.opportunities.isEmpty {
                Label("No open findings require developer guidance.", systemImage: "checkmark.circle")
                    .font(.subheadline)
            } else {
                ForEach(fixCenter.opportunities.prefix(10)) { opportunity in
                    opportunityCard(opportunity)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
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

    private func opportunityCard(_ opportunity: AccessibilityFixOpportunity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(opportunity.ruleName)
                        .font(.headline)
                    Text(opportunity.ruleID)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(opportunity.severity.displayName)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 14) {
                Label("\(opportunity.occurrences) occurrences", systemImage: "exclamationmark.circle")
                Label("\(opportunity.affectedScreens) screens", systemImage: "rectangle.stack")
                Label(opportunity.confidence, systemImage: "checkmark.shield")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !opportunity.screenNames.isEmpty {
                Text("Screens: \(opportunity.screenNames.joined(separator: ", "))")
                    .font(.caption)
            }

            if !opportunity.affectedElements.isEmpty {
                Text("Affected: \(opportunity.affectedElements.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(opportunity.remediation)
                .font(.subheadline)

            if let code = opportunity.swiftUIExample {
                codeBlock(title: opportunity.primaryExampleTitle, code: code)
            }

            if let code = opportunity.uikitExample {
                codeBlock(title: opportunity.secondaryExampleTitle, code: code)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .textBackgroundColor)))
    }

    private func codeBlock(title: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
            Text(code)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }
}
