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

struct VoiceOverFocusStop: Identifiable, Codable, Hashable {
    let id: UUID
    let position: Int
    let elementType: String
    let label: String
    let identifier: String
    let frameX: Double
    let frameY: Double
    let frameWidth: Double
    let frameHeight: Double
    let status: IntelligenceStatus
    let issue: String?

    var displayName: String {
        if !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return label
        }
        if !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return identifier
        }
        return elementType
    }
}

struct VoiceOverJourneyScreen: Identifiable, Codable, Hashable {
    let id: UUID
    let screenName: String
    let screenSignature: String
    let focusStops: [VoiceOverFocusStop]
    let issueCount: Int
    let validationCount: Int

    var status: IntelligenceStatus {
        if issueCount > 0 { return .fail }
        if validationCount > 0 { return .validate }
        return .pass
    }
}

struct VoiceOverEngineResult: Codable, Hashable {
    let interactiveElementsObserved: Int
    let accessibleNameFailures: Int
    let hiddenInteractiveFailures: Int
    let roleStateFailures: Int
    let focusOrderValidations: Int
    let focusStopsObserved: Int
    let screensWithFocusSequences: Int
    let screensWithFocusIssues: Int
    let focusSequences: [VoiceOverJourneyScreen]
    let status: IntelligenceStatus
    let note: String
}

struct ResponsiveAccessibilityResult: Codable, Hashable {
    let tested: Bool
    let originalOrientation: String?
    let testedOrientation: String?
    let orientationChanged: Bool
    let landscapeElementCount: Int
    let landscapeFailureCount: Int
    let landscapeWarningCount: Int
    let landscapeValidationCount: Int
    let landscapeScreenshotCaptured: Bool
    let dynamicTypeValidationCount: Int
    let dynamicTypeFailureCount: Int
    let status: IntelligenceStatus
    let note: String

    static let notTested = ResponsiveAccessibilityResult(
        tested: false,
        originalOrientation: nil,
        testedOrientation: nil,
        orientationChanged: false,
        landscapeElementCount: 0,
        landscapeFailureCount: 0,
        landscapeWarningCount: 0,
        landscapeValidationCount: 0,
        landscapeScreenshotCaptured: false,
        dynamicTypeValidationCount: 0,
        dynamicTypeFailureCount: 0,
        status: .notTested,
        note: "Runtime orientation testing was not performed."
    )
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

struct AccessibilityRegressionIssueSnapshot: Codable, Hashable {
    let key: String
    let screenName: String
    let screenSignature: String
    let ruleID: String
    let ruleName: String
    let status: RuleResultStatus
    let severity: AccessibilityFinding.Severity
    let message: String
    let remediation: String
    let elementType: String
    let elementLabel: String
    let identifier: String
    let value: String
    let frameX: Double
    let frameY: Double
    let frameWidth: Double
    let frameHeight: Double
}

struct AccessibilityDiffIssue: Identifiable, Codable, Hashable {
    let id: String
    let change: String
    let issue: AccessibilityRegressionIssueSnapshot
}

struct AccessibilityDiffScreenChange: Identifiable, Codable, Hashable {
    let id: String
    let change: String
    let screenName: String
    let signature: String
}

struct AccessibilityDiffResult: Codable, Hashable {
    let hasBaseline: Bool
    let newIssues: [AccessibilityDiffIssue]
    let fixedIssues: [AccessibilityDiffIssue]
    let addedScreens: [AccessibilityDiffScreenChange]
    let removedScreens: [AccessibilityDiffScreenChange]

    static let notTested = AccessibilityDiffResult(
        hasBaseline: false,
        newIssues: [],
        fixedIssues: [],
        addedScreens: [],
        removedScreens: []
    )
}

// MARK: - Accessibility Quality Gate

struct AccessibilityQualityGatePolicy: Codable, Hashable {
    let failOnNewIssues: Bool
    let failOnCriticalFailures: Bool
    let failOnBlockedJourneys: Bool
    let failOnWCAGAAFailures: Bool

