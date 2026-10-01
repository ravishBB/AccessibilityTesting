//
//  AccessibilityIntelligence.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 30/09/26.

import Foundation
import SwiftUI

// MARK: - Common Models

enum IntelligenceStatus: String, Codable, CaseIterable {
    case pass
    case warning
    case fail
    case validate
    case notTested

    var title: String {
        switch self {
        case .pass: return "Pass"
        case .warning: return "Warning"
        case .fail: return "Fail"
        case .validate: return "Validate"
        case .notTested: return "Not tested"
        }
    }
}

struct IntelligenceMetric: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let value: Int
    let status: IntelligenceStatus
    let detail: String
}

struct VisualEngineResult: Codable, Hashable {
    let totalScreens: Int
    let screensWithScreenshots: Int
    let screensWithVisualFindings: Int
    let visualFindingCount: Int
    let annotatedScreens: Int
    let status: IntelligenceStatus
}

struct StateEngineResult: Codable, Hashable {
    let stateRelatedEvaluations: Int
    let stateFailures: Int
    let stateWarnings: Int
    let interactionValidations: Int
    let status: IntelligenceStatus
    let note: String
}

struct VoiceOverEngineResult: Codable, Hashable {
    let interactiveElementsObserved: Int
    let accessibleNameFailures: Int
    let hiddenInteractiveFailures: Int
    let roleStateFailures: Int
    let focusOrderValidations: Int
    let status: IntelligenceStatus
    let note: String
}

struct JourneyPath: Identifiable, Codable, Hashable {
    let id: UUID
    let screenSignatures: [String]
    let screenNames: [String]
    let status: IntelligenceStatus
    let blockingIssues: Int
    let warnings: Int

    var displayPath: String {
        screenNames.joined(separator: " → ")
    }
}

struct JourneyEngineResult: Codable, Hashable {
    let discoveredPaths: Int
    let blockedJourneys: Int
    let warningJourneys: Int
    let completedJourneys: Int
    let deadEndScreens: Int
    let unreachableScreens: Int
    let paths: [JourneyPath]
    let status: IntelligenceStatus
}

struct WCAGCriterionResult: Identifiable, Codable, Hashable {
    let id: String
    let criterion: String
    let title: String
    let level: String
    let status: IntelligenceStatus
    let failures: Int
    let warnings: Int
    let validations: Int
    let passes: Int
    let ruleIDs: [String]
}

struct WCAGEngineResult: Codable, Hashable {
    let criteria: [WCAGCriterionResult]
    let criteriaWithFailures: Int
    let criteriaWithValidation: Int
    let criteriaPassing: Int
    let criteriaNotTested: Int
    let unmappedRuleCount: Int
}

struct RegressionEngineResult: Codable, Hashable {
    let hasBaseline: Bool
    let newIssues: Int
    let fixedIssues: Int
    let unchangedIssues: Int
    let newScreens: Int
    let removedScreens: Int
    let status: IntelligenceStatus
}

struct AccessibilityIntelligence: Codable, Hashable {
    let generatedAt: Date
    let visual: VisualEngineResult
    let state: StateEngineResult
    let voiceOver: VoiceOverEngineResult
    let journey: JourneyEngineResult
    let wcag: WCAGEngineResult
    let regression: RegressionEngineResult
    let impactCenter: AccessibilityImpactCenter?

    var overallStatus: IntelligenceStatus {
        if [visual.status, state.status, voiceOver.status, journey.status]
            .contains(.fail) {
            return .fail
        }
        if [visual.status, state.status, voiceOver.status, journey.status]
            .contains(.warning) {
            return .warning
        }
        if [visual.status, state.status, voiceOver.status, journey.status]
            .contains(.validate) {
            return .validate
        }
        return .pass
    }
}

// MARK: - Regression Snapshot

struct AccessibilityRegressionSnapshot: Codable, Hashable {
    let applicationName: String
    let bundleID: String
    let screenSignatures: Set<String>
    let issueKeys: Set<String>
    let capturedAt: Date

