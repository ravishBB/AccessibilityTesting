//
//  JSONReportExporter.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 29/09/26.

import Foundation

nonisolated struct JSONReportExporter {

    enum ExportError: LocalizedError {
        case couldNotCreateFile

        var errorDescription: String? {
            switch self {
            case .couldNotCreateFile:
                return "The accessibility JSON report could not be created."
            }
        }
    }

    struct Options {
        var includeScreenshots = true
        var maxScreenshotPixelSize = 900
        var includeOriginalWhenAnnotated = false
    }

    var options = Options()

    func makeJSONData(from report: AccessibilityScanResult) throws -> Data {
        let payload = JSONReportPayload(report: report, options: options)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes
        ]
        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(payload)
    }

    func writeJSONFile(from report: AccessibilityScanResult) throws -> URL {
        let data = try makeJSONData(from: report)

        let fileName = sanitizedFileName(report.applicationName)
            + "_AccessibilityReport_"
            + timestampString(report.finishedAt)
            + ".json"

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccessibilityScanner", isDirectory: true)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let url = directory.appendingPathComponent(fileName)

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw ExportError.couldNotCreateFile
        }
    }

    private func sanitizedFileName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(
            charactersIn: "/\\:?%*|\"<>"
        )

        let cleaned = value
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? "AccessibilityScan" : cleaned
    }

    private func timestampString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

// MARK: - JSON Payload

private nonisolated struct JSONReportPayload: Codable {

    let schemaVersion: String
    let reportID: UUID
    let generator: JSONGenerator
    let scan: JSONScanMetadata
    let summary: JSONSummary
    let findings: [JSONGroupedFinding]
    let screens: [JSONScreen]
    let rules: [JSONRuleSummary]
    /// Per-rule outcomes and the full WCAG A/AA coverage matrix (schema 1.5).
    let coverage: ReportCoverage
    /// Every BB ID in the ruleset and what this scan did with it (schema 1.7).
    let bbCoverage: [BBCoverageEntry]
    let intelligence: AccessibilityIntelligence?

    init(report: AccessibilityScanResult, options: JSONReportExporter.Options) {
        let grouping = FindingGrouping(report: report)

        // 1.4 is additive over 1.3: generator, reportID, findings, per-evaluation
        // fingerprint/wcag/impact, rule metadata and embedded screenshots.
        // 1.5 is additive over 1.4: coverage block and summary.uniquePasses.
        // 1.6: scan.environment, scan.scanNotes, generator.bbMappingVersion,
        // BB issue IDs on findings and evaluations; scan.deviceUDID removed.
        // 1.7: bbCoverage (every BB ruleset row with its result on this scan).
        self.schemaVersion = "1.8"
        self.reportID = report.id
        self.generator = JSONGenerator()
        self.scan = JSONScanMetadata(report: report)
        self.summary = JSONSummary(report: report, grouping: grouping)
        self.findings = grouping.groups.map { JSONGroupedFinding(group: $0) }
        self.screens = report.screens.map {
            JSONScreen(screen: $0, grouping: grouping, options: options)
        }
        self.rules = report.ruleSummaries.map { JSONRuleSummary(summary: $0) }
        self.coverage = ReportCoverage(report: report, grouping: grouping)
        self.bbCoverage = BBCoverage.entries(for: report)
        // Quality gate, VoiceOver, journey and regression analysis are not
        // part of the report.
        self.intelligence = nil
    }
}

private nonisolated struct JSONGenerator: Codable {
    let name: String
    let version: String
    let build: String
    let ruleSetVersion: String
    let bbMappingVersion: String
    let standard: String
    let catalogRuleCount: Int

    init() {
        self.name = ScannerBuildInfo.productName
        self.version = ScannerBuildInfo.version
        self.build = ScannerBuildInfo.build
        self.ruleSetVersion = ScannerBuildInfo.ruleSetVersion
        self.bbMappingVersion = BBIssueCatalog.version
        self.standard = ScannerBuildInfo.wcagVersion
        self.catalogRuleCount = AccessibilityRuleCatalog.ruleCount
    }
}