    static let productionDefault = AccessibilityQualityGatePolicy(
        failOnNewIssues: true,
        failOnCriticalFailures: true,
        failOnBlockedJourneys: true,
        failOnWCAGAAFailures: false
    )
}

struct AccessibilityQualityGateCheck: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let value: Int
    let enforced: Bool
    let passed: Bool
    let detail: String
}

struct AccessibilityQualityGateResult: Codable, Hashable {
    let policy: AccessibilityQualityGatePolicy
    let status: IntelligenceStatus
    let checks: [AccessibilityQualityGateCheck]

    var enforcedFailureCount: Int {
        checks.filter { $0.enforced && !$0.passed }.count
    }
}

struct AccessibilityIntelligence: Codable, Hashable {
    let generatedAt: Date
    let visual: VisualEngineResult
    let state: StateEngineResult
    let responsive: ResponsiveAccessibilityResult
    let voiceOver: VoiceOverEngineResult
    let journey: JourneyEngineResult
    let wcag: WCAGEngineResult
    let regression: RegressionEngineResult
    let diff: AccessibilityDiffResult?
    let qualityGate: AccessibilityQualityGateResult
    let impactCenter: AccessibilityImpactCenter?
    let fixCenter: AccessibilityFixCenter?

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
    let screenNames: [String: String]
    let issueKeys: Set<String>
    let issueDetails: [String: AccessibilityRegressionIssueSnapshot]
    let capturedAt: Date

    private enum CodingKeys: String, CodingKey {
        case applicationName, bundleID, screenSignatures, screenNames, issueKeys, issueDetails, capturedAt
    }

    init(report: AccessibilityScanResult) {
        self.applicationName = report.applicationName
        self.bundleID = report.bundleID
        self.screenSignatures = Set(report.screens.map(\.signature))
        self.screenNames = Dictionary(uniqueKeysWithValues: report.screens.map { ($0.signature, $0.name) })

        var details: [String: AccessibilityRegressionIssueSnapshot] = [:]
        for screen in report.screens {
            for evaluation in screen.evaluations where
                evaluation.status == .fail ||
                evaluation.status == .warning ||
                evaluation.status == .validate {
                let key = Self.issueKey(screen: screen, evaluation: evaluation)
                details[key] = AccessibilityRegressionIssueSnapshot(
                    key: key,
                    screenName: screen.name,
                    screenSignature: screen.signature,
                    ruleID: evaluation.ruleID,
                    ruleName: evaluation.ruleName,
                    status: evaluation.status,
                    severity: evaluation.severity,
                    message: evaluation.message,
                    remediation: evaluation.remediation,
                    elementType: evaluation.elementType,
                    elementLabel: evaluation.elementLabel,
                    identifier: evaluation.identifier,
                    value: evaluation.value ?? "",
                    frameX: evaluation.frameX,
                    frameY: evaluation.frameY,
                    frameWidth: evaluation.frameWidth,
                    frameHeight: evaluation.frameHeight
                )
            }
        }
        self.issueDetails = details
        self.issueKeys = Set(details.keys)
        self.capturedAt = report.finishedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        applicationName = try container.decode(String.self, forKey: .applicationName)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        screenSignatures = try container.decode(Set<String>.self, forKey: .screenSignatures)
        screenNames = try container.decodeIfPresent([String: String].self, forKey: .screenNames) ?? [:]
        issueKeys = try container.decode(Set<String>.self, forKey: .issueKeys)
        issueDetails = try container.decodeIfPresent([String: AccessibilityRegressionIssueSnapshot].self, forKey: .issueDetails) ?? [:]
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
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
        baseline: AccessibilityRegressionSnapshot? = nil,
        responsive: ResponsiveAccessibilityResult = .notTested
    ) -> AccessibilityIntelligence {
        let visual = analyzeVisual(report)
        let state = analyzeState(report)
        let voiceOver = analyzeVoiceOver(report)
        let journey = analyzeJourneys(report)
        let wcag = analyzeWCAG(report)
        let regression = analyzeRegression(report, baseline: baseline)
        let diff = analyzeAccessibilityDiff(report, baseline: baseline)

        let provisionalWithoutGate = AccessibilityIntelligence(
            generatedAt: Date(),
            visual: visual,
            state: state,
            responsive: responsive,
            voiceOver: voiceOver,
            journey: journey,
            wcag: wcag,
            regression: regression,
            diff: diff,
            qualityGate: AccessibilityQualityGateResult(
                policy: .productionDefault,
                status: .notTested,
                checks: []
            ),
            impactCenter: nil,
            fixCenter: nil
        )

        let qualityGate = analyzeQualityGate(
            report: report,
            intelligence: provisionalWithoutGate,
            policy: .productionDefault
        )

        let provisional = AccessibilityIntelligence(
            generatedAt: provisionalWithoutGate.generatedAt,
            visual: visual,
            state: state,
            responsive: responsive,
            voiceOver: voiceOver,
            journey: journey,
            wcag: wcag,
            regression: regression,
            diff: diff,
            qualityGate: qualityGate,
            impactCenter: nil,
            fixCenter: nil
        )

        let impactCenter = AccessibilityImpactCenter.analyze(
            report: report,
            intelligence: provisional
        )
        let fixCenter = AccessibilityFixCenter.analyze(report: report)

        return AccessibilityIntelligence(
            generatedAt: provisional.generatedAt,
            visual: visual,
            state: state,
            responsive: responsive,
            voiceOver: voiceOver,
            journey: journey,
            wcag: wcag,
            regression: regression,
            diff: diff,
            qualityGate: qualityGate,
            impactCenter: impactCenter,
            fixCenter: fixCenter
        )
    }