    init(report: AccessibilityScanResult) {
        self.applicationName = report.applicationName
        self.bundleID = report.bundleID
        self.screenSignatures = Set(report.screens.map(\.signature))
        self.issueKeys = Set(
            report.screens.flatMap { screen in
                screen.evaluations
                    .filter {
                        $0.status == .fail ||
                        $0.status == .warning ||
                        $0.status == .validate
                    }
                    .map { evaluation in
                        Self.issueKey(screen: screen, evaluation: evaluation)
                    }
            }
        )
        self.capturedAt = report.finishedAt
    }

    static func issueKey(
        screen: ScreenScanResult,
        evaluation: AccessibilityRuleEvaluation
    ) -> String {
        [
            screen.signature,
            evaluation.ruleID,
            evaluation.elementType,
            evaluation.identifier,
            evaluation.elementLabel,
            String(format: "%.1f", evaluation.frameX),
            String(format: "%.1f", evaluation.frameY),
            String(format: "%.1f", evaluation.frameWidth),
            String(format: "%.1f", evaluation.frameHeight)
        ].joined(separator: "|")
    }
}

final class AccessibilityRegressionStore {
    static let shared = AccessibilityRegressionStore()

    private let defaults = UserDefaults.standard
    private let keyPrefix = "AccessibilityScanner.regression."

    private init() {}

    func load(bundleID: String) -> AccessibilityRegressionSnapshot? {
        guard let data = defaults.data(forKey: keyPrefix + bundleID) else {
            return nil
        }

        return try? JSONDecoder().decode(
            AccessibilityRegressionSnapshot.self,
            from: data
        )
    }

    func save(report: AccessibilityScanResult) {
        let snapshot = AccessibilityRegressionSnapshot(report: report)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: keyPrefix + report.bundleID)
    }
}

// MARK: - Engine

struct AccessibilityIntelligenceEngine {

    static func analyze(
        report: AccessibilityScanResult,
        baseline: AccessibilityRegressionSnapshot? = nil
    ) -> AccessibilityIntelligence {
        let visual = analyzeVisual(report)
        let state = analyzeState(report)
        let voiceOver = analyzeVoiceOver(report)
        let journey = analyzeJourneys(report)
        let wcag = analyzeWCAG(report)
        let regression = analyzeRegression(report, baseline: baseline)

        let provisional = AccessibilityIntelligence(
            generatedAt: Date(),
            visual: visual,
            state: state,
            voiceOver: voiceOver,
            journey: journey,
            wcag: wcag,
            regression: regression,
            impactCenter: nil
        )

        let impactCenter = AccessibilityImpactCenter.analyze(
            report: report,
            intelligence: provisional
        )

        return AccessibilityIntelligence(
            generatedAt: provisional.generatedAt,
            visual: visual,
            state: state,
            voiceOver: voiceOver,
            journey: journey,
            wcag: wcag,
            regression: regression,
            impactCenter: impactCenter
        )
    }

    // MARK: Visual Engine

    private static func analyzeVisual(
        _ report: AccessibilityScanResult
    ) -> VisualEngineResult {
        let visualRuleIDs: Set<String> = [
            "contrast-standard-text-4-5",
            "contrast-large-text-3",
            "contrast-standard-text-7",
            "contrast-large-text-4-5",
            "contrast-text-over-image",
            "contrast-opacity",
            "text-clipping",
            "text-resize",
            "non-text-contrast",
            "form-border-contrast",
            "target-size-enhanced-44",
            "target-size-minimum-24",
            "touch-target-size-44",
            "touch-target-size-24"
        ]

        let visualEvaluations = report.allEvaluations.filter {
            visualRuleIDs.contains($0.ruleID)
        }

        let visualProblems = visualEvaluations.filter {
            $0.status == .fail || $0.status == .warning
        }.count

        let screensWithVisualFindings = Set(
            report.screens.filter { screen in
                screen.evaluations.contains {
                    visualRuleIDs.contains($0.ruleID) &&
                    ($0.status == .fail || $0.status == .warning)
                }
            }.map(\.id)
        ).count

        let screenshots = report.screens.filter { $0.screenshot != nil }.count
        let annotated = report.screens.filter { !$0.annotations.isEmpty }.count

        let status: IntelligenceStatus
        if visualProblems > 0 {
            status = .fail
        } else if screenshots < report.screens.count && !report.screens.isEmpty {
            status = .validate
        } else {
            status = .pass
        }

        return VisualEngineResult(
            totalScreens: report.screens.count,
            screensWithScreenshots: screenshots,
            screensWithVisualFindings: screensWithVisualFindings,
            visualFindingCount: visualProblems,
            annotatedScreens: annotated,
            status: status
        )
    }

