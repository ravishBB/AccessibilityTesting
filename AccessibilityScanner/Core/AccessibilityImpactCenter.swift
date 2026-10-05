//
//  AccessibilityImpactCenter.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 24/09/26.



import Foundation
import SwiftUI

struct AccessibilityHotspot: Identifiable, Codable, Hashable {
    let id: String
    let screenName: String
    let signature: String
    let failures: Int
    let warnings: Int
    let validations: Int
    let affectedElements: Int
    let outgoingPaths: Int
    let journeyExposure: Int
    let blockedJourneyExposure: Int
    let impactScore: Int

    var status: IntelligenceStatus {
        if failures > 0 { return .fail }
        if warnings > 0 { return .warning }
        if validations > 0 { return .validate }
        return .pass
    }
}

struct AccessibilityImpactCenter: Codable, Hashable {
    let hotspots: [AccessibilityHotspot]
    let topFixes: [AccessibilityFixOpportunity]
    let totalJourneyExposure: Int
    let blockedJourneyExposure: Int
    let highestImpactScore: Int

    static func analyze(
        report: AccessibilityScanResult,
        intelligence: AccessibilityIntelligence
    ) -> AccessibilityImpactCenter {
        let paths = intelligence.journey.paths

        var pathCountByScreen: [String: Int] = [:]
        var blockedPathCountByScreen: [String: Int] = [:]

        for path in paths {
            let uniqueScreens = Set(path.screenSignatures)
            for signature in uniqueScreens {
                pathCountByScreen[signature, default: 0] += 1
                if path.status == .fail {
                    blockedPathCountByScreen[signature, default: 0] += 1
                }
            }
        }

        let hotspots = report.screens.map { screen -> AccessibilityHotspot in
            let exposure = pathCountByScreen[screen.signature, default: 0]
            let blockedExposure = blockedPathCountByScreen[screen.signature, default: 0]
            let severityWeight = screen.failures * 5 + screen.warnings * 3 + screen.validations * 2
            let centralityBonus = max(1, exposure)
            let impact = severityWeight * centralityBonus + blockedExposure * 5

            return AccessibilityHotspot(
                id: screen.signature,
                screenName: screen.name,
                signature: screen.signature,
                failures: screen.failures,
                warnings: screen.warnings,
                validations: screen.validations,
                affectedElements: screen.affectedElements,
                outgoingPaths: screen.transitions.count,
                journeyExposure: exposure,
                blockedJourneyExposure: blockedExposure,
                impactScore: impact
            )
        }
        .sorted {
            if $0.impactScore != $1.impactScore {
                return $0.impactScore > $1.impactScore
            }
            return $0.screenName.localizedCaseInsensitiveCompare($1.screenName) == .orderedAscending
        }

        var evaluationsByRule: [String: [AccessibilityRuleEvaluation]] = [:]
        for screen in report.screens {
            for evaluation in screen.evaluations where evaluation.status != .pass {
                evaluationsByRule[evaluation.ruleID, default: []].append(evaluation)
            }
        }

        let topFixes = evaluationsByRule.compactMap { ruleID, evaluations -> AccessibilityFixOpportunity? in
            guard let first = evaluations.first else { return nil }

            let screenSignatures = Set(
                report.screens.compactMap { screen in
                    screen.evaluations.contains { $0.ruleID == ruleID && $0.status != .pass }
                        ? screen.signature
                        : nil
                }
            )

            let affectedJourneys = paths.filter { path in
                !Set(path.screenSignatures).isDisjoint(with: screenSignatures)
            }

            let blockedJourneys = affectedJourneys.filter { $0.status == .fail }.count
            let statusWeight: Int
            switch first.status {
            case .fail: statusWeight = 5
            case .warning: statusWeight = 3
            case .validate: statusWeight = 2
            case .pass: statusWeight = 0
            }

            let impact = statusWeight * max(1, screenSignatures.count)
                + affectedJourneys.count * 2
                + blockedJourneys * 5
                + min(evaluations.count, 10)

            let names = report.screens
                .filter { screenSignatures.contains($0.signature) }
                .map(\.name)
                .sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                }

            let elements = Array(Set(evaluations.map { evaluation in
                let label = evaluation.elementLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                let identifier = evaluation.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty { return label }
                if !identifier.isEmpty { return identifier }
                return evaluation.elementType
            }).sorted().prefix(5))

            let guidance = AccessibilityFixGuidance.forRule(ruleID: ruleID, first: first)

            return AccessibilityFixOpportunity(
                id: ruleID,
                ruleID: ruleID,
                ruleName: first.ruleName,
                severity: first.severity,
                occurrences: evaluations.count,
                affectedScreens: screenSignatures.count,
                screenNames: names,
                affectedElements: elements,
                remediation: guidance.remediation,
                confidence: guidance.confidence,
                swiftUIExample: guidance.swiftUIExample,
                uikitExample: guidance.uikitExample,
                status: first.status,
                affectedJourneys: affectedJourneys.count,
                blockedJourneys: blockedJourneys,
                impactScore: impact,
                platform: first.platform
            )
        }
        .sorted {
            if $0.impactScore != $1.impactScore {
                return $0.impactScore > $1.impactScore
            }
            return $0.ruleName.localizedCaseInsensitiveCompare($1.ruleName) == .orderedAscending
        }
        .prefix(8)
        .map { $0 }