    // MARK: Quality Gate

    private static func analyzeQualityGate(
        report: AccessibilityScanResult,
        intelligence: AccessibilityIntelligence,
        policy: AccessibilityQualityGatePolicy
    ) -> AccessibilityQualityGateResult {
        let criticalFailures = report.allEvaluations.filter {
            $0.status == .fail && $0.severity == .error
        }.count

        let aaFailures = intelligence.wcag.criteria
            .filter { $0.level == "AA" }
            .reduce(0) { $0 + $1.failures }

        let newIssues = intelligence.regression.hasBaseline
            ? intelligence.regression.newIssues
            : 0

        let checks = [
            AccessibilityQualityGateCheck(
                id: "new-issues",
                title: "New accessibility issues",
                value: newIssues,
                enforced: policy.failOnNewIssues && intelligence.regression.hasBaseline,
                passed: newIssues == 0,
                detail: intelligence.regression.hasBaseline
                    ? (newIssues == 0 ? "No new issues compared with the previous baseline." : "New issues were detected since the previous baseline.")
                    : "No previous baseline is available; this check will be enforced on the next comparison scan."
            ),
            AccessibilityQualityGateCheck(
                id: "critical-failures",
                title: "Critical accessibility failures",
                value: criticalFailures,
                enforced: policy.failOnCriticalFailures,
                passed: criticalFailures == 0,
                detail: criticalFailures == 0
                    ? "No error-severity accessibility failures were recorded."
                    : "Error-severity failures require correction before release."
            ),
            AccessibilityQualityGateCheck(
                id: "blocked-journeys",
                title: "Blocked journeys",
                value: intelligence.journey.blockedJourneys,
                enforced: policy.failOnBlockedJourneys,
                passed: intelligence.journey.blockedJourneys == 0,
                detail: intelligence.journey.blockedJourneys == 0
                    ? "No discovered journey was blocked by accessibility findings."
                    : "One or more discovered workflows contain blocking accessibility findings."
            ),
            AccessibilityQualityGateCheck(
                id: "wcag-aa",
                title: "WCAG 2.2 AA failures",
                value: aaFailures,
                enforced: policy.failOnWCAGAAFailures,
                passed: aaFailures == 0,
                detail: aaFailures == 0
                    ? "No mapped WCAG 2.2 AA failures were recorded."
                    : (policy.failOnWCAGAAFailures ? "Mapped AA failures are configured to block release." : "AA failures are reported but are not configured to block release.")
            )
        ]

        let enforcedFailures = checks.filter { $0.enforced && !$0.passed }.count
        let status: IntelligenceStatus
        if enforcedFailures > 0 {
            status = .fail
        } else if !intelligence.regression.hasBaseline || intelligence.journey.status == .notTested {
            status = .validate
        } else {
            status = .pass
        }

        return AccessibilityQualityGateResult(
            policy: policy,
            status: status,
            checks: checks
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
        let interactiveTypes: Set<AccessibilityRole> =
            AccessibilityRole.controls.union([.link])

        let interactiveEvaluations = report.allEvaluations.filter {
            interactiveTypes.contains($0.elementRole)
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

        let sequences = report.screens.map { screen in
            buildVoiceOverSequence(
                screen: screen,
                interactiveTypes: interactiveTypes,
                nameRuleIDs: nameRuleIDs,
                hiddenRuleIDs: hiddenRuleIDs,
                roleStateRuleIDs: roleStateRuleIDs,
                focusRuleIDs: focusRuleIDs
            )
        }.filter { !$0.focusStops.isEmpty }

        let sequenceIssueCount = sequences.reduce(0) { $0 + $1.issueCount }
        let sequenceValidationCount = sequences.reduce(0) { $0 + $1.validationCount }
        let status: IntelligenceStatus
        if nameFailures + hiddenFailures + roleStateFailures > 0 || sequenceIssueCount > 0 {
            status = .fail
        } else if focusValidations > 0 || sequenceValidationCount > 0 {
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
            focusStopsObserved: sequences.reduce(0) { $0 + $1.focusStops.count },
            screensWithFocusSequences: sequences.count,
            screensWithFocusIssues: sequences.filter { $0.issueCount > 0 }.count,
            focusSequences: sequences,
            status: status,
            note: "Focus sequences are inferred from the scanned accessibility hierarchy and element geometry. VoiceOver itself is not enabled or driven by this analysis."
        )
    }

    private static func buildVoiceOverSequence(
        screen: ScreenScanResult,
        interactiveTypes: Set<AccessibilityRole>,
        nameRuleIDs: Set<String>,
        hiddenRuleIDs: Set<String>,
        roleStateRuleIDs: Set<String>,
        focusRuleIDs: Set<String>
    ) -> VoiceOverJourneyScreen {
        let candidates = screen.evaluations.filter { evaluation in
            interactiveTypes.contains(evaluation.elementRole) ||
            !evaluation.elementLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.sorted { lhs, rhs in
            if lhs.frameY != rhs.frameY { return lhs.frameY < rhs.frameY }
            if lhs.frameX != rhs.frameX { return lhs.frameX < rhs.frameX }
            return lhs.elementType < rhs.elementType
        }

        var seenNames: Set<String> = []
        var stops: [VoiceOverFocusStop] = []

        for (index, evaluation) in candidates.enumerated() {
            let trimmedLabel = evaluation.elementLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            let hidden = hiddenRuleIDs.contains(evaluation.ruleID) && evaluation.status == .fail
            let nameIssue = nameRuleIDs.contains(evaluation.ruleID) &&
                (evaluation.status == .fail || evaluation.status == .warning)
            let roleIssue = roleStateRuleIDs.contains(evaluation.ruleID) && evaluation.status == .fail
            let focusValidation = focusRuleIDs.contains(evaluation.ruleID) && evaluation.status == .validate

            let duplicateKey = trimmedLabel.lowercased()
            let duplicate = !duplicateKey.isEmpty && seenNames.contains(duplicateKey)
            if !duplicateKey.isEmpty { seenNames.insert(duplicateKey) }

            let issue: String?
            let status: IntelligenceStatus
            if hidden {
                issue = "Interactive element is hidden from screen-reader users."
                status = .fail
            } else if nameIssue || trimmedLabel.isEmpty {
                issue = "Accessible name may be missing or incomplete."
                status = .fail
            } else if roleIssue {
                issue = "Role or state information may not be announced correctly."
                status = .fail
            } else if duplicate {
                issue = "Repeated accessible name may make this focus stop ambiguous."
                status = .warning
            } else if focusValidation {
                issue = "Focus order requires manual validation."
                status = .validate
            } else {
                issue = nil
                status = .pass
            }

            stops.append(
                VoiceOverFocusStop(
                    id: UUID(),
                    position: index + 1,
                    elementType: evaluation.elementType,
                    label: trimmedLabel,
                    identifier: evaluation.identifier,
                    frameX: evaluation.frameX,
                    frameY: evaluation.frameY,
                    frameWidth: evaluation.frameWidth,
                    frameHeight: evaluation.frameHeight,
                    status: status,
                    issue: issue
                )
            )
        }

        let issueCount = stops.filter { $0.status == .fail || $0.status == .warning }.count
        let validationCount = stops.filter { $0.status == .validate }.count

        return VoiceOverJourneyScreen(
            id: UUID(),
            screenName: screen.name,
            screenSignature: screen.signature,
            focusStops: stops,
            issueCount: issueCount,
            validationCount: validationCount
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

    // MARK: Accessibility Diff

    private static func analyzeAccessibilityDiff(
        _ report: AccessibilityScanResult,
        baseline: AccessibilityRegressionSnapshot?
    ) -> AccessibilityDiffResult {
        guard let baseline else { return .notTested }

        let current = AccessibilityRegressionSnapshot(report: report)
        let newKeys = current.issueKeys.subtracting(baseline.issueKeys)
        let fixedKeys = baseline.issueKeys.subtracting(current.issueKeys)

        let newIssues = newKeys.sorted().compactMap { key -> AccessibilityDiffIssue? in
            guard let issue = current.issueDetails[key] else { return nil }
            return AccessibilityDiffIssue(id: "new|\(key)", change: "New", issue: issue)
        }

        let fixedIssues = fixedKeys.sorted().compactMap { key -> AccessibilityDiffIssue? in
            guard let issue = baseline.issueDetails[key] else { return nil }
            return AccessibilityDiffIssue(id: "fixed|\(key)", change: "Fixed", issue: issue)
        }

        let addedScreens = current.screenSignatures.subtracting(baseline.screenSignatures)
            .sorted().map { signature in
                AccessibilityDiffScreenChange(
                    id: "added|\(signature)",
                    change: "Added",
                    screenName: current.screenNames[signature] ?? signature,
                    signature: signature
                )
            }

        let removedScreens = baseline.screenSignatures.subtracting(current.screenSignatures)
            .sorted().map { signature in
                AccessibilityDiffScreenChange(
                    id: "removed|\(signature)",
                    change: "Removed",
                    screenName: baseline.screenNames[signature] ?? signature,
                    signature: signature
                )
            }

        return AccessibilityDiffResult(
            hasBaseline: true,
            newIssues: newIssues,
            fixedIssues: fixedIssues,
            addedScreens: addedScreens,
            removedScreens: removedScreens
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

// MARK: - Quality Gate UI

struct AccessibilityQualityGateView: View {
    let gate: AccessibilityQualityGateResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accessibility Quality Gate")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Release checks based on the current scan, regression baseline and discovered journeys.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                gateBadge(gate.status)
            }

            HStack(spacing: 12) {
                gateMetric(
                    title: "Gate",
                    value: gate.status.title
                )
                gateMetric(
                    title: "Blocking",
                    value: "\(gate.enforcedFailureCount)"
                )
                gateMetric(
                    title: "Checks",
                    value: "\(gate.checks.count)"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(gate.checks) { check in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: check.enforced && !check.passed ? "xmark.circle.fill" : check.passed ? "checkmark.circle.fill" : "info.circle.fill")
                            .foregroundStyle(check.enforced && !check.passed ? .red : check.passed ? .green : .secondary)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(check.title)
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                if check.enforced {
                                    Text("ENFORCED")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.secondary.opacity(0.10))
                                        .clipShape(Capsule())
                                } else {
                                    Text("REPORT ONLY")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.secondary.opacity(0.10))
                                        .clipShape(Capsule())
                                }
                                Spacer()
                                Text("\(check.value)")
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                            }

                            Text(check.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(11)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.055)))
                }
            }

            Text("A PASS means no enforced gate condition failed. A VALIDATE result means the scan needs a baseline or deeper runtime validation before a release decision can be made.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.secondary.opacity(0.10))
                )
        )
    }