    // MARK: State Engine

    private static func analyzeState(
        _ report: AccessibilityScanResult
    ) -> StateEngineResult {
        let stateRuleIDs: Set<String> = [
            "button-disabled-state",
            "role-trait-consistency",
            "state-trait-consistency",
            "adjustable-accessibility-value",
            "segmented-control-interactive",
            "tab-accessibility",
            "modal-accessibility",
            "live-region",
            "loading-indicator-contrast",
            "time-limited-ui"
        ]

        let evaluations = report.allEvaluations.filter {
            stateRuleIDs.contains($0.ruleID)
        }

        let failures = evaluations.filter { $0.status == .fail }.count
        let warnings = evaluations.filter { $0.status == .warning }.count
        let validations = evaluations.filter { $0.status == .validate }.count

        let status: IntelligenceStatus
        if failures > 0 { status = .fail }
        else if warnings > 0 { status = .warning }
        else if validations > 0 { status = .validate }
        else { status = .pass }

        return StateEngineResult(
            stateRelatedEvaluations: evaluations.count,
            stateFailures: failures,
            stateWarnings: warnings,
            interactionValidations: validations,
            status: status,
            note: "This scan analyzes exposed accessibility state. Runtime before/after interaction changes require interaction replay."
        )
    }

    // MARK: VoiceOver Engine

    private static func analyzeVoiceOver(
        _ report: AccessibilityScanResult
    ) -> VoiceOverEngineResult {
        let interactiveTypes: Set<String> = [
            "XCUIElementTypeButton",
            "XCUIElementTypeTextField",
            "XCUIElementTypeSecureTextField",
            "XCUIElementTypeSlider",
            "XCUIElementTypeSwitch",
            "XCUIElementTypeStepper",
            "XCUIElementTypePickerWheel",
            "XCUIElementTypeLink"
        ]

        let interactiveEvaluations = report.allEvaluations.filter {
            interactiveTypes.contains($0.elementType)
        }

        let nameRuleIDs: Set<String> = [
            "accessible-name",
            "button-name-descriptive",
            "image-button-name",
            "interactive-name-descriptive",
            "image-accessible-label",
            "image-name-descriptive",
            "duplicate-interactive-name"
        ]

        let hiddenRuleIDs: Set<String> = [
            "interactive-screen-reader-hidden",
            "screen-reader-content"
        ]

        let roleStateRuleIDs: Set<String> = [
            "role-trait-consistency",
            "state-trait-consistency",
            "adjustable-accessibility-value",
            "button-disabled-state",
            "text-link-role",
            "text-button-role"
        ]

        let focusRuleIDs: Set<String> = [
            "focus-order"
        ]

        let nameFailures = report.allEvaluations.filter {
            nameRuleIDs.contains($0.ruleID) &&
            ($0.status == .fail || $0.status == .warning)
        }.count

        let hiddenFailures = report.allEvaluations.filter {
            hiddenRuleIDs.contains($0.ruleID) &&
            $0.status == .fail
        }.count

        let roleStateFailures = report.allEvaluations.filter {
            roleStateRuleIDs.contains($0.ruleID) &&
            $0.status == .fail
        }.count

        let focusValidations = report.allEvaluations.filter {
            focusRuleIDs.contains($0.ruleID) &&
            $0.status == .validate
        }.count

        let status: IntelligenceStatus
        if nameFailures + hiddenFailures + roleStateFailures > 0 {
            status = .fail
        } else if focusValidations > 0 {
            status = .validate
        } else {
            status = .pass
        }

        return VoiceOverEngineResult(
            interactiveElementsObserved: Set(
                interactiveEvaluations.map {
                    "\($0.elementType)|\($0.identifier)|\($0.elementLabel)|\($0.frameX)|\($0.frameY)"
                }
            ).count,
            accessibleNameFailures: nameFailures,
            hiddenInteractiveFailures: hiddenFailures,
            roleStateFailures: roleStateFailures,
            focusOrderValidations: focusValidations,
            status: status,
            note: "Hierarchy-based VoiceOver readiness analysis. This does not claim to run the VoiceOver runtime itself."
        )
    }