private nonisolated struct JSONWCAG: Codable {
    let criterion: String
    let title: String?
    let level: String?

    init?(metadata: AccessibilityRuleMetadata) {
        guard let criterion = metadata.wcagCriterion else { return nil }
        self.criterion = criterion
        self.title = metadata.wcagTitle
        self.level = metadata.wcagLevel
    }
}

private nonisolated struct JSONGroupedFinding: Codable {
    let id: String
    let ruleID: String
    let ruleName: String
    let bbIssueID: String?
    let bbIssueTitle: String?
    /// WCAG criterion of the BB issue, from the BB sheet.
    let bbIssueWCAG: String?
    /// Validate only: the Fail code to log if the tester confirms it.
    let bbIfConfirmedID: String?
    let bbIfConfirmedTitle: String?
    let status: String
    let severity: String
    let impact: String
    let wcag: JSONWCAG?
    let affectedUsers: String
    let howToTest: String
    let remediation: String
    let elementCount: Int
    let screenCount: Int
    let fingerprints: [String]

    init(group: GroupedFinding) {
        self.id = group.id
        self.ruleID = group.ruleID
        self.ruleName = group.ruleName
        self.bbIssueID = group.bbIssue?.id
        self.bbIssueTitle = group.bbIssue?.title
        self.bbIssueWCAG = group.bbIssue?.wcag
        self.bbIfConfirmedID = group.bbIfConfirmed?.id
        self.bbIfConfirmedTitle = group.bbIfConfirmed?.title
        self.status = group.status.rawValue
        self.severity = group.severity.rawValue
        self.impact = group.metadata.impact.rawValue
        self.wcag = JSONWCAG(metadata: group.metadata)
        self.affectedUsers = group.metadata.affectedUsers
        self.howToTest = group.metadata.howToTest
        self.remediation = group.remediation
        self.elementCount = group.count
        self.screenCount = group.screenCount
        self.fingerprints = group.occurrences.map(\.fingerprint)
    }
}

private nonisolated struct JSONScanMetadata: Codable {
    let applicationName: String
    let bundleID: String
    let deviceName: String
    // The device UDID is a hardware identifier and is not included in a
    // report that goes to clients.
    let environment: ScanEnvironment?
    /// What the scan could not do (failed taps, lost navigation, moving screens).
    let scanNotes: [String]
    let startedAt: Date
    let finishedAt: Date
    let durationSeconds: Double
    let screensScanned: Int
    /// Rules attempted on this scan. Not every rule produces a result; see
    /// `coverage` for how many gave automated verdicts.
    let rulesExecuted: Int

    init(report: AccessibilityScanResult) {
        self.applicationName = report.applicationName
        self.bundleID = report.bundleID
        self.deviceName = report.deviceName
        self.environment = report.environment
        self.scanNotes = report.scanNotes ?? []
        self.startedAt = report.startedAt
        self.finishedAt = report.finishedAt
        self.durationSeconds = max(
            0,
            report.finishedAt.timeIntervalSince(report.startedAt)
        )
        self.screensScanned = report.screens.count
        self.rulesExecuted = report.rulesExecuted
    }
}

private nonisolated struct JSONSummary: Codable {
    let totalElementsTested: Int
    let totalEvaluations: Int
    let totalFailures: Int
    let totalWarnings: Int
    let totalValidations: Int
    let totalPasses: Int
    let totalIssues: Int
    let overallStatus: String
    /// Unique affected elements (duplicates merged), as shown in the report.
    let uniqueFailures: Int
    let uniqueWarnings: Int
    let uniqueManualReview: Int
    /// Passed results in the same unit as the unique counts above.
    let uniquePasses: Int

    init(report: AccessibilityScanResult, grouping: FindingGrouping) {
        self.uniquePasses = grouping.passCount
        self.uniqueFailures = grouping.failureCount
        self.uniqueWarnings = grouping.warningCount
        self.uniqueManualReview = grouping.manualReviewCount
        self.totalElementsTested = report.totalElementsTested
        self.totalEvaluations = report.allEvaluations.count
        self.totalFailures = report.totalFailures
        self.totalWarnings = report.totalWarnings
        self.totalValidations = report.totalValidations
        self.totalPasses = report.totalPasses
        self.totalIssues = report.totalIssues
        self.overallStatus = report.overallStatus.rawValue
    }
}