    private func gateMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func gateBadge(_ status: IntelligenceStatus) -> some View {
        Text(status.title.uppercased())
            .font(.caption)
            .fontWeight(.bold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(gateColor(status).opacity(0.12))
            .foregroundStyle(gateColor(status))
            .clipShape(Capsule())
    }

    private func gateColor(_ status: IntelligenceStatus) -> Color {
        switch status {
        case .pass: return .green
        case .fail: return .red
        case .warning: return .orange
        case .validate: return .yellow
        case .notTested: return .gray
        }
    }
}

// MARK: - Intelligence UI

struct AccessibilityIntelligenceView: View {
    let intelligence: AccessibilityIntelligence

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            engineGrid
            responsiveSection
            voiceOverJourneySection
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

    private var responsiveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Responsive Accessibility")
                        .font(.headline)
                    Text("Runtime orientation smoke test plus Dynamic Type coverage from the accessibility rules.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge(intelligence.responsive.status)
            }

            HStack(spacing: 20) {
                metric("Landscape elements", intelligence.responsive.landscapeElementCount)
                metric("Landscape failures", intelligence.responsive.landscapeFailureCount)
                metric("Landscape warnings", intelligence.responsive.landscapeWarningCount)
                metric("Text-size checks", intelligence.responsive.dynamicTypeValidationCount + intelligence.responsive.dynamicTypeFailureCount)
            }