    // MARK: Journey Engine

    private static func analyzeJourneys(
        _ report: AccessibilityScanResult
    ) -> JourneyEngineResult {
        guard !report.screens.isEmpty else {
            return JourneyEngineResult(
                discoveredPaths: 0,
                blockedJourneys: 0,
                warningJourneys: 0,
                completedJourneys: 0,
                deadEndScreens: 0,
                unreachableScreens: 0,
                paths: [],
                status: .notTested
            )
        }

        let start = report.screens[0]
        var adjacency: [String: [String]] = [:]
        for screen in report.screens {
            adjacency[screen.signature] = screen.transitions
                .map(\.targetSignature)
                .filter { !$0.isEmpty }
        }

        var paths: [JourneyPath] = []
        let maxDepth = 7
        let maxPaths = 24

        func buildPaths(
            signatures: [String],
            names: [String]
        ) {
            guard paths.count < maxPaths else { return }
            guard let current = signatures.last else { return }

            let next = Array(
                Set(adjacency[current] ?? [])
            )

            if next.isEmpty || signatures.count >= maxDepth {
                let screens = signatures.compactMap { signature in
                    report.screens.first { $0.signature == signature }
                }
                let failures = screens.reduce(0) { $0 + $1.failures }
                let warnings = screens.reduce(0) { $0 + $1.warnings }
                let status: IntelligenceStatus = failures > 0
                    ? .fail
                    : warnings > 0
                        ? .warning
                        : .pass

                paths.append(
                    JourneyPath(
                        id: UUID(),
                        screenSignatures: signatures,
                        screenNames: names,
                        status: status,
                        blockingIssues: failures,
                        warnings: warnings
                    )
                )
                return
            }

            for target in next {
                guard paths.count < maxPaths else { return }
                guard !signatures.contains(target) else { continue }

                let name = report.screens.first {
                    $0.signature == target
                }?.name ?? "Unknown screen"

                buildPaths(
                    signatures: signatures + [target],
                    names: names + [name]
                )
            }
        }

        buildPaths(
            signatures: [start.signature],
            names: [start.name]
        )

        let reachable = reachableSignatures(
            from: start.signature,
            adjacency: adjacency
        )

        let deadEnds = report.screens.filter {
            (adjacency[$0.signature] ?? []).isEmpty
        }.count

        let blocked = paths.filter { $0.status == .fail }.count
        let warnings = paths.filter { $0.status == .warning }.count
        let completed = paths.filter { $0.status == .pass }.count

        let status: IntelligenceStatus
        if blocked > 0 { status = .fail }
        else if warnings > 0 { status = .warning }
        else if paths.isEmpty { status = .validate }
        else { status = .pass }

        return JourneyEngineResult(
            discoveredPaths: paths.count,
            blockedJourneys: blocked,
            warningJourneys: warnings,
            completedJourneys: completed,
            deadEndScreens: deadEnds,
            unreachableScreens: max(0, report.screens.count - reachable.count),
            paths: paths,
            status: status
        )
    }

    private static func reachableSignatures(
        from start: String,
        adjacency: [String: [String]]
    ) -> Set<String> {
        var visited: Set<String> = []
        var queue: [String] = [start]

        while let current = queue.first {
            queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            queue.append(contentsOf: adjacency[current] ?? [])
        }

        return visited
    }