private nonisolated struct JSONScreen: Codable {
    let id: UUID
    let name: String
    let signature: String
    let elementCount: Int
    let failures: Int
    let warnings: Int
    let validations: Int
    let passes: Int
    let affectedElements: Int
    let screenshot: JSONScreenshot?
    let annotations: [JSONAnnotation]
    let viewportScreenshots: [JSONViewportScreenshot]
    let evaluations: [JSONEvaluation]
    let transitions: [JSONTransition]

    init(
        screen: ScreenScanResult,
        grouping: FindingGrouping,
        options: JSONReportExporter.Options
    ) {
        self.id = screen.id
        self.name = screen.name
        self.signature = screen.signature
        self.elementCount = screen.elementCount
        self.failures = screen.failures
        self.warnings = screen.warnings
        self.validations = screen.validations
        self.passes = screen.passes
        self.affectedElements = screen.affectedElements
        // The screen screenshot is also the first viewport: embed its image
        // bytes only once, in the viewport list.
        self.screenshot = screen.screenshot.map {
            JSONScreenshot(screenshot: $0, options: options, embedImages: screen.viewportScreenshots.isEmpty)
        }
        self.annotations = screen.annotations.map { JSONAnnotation(annotation: $0) }
        self.viewportScreenshots = screen.viewportScreenshots.map {
            JSONViewportScreenshot(viewport: $0, options: options)
        }
        self.evaluations = screen.evaluations.map {
            JSONEvaluation(
                evaluation: $0,
                fingerprint: grouping.fingerprintByEvaluationID[$0.id]
            )
        }
        self.transitions = screen.transitions.map { JSONTransition(transition: $0) }
    }
}


private nonisolated struct JSONViewportScreenshot: Codable {
    let id: UUID
    let index: Int
    let screenshot: JSONScreenshot
    let annotations: [JSONAnnotation]

    init(viewport: ScreenshotViewport, options: JSONReportExporter.Options) {
        self.id = viewport.id
        self.index = viewport.index
        self.screenshot = JSONScreenshot(screenshot: viewport.screenshot, options: options)
        self.annotations = viewport.annotations.map { JSONAnnotation(annotation: $0) }
    }
}

private nonisolated struct JSONTransition: Codable {
    let id: UUID
    let targetSignature: String
    let actionID: String
    let actionLabel: String
    let actionIdentifier: String
    let actionType: String
    let frame: JSONFrame
    let xpath: String?

    init(transition: NavigationTransition) {
        self.id = transition.id
        self.targetSignature = transition.targetSignature
        self.actionID = transition.actionID
        self.actionLabel = transition.actionLabel
        self.actionIdentifier = transition.actionIdentifier
        self.actionType = transition.actionType
        self.frame = JSONFrame(
            x: transition.actionFrameX,
            y: transition.actionFrameY,
            width: transition.actionFrameWidth,
            height: transition.actionFrameHeight
        )
        self.xpath = transition.xpath
    }
}

private nonisolated struct JSONScreenshot: Codable {
    let width: Double
    let height: Double
    let hierarchyWidth: Double
    let hierarchyHeight: Double
    let hasOriginalImage: Bool
    let hasAnnotatedImage: Bool
    /// Present when screenshots are embedded. JPEG, longest side capped by the export options.
    let imageMimeType: String?
    let imageBase64: String?
    let annotatedImageBase64: String?

    init(screenshot: ScanScreenshot, options: JSONReportExporter.Options, embedImages: Bool = true) {
        if options.includeScreenshots && embedImages {
            let annotated = screenshot.annotatedImageData.flatMap {
                ReportImageEncoder.encode($0, maxPixelSize: options.maxScreenshotPixelSize)
            }
            let original = (annotated == nil || options.includeOriginalWhenAnnotated)
                ? ReportImageEncoder.encode(screenshot.imageData, maxPixelSize: options.maxScreenshotPixelSize)
                : nil
            self.imageMimeType = original?.mimeType ?? annotated?.mimeType
            self.imageBase64 = original?.base64
            self.annotatedImageBase64 = annotated?.base64
        } else {
            self.imageMimeType = nil
            self.imageBase64 = nil
            self.annotatedImageBase64 = nil
        }

        self.width = screenshot.width
        self.height = screenshot.height
        self.hierarchyWidth = screenshot.hierarchyWidth
        self.hierarchyHeight = screenshot.hierarchyHeight
        self.hasOriginalImage = !screenshot.imageData.isEmpty
        self.hasAnnotatedImage = screenshot.annotatedImageData != nil
    }
}