            if intelligence.responsive.tested {
                HStack(spacing: 10) {
                    Label(
                        intelligence.responsive.landscapeScreenshotCaptured ? "Landscape captured" : "Landscape not captured",
                        systemImage: intelligence.responsive.landscapeScreenshotCaptured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    if let original = intelligence.responsive.originalOrientation {
                        Text("Original: \(original)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(intelligence.responsive.note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }

    private var voiceOverJourneySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("VoiceOver Navigation")
                        .font(.headline)
                    Text("Inferred focus sequence from the scanned accessibility hierarchy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge(intelligence.voiceOver.status)
            }

            HStack(spacing: 20) {
                metric("Focus stops", intelligence.voiceOver.focusStopsObserved)
                metric("Screens", intelligence.voiceOver.screensWithFocusSequences)
                metric("Screens with issues", intelligence.voiceOver.screensWithFocusIssues)
            }

            Text("This is a hierarchy-based navigation model. It does not claim to drive the VoiceOver runtime.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if intelligence.voiceOver.focusSequences.isEmpty {
                Text("No focusable elements were available to build a navigation sequence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(intelligence.voiceOver.focusSequences) { screen in
                        DisclosureGroup {
                            LazyVStack(alignment: .leading, spacing: 5) {
                                ForEach(screen.focusStops) { stop in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(stop.position)")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .frame(width: 24, height: 24)
                                            .background(Circle().fill(Color.secondary.opacity(0.12)))

                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(stop.displayName)
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .lineLimit(2)
                                                statusBadge(stop.status)
                                            }
                                            Text(stop.elementType)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            if let issue = stop.issue {
                                                Text(issue)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            HStack {
                                statusDot(screen.status)
                                Text(screen.screenName)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("\(screen.focusStops.count) stops")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if screen.issueCount > 0 {
                                    Text("\(screen.issueCount) issues")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
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