    // MARK: WCAG Layer

    private struct WCGMapping {
        let criterion: String
        let title: String
        let level: String
    }

    private static let wcagMappings: [String: WCGMapping] = [
        "accessible-name": .init(criterion: "4.1.2", title: "Name, Role, Value", level: "A"),
        "button-name-descriptive": .init(criterion: "4.1.2", title: "Name, Role, Value", level: "A"),
        "image-button-name": .init(criterion: "4.1.2", title: "Name, Role, Value", level: "A"),
        "interactive-name-descriptive": .init(criterion: "4.1.2", title: "Name, Role, Value", level: "A"),
        "image-accessible-label": .init(criterion: "1.1.1", title: "Non-text Content", level: "A"),
        "image-name-descriptive": .init(criterion: "1.1.1", title: "Non-text Content", level: "A"),
        "contrast-standard-text-4-5": .init(criterion: "1.4.3", title: "Contrast (Minimum)", level: "AA"),
        "contrast-large-text-3": .init(criterion: "1.4.3", title: "Contrast (Minimum)", level: "AA"),
        "contrast-standard-text-7": .init(criterion: "1.4.6", title: "Contrast (Enhanced)", level: "AAA"),
        "contrast-large-text-4-5": .init(criterion: "1.4.6", title: "Contrast (Enhanced)", level: "AAA"),
        "contrast-text-over-image": .init(criterion: "1.4.3", title: "Contrast (Minimum)", level: "AA"),
        "contrast-opacity": .init(criterion: "1.4.3", title: "Contrast (Minimum)", level: "AA"),
        "non-text-contrast": .init(criterion: "1.4.11", title: "Non-text Contrast", level: "AA"),
        "form-border-contrast": .init(criterion: "1.4.11", title: "Non-text Contrast", level: "AA"),
        "text-resize": .init(criterion: "1.4.4", title: "Resize Text", level: "AA"),
        "text-clipping": .init(criterion: "1.4.4", title: "Resize Text", level: "AA"),
        "target-size-minimum-24": .init(criterion: "2.5.8", title: "Target Size (Minimum)", level: "AA"),
        "touch-target-size-24": .init(criterion: "2.5.8", title: "Target Size (Minimum)", level: "AA"),
        "focus-order": .init(criterion: "2.4.3", title: "Focus Order", level: "A"),
        "screen-title": .init(criterion: "2.4.2", title: "Page Titled / Screen Title", level: "A"),
        "text-link-role": .init(criterion: "4.1.2", title: "Name, Role, Value", level: "A"),
        "text-button-role": .init(criterion: "4.1.2", title: "Name, Role, Value", level: "A"),
        "role-trait-consistency": .init(criterion: "4.1.2", title: "Name, Role, Value", level: "A"),
        "state-trait-consistency": .init(criterion: "4.1.2", title: "Name, Role, Value", level: "A"),
        "adjustable-accessibility-value": .init(criterion: "4.1.2", title: "Name, Role, Value", level: "A"),
        "motion-alternative": .init(criterion: "2.5.4", title: "Motion Actuation", level: "A"),
        "form-autocomplete": .init(criterion: "1.3.5", title: "Identify Input Purpose", level: "AA"),
        "language": .init(criterion: "3.1.1", title: "Language of Page / App", level: "A"),
        "modal-accessibility": .init(criterion: "2.1.2", title: "No Keyboard Trap", level: "A"),
        "live-region": .init(criterion: "4.1.3", title: "Status Messages", level: "AA"),
        "loading-indicator-contrast": .init(criterion: "1.4.11", title: "Non-text Contrast", level: "AA"),
        "time-limited-ui": .init(criterion: "2.2.1", title: "Timing Adjustable", level: "A")
    ]