private nonisolated struct JSONAnnotation: Codable {
    let id: UUID
    let number: Int
    let ruleID: String
    let ruleName: String
    let severity: String
    let message: String
    let remediation: String
    let elementType: String
    let elementLabel: String
    let frame: JSONFrame

    init(annotation: ScreenshotAnnotation) {
        self.id = annotation.id
        self.number = annotation.number
        self.ruleID = annotation.ruleID
        self.ruleName = annotation.ruleName
        self.severity = annotation.severity.rawValue
        self.message = annotation.message
        self.remediation = annotation.remediation
        self.elementType = annotation.elementType
        self.elementLabel = annotation.elementLabel
        self.frame = JSONFrame(
            x: annotation.frameX,
            y: annotation.frameY,
            width: annotation.frameWidth,
            height: annotation.frameHeight
        )
    }
}

private nonisolated struct JSONEvaluation: Codable {
    let id: UUID
    let ruleID: String
    let ruleName: String
    let ruleDescription: String
    let bbIssueID: String?
    let bbIfConfirmedID: String?
    let status: String
    let severity: String
    let message: String
    let remediation: String
    let element: JSONElement
    /// Stable ID for non-pass results; nil for passes.
    let fingerprint: String?
    let impact: String
    let wcag: JSONWCAG?

    init(evaluation: AccessibilityRuleEvaluation, fingerprint: String?) {
        let metadata = AccessibilityRuleCatalog.metadata(for: evaluation.ruleID)
        self.fingerprint = fingerprint
        self.impact = metadata.impact.rawValue
        self.wcag = JSONWCAG(metadata: metadata)
        self.id = evaluation.id
        self.ruleID = evaluation.ruleID
        self.ruleName = evaluation.ruleName
        self.ruleDescription = evaluation.ruleDescription
        self.bbIssueID = BBIssueCatalog.issue(for: evaluation)?.id
        self.bbIfConfirmedID = BBIssueCatalog.ifConfirmed(for: evaluation)?.id
        self.status = evaluation.status.rawValue
        self.severity = evaluation.severity.rawValue
        self.message = evaluation.message
        self.remediation = evaluation.remediation
        self.element = JSONElement(evaluation: evaluation)
    }
}

private nonisolated struct JSONElement: Codable {
    let type: String
    let identifier: String
    let label: String
    let value: String?
    let frame: JSONFrame

    init(evaluation: AccessibilityRuleEvaluation) {
        self.type = evaluation.elementType
        self.identifier = evaluation.identifier
        self.label = evaluation.elementLabel
        self.value = evaluation.value
        self.frame = JSONFrame(
            x: evaluation.frameX,
            y: evaluation.frameY,
            width: evaluation.frameWidth,
            height: evaluation.frameHeight
        )
    }
}

private nonisolated struct JSONFrame: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

private nonisolated struct JSONRuleSummary: Codable {
    let ruleID: String
    let ruleName: String
    let severity: String
    let total: Int
    let pass: Int
    let fail: Int
    let warning: Int
    let validate: Int
    let impact: String
    let wcag: JSONWCAG?
    let affectedUsers: String
    let howToTest: String

    init(summary: RuleSummary) {
        let metadata = AccessibilityRuleCatalog.metadata(for: summary.ruleID)
        self.impact = metadata.impact.rawValue
        self.wcag = JSONWCAG(metadata: metadata)
        self.affectedUsers = metadata.affectedUsers
        self.howToTest = metadata.howToTest
        self.ruleID = summary.ruleID
        self.ruleName = summary.ruleName
        self.severity = summary.severity.rawValue
        self.total = summary.totalEvaluations
        self.pass = summary.passes
        self.fail = summary.failures
        self.warning = summary.warnings
        self.validate = summary.validations
    }
}