        return AccessibilityImpactCenter(
            hotspots: Array(hotspots.prefix(10)),
            topFixes: Array(topFixes),
            totalJourneyExposure: paths.count,
            blockedJourneyExposure: paths.filter { $0.status == .fail }.count,
            highestImpactScore: hotspots.first?.impactScore ?? 0
        )
    }
}

struct AccessibilityImpactCenterView: View {
    let impact: AccessibilityImpactCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            exposureCards
            topFixes
            hotspots
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Fix Priorities")
                    .font(.headline)
                Spacer()
                Label("Priority analysis", systemImage: "scope")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var exposureCards: some View {
        HStack(spacing: 12) {
            impactMetric(
                title: "Workflow coverage",
                value: impact.totalJourneyExposure,
                subtitle: "discovered journeys",
                symbol: "point.3.connected.trianglepath.dotted"
            )
            impactMetric(
                title: "Blocked journeys",
                value: impact.blockedJourneyExposure,
                subtitle: "journeys with failures",
                symbol: "nosign"
            )
            impactMetric(
                title: "Highest priority",
                value: impact.highestImpactScore,
                subtitle: "priority score",
                symbol: "flame.fill"
            )
        }
    }

    private func impactMetric(
        title: String,
        value: Int,
        subtitle: String,
        symbol: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.headline)
                    .monospacedDigit()
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }

    private var topFixes: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Priority Findings")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(impact.topFixes.count) findings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if impact.topFixes.isEmpty {
                Text("No findings require prioritization.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(impact.topFixes.enumerated()), id: \.offset) { index, fix in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(fixColor(fix.status))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(fix.ruleName)
                                        .font(.callout)
                                        .fontWeight(.semibold)
                                        .lineLimit(2)
                                    Text("\(fix.occurrences) occurrences • \(fix.affectedScreens) screens • \(fix.affectedJourneys) journeys • \(fix.blockedJourneys) blocked")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(fix.impactScore)")
                                        .font(.headline)
                                        .monospacedDigit()
                                    Text("priority score")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if !fix.remediation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(fix.remediation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if !fix.screenNames.isEmpty {
                                Text("Affected screens: " + fix.screenNames.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.secondary.opacity(0.045))
                        )
                    }
                }
            }
        }
    }

    private var hotspots: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Screen Priorities")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("workflow-aware")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if impact.hotspots.isEmpty {
                Text("No screen data is available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(impact.hotspots) { hotspot in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(fixColor(hotspot.status))
                                .frame(width: 9, height: 9)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(hotspot.screenName)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                Text("F \(hotspot.failures) • W \(hotspot.warnings) • V \(hotspot.validations) • \(hotspot.journeyExposure) journeys")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("\(hotspot.impactScore)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func fixColor(_ status: IntelligenceStatus) -> Color {
        switch status {
        case .fail: return .red
        case .warning: return .orange
        case .validate: return .yellow
        case .pass: return .green
        case .notTested: return .gray
        }
    }

    private func fixColor(_ status: RuleResultStatus) -> Color {
        switch status {
        case .fail: return .red
        case .warning: return .orange
        case .validate: return .yellow
        case .pass: return .green
        }
    }
}