    private static func analyzeWCAG(
        _ report: AccessibilityScanResult
    ) -> WCAGEngineResult {
        var grouped: [String: [AccessibilityRuleEvaluation]] = [:]

        for evaluation in report.allEvaluations {
            guard let mapping = wcagMappings[evaluation.ruleID] else { continue }
            grouped[mapping.criterion, default: []].append(evaluation)
        }

        let criteria = grouped.compactMap { criterion, evaluations -> WCAGCriterionResult? in
            guard let mapping = wcagMappings[evaluations[0].ruleID] else { return nil }

            let failures = evaluations.filter { $0.status == .fail }.count
            let warnings = evaluations.filter { $0.status == .warning }.count
            let validations = evaluations.filter { $0.status == .validate }.count
            let passes = evaluations.filter { $0.status == .pass }.count

            let status: IntelligenceStatus
            if failures > 0 { status = .fail }
            else if warnings > 0 { status = .warning }
            else if validations > 0 { status = .validate }
            else { status = .pass }

            return WCAGCriterionResult(
                id: criterion,
                criterion: criterion,
                title: mapping.title,
                level: mapping.level,
                status: status,
                failures: failures,
                warnings: warnings,
                validations: validations,
                passes: passes,
                ruleIDs: Array(Set(evaluations.map(\.ruleID))).sorted()
            )
        }
        .sorted {
            $0.criterion.localizedStandardCompare($1.criterion) == .orderedAscending
        }

        let mappedRuleIDs = Set(wcagMappings.keys)
        let unmappedRuleCount = Set(
            report.allEvaluations.map(\.ruleID)
        ).subtracting(mappedRuleIDs).count

        return WCAGEngineResult(
            criteria: criteria,
            criteriaWithFailures: criteria.filter { $0.status == .fail }.count,
            criteriaWithValidation: criteria.filter { $0.status == .validate }.count,
            criteriaPassing: criteria.filter { $0.status == .pass }.count,
            criteriaNotTested: 0,
            unmappedRuleCount: unmappedRuleCount
        )
    }

    // MARK: Regression

    private static func analyzeRegression(
        _ report: AccessibilityScanResult,
        baseline: AccessibilityRegressionSnapshot?
    ) -> RegressionEngineResult {
        guard let baseline else {
            return RegressionEngineResult(
                hasBaseline: false,
                newIssues: 0,
                fixedIssues: 0,
                unchangedIssues: 0,
                newScreens: 0,
                removedScreens: 0,
                status: .notTested
            )
        }

        let current = AccessibilityRegressionSnapshot(report: report)
        let newIssues = current.issueKeys.subtracting(baseline.issueKeys).count
        let fixedIssues = baseline.issueKeys.subtracting(current.issueKeys).count
        let unchanged = current.issueKeys.intersection(baseline.issueKeys).count
        let newScreens = current.screenSignatures.subtracting(baseline.screenSignatures).count
        let removedScreens = baseline.screenSignatures.subtracting(current.screenSignatures).count

        let status: IntelligenceStatus = newIssues > 0 ? .fail : .pass

        return RegressionEngineResult(
            hasBaseline: true,
            newIssues: newIssues,
            fixedIssues: fixedIssues,
            unchangedIssues: unchanged,
            newScreens: newScreens,
            removedScreens: removedScreens,
            status: status
        )
    }
}

// MARK: - Report Integration Helpers

extension AccessibilityScanResult {
    func settingIntelligence(
        _ intelligence: AccessibilityIntelligence
    ) -> AccessibilityScanResult {
        AccessibilityScanResult(
            id: id,
            applicationName: applicationName,
            bundleID: bundleID,
            deviceName: deviceName,
            deviceUDID: deviceUDID,
            startedAt: startedAt,
            finishedAt: finishedAt,
            screens: screens,
            rulesExecuted: rulesExecuted,
            intelligence: intelligence
        )
    }
}

// MARK: - Intelligence UI

struct AccessibilityIntelligenceView: View {
    let intelligence: AccessibilityIntelligence

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            engineGrid
            journeySection
            wcagSection
            regressionSection
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Accessibility Analysis")
                .font(.title2)
                .fontWeight(.bold)
            Text("Combined analysis of visual checks, control state, assistive technology, journeys, WCAG mappings and scan-to-scan changes.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var engineGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            engineCard("Visual Engine", symbol: "eye", status: intelligence.visual.status) {
                Text("\(intelligence.visual.visualFindingCount) visual findings")
                Text("\(intelligence.visual.screensWithScreenshots)/\(intelligence.visual.totalScreens) screens have screenshots")
            }
            engineCard("State Engine", symbol: "switch.2", status: intelligence.state.status) {
                Text("\(intelligence.state.stateFailures) state failures")
                Text("\(intelligence.state.interactionValidations) validations")
            }
            engineCard("VoiceOver Checks", symbol: "person.wave.2", status: intelligence.voiceOver.status) {
                Text("\(intelligence.voiceOver.interactiveElementsObserved) interactive elements")
                Text("\(intelligence.voiceOver.accessibleNameFailures) name issues")
            }
            engineCard("Journey Engine", symbol: "point.3.connected.trianglepath.dotted", status: intelligence.journey.status) {
                Text("\(intelligence.journey.discoveredPaths) paths")
                Text("\(intelligence.journey.blockedJourneys) blocked journeys")
            }
        }
    }

    private func engineCard<Content: View>(
        _ title: String,
        symbol: String,
        status: IntelligenceStatus,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.headline)
                Spacer()
                statusBadge(status)
            }
            content()
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }

    private var journeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Journey Analysis")
                    .font(.headline)
                Spacer()
                statusBadge(intelligence.journey.status)
            }

            HStack(spacing: 20) {
                metric("Paths", intelligence.journey.discoveredPaths)
                metric("Blocked", intelligence.journey.blockedJourneys)
                metric("Warnings", intelligence.journey.warningJourneys)
                metric("Completed", intelligence.journey.completedJourneys)
                metric("Dead ends", intelligence.journey.deadEndScreens)
                metric("Unreachable", intelligence.journey.unreachableScreens)
            }

            if intelligence.journey.paths.isEmpty {
                Text("No navigable journey path was retained. Additional interaction testing is required for deeper workflow validation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(intelligence.journey.paths) { path in
                        HStack(alignment: .top, spacing: 8) {
                            statusDot(path.status)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(path.displayPath)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text("\(path.blockingIssues) blocking issue(s) • \(path.warnings) warning(s)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var wcagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WCAG 2.2 Mapping")
                    .font(.headline)
                Spacer()
                Text("\(intelligence.wcag.criteria.count) criteria")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if intelligence.wcag.criteria.isEmpty {
                Text("No WCAG criteria were exercised by the current rule set.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(intelligence.wcag.criteria) { criterion in
                    HStack(spacing: 10) {
                        statusDot(criterion.status)
                        Text("\(criterion.criterion) — \(criterion.title)")
                            .font(.caption)
                        Text(criterion.level)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.10))
                            .clipShape(Capsule())
                        Spacer()
                        Text("F \(criterion.failures) • W \(criterion.warnings) • V \(criterion.validations) • P \(criterion.passes)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var regressionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Regression")
                    .font(.headline)
                Spacer()
                statusBadge(intelligence.regression.status)
            }

            if !intelligence.regression.hasBaseline {
                Text("No previous baseline is available. The next scan will establish the comparison baseline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 20) {
                    metric("New", intelligence.regression.newIssues)
                    metric("Fixed", intelligence.regression.fixedIssues)
                    metric("Unchanged", intelligence.regression.unchangedIssues)
                    metric("Added screens", intelligence.regression.newScreens)
                    metric("Removed screens", intelligence.regression.removedScreens)
                }
            }
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

    private func statusBadge(_ status: IntelligenceStatus) -> some View {
        Text(status.title)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(status).opacity(0.12))
            .foregroundStyle(statusColor(status))
            .clipShape(Capsule())
    }

    private func statusDot(_ status: IntelligenceStatus) -> some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: 8, height: 8)
            .padding(.top, 5)
    }

    private func statusColor(_ status: IntelligenceStatus) -> Color {
        switch status {
        case .pass: return .green
        case .warning: return .orange
        case .fail: return .red
        case .validate: return .yellow
        case .notTested: return .gray
        }
    }
}
