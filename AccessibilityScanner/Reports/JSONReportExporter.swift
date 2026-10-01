//
//  JSONReportExporter.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 29/09/26.

import Foundation

struct JSONReportExporter {

    enum ExportError: LocalizedError {
        case couldNotCreateFile

        var errorDescription: String? {
            switch self {
            case .couldNotCreateFile:
                return "The accessibility JSON report could not be created."
            }
        }
    }

    func makeJSONData(from report: AccessibilityScanResult) throws -> Data {
        let payload = JSONReportPayload(report: report)

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

private struct JSONReportPayload: Codable {

    let schemaVersion: String
    let scan: JSONScanMetadata
    let summary: JSONSummary
    let screens: [JSONScreen]
    let rules: [JSONRuleSummary]
    let intelligence: AccessibilityIntelligence?

    init(report: AccessibilityScanResult) {
        self.schemaVersion = "1.2"
        self.scan = JSONScanMetadata(report: report)
        self.summary = JSONSummary(report: report)
        self.screens = report.screens.map(JSONScreen.init)
        self.rules = report.ruleSummaries.map(JSONRuleSummary.init)
        self.intelligence = report.intelligence
    }
}

private struct JSONScanMetadata: Codable {
    let applicationName: String
    let bundleID: String
    let deviceName: String
    let deviceUDID: String
    let startedAt: Date
    let finishedAt: Date
    let durationSeconds: Double
    let screensScanned: Int
    let rulesExecuted: Int

    init(report: AccessibilityScanResult) {
        self.applicationName = report.applicationName
        self.bundleID = report.bundleID
        self.deviceName = report.deviceName
        self.deviceUDID = report.deviceUDID
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

private struct JSONSummary: Codable {
    let totalElementsTested: Int
    let totalEvaluations: Int
    let totalFailures: Int
    let totalWarnings: Int
    let totalValidations: Int
    let totalPasses: Int
    let totalIssues: Int
    let overallStatus: String

    init(report: AccessibilityScanResult) {
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

private struct JSONScreen: Codable {
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
    let evaluations: [JSONEvaluation]
    let transitions: [JSONTransition]

    init(screen: ScreenScanResult) {
        self.id = screen.id
        self.name = screen.name
        self.signature = screen.signature
        self.elementCount = screen.elementCount
        self.failures = screen.failures
        self.warnings = screen.warnings
        self.validations = screen.validations
        self.passes = screen.passes
        self.affectedElements = screen.affectedElements
        self.screenshot = screen.screenshot.map(JSONScreenshot.init)
        self.annotations = screen.annotations.map(JSONAnnotation.init)
        self.evaluations = screen.evaluations.map(JSONEvaluation.init)
        self.transitions = screen.transitions.map(JSONTransition.init)
    }
}


private struct JSONTransition: Codable {
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

private struct JSONScreenshot: Codable {
    let width: Double
    let height: Double
    let hierarchyWidth: Double
    let hierarchyHeight: Double
    let hasOriginalImage: Bool
    let hasAnnotatedImage: Bool

    init(screenshot: ScanScreenshot) {
        self.width = screenshot.width
        self.height = screenshot.height
        self.hierarchyWidth = screenshot.hierarchyWidth
        self.hierarchyHeight = screenshot.hierarchyHeight
        self.hasOriginalImage = !screenshot.imageData.isEmpty
        self.hasAnnotatedImage = screenshot.annotatedImageData != nil
    }
}

private struct JSONAnnotation: Codable {
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

private struct JSONEvaluation: Codable {
    let id: UUID
    let ruleID: String
    let ruleName: String
    let ruleDescription: String
    let status: String
    let severity: String
    let message: String
    let remediation: String
    let element: JSONElement

    init(evaluation: AccessibilityRuleEvaluation) {
        self.id = evaluation.id
        self.ruleID = evaluation.ruleID
        self.ruleName = evaluation.ruleName
        self.ruleDescription = evaluation.ruleDescription
        self.status = evaluation.status.rawValue
        self.severity = evaluation.severity.rawValue
        self.message = evaluation.message
        self.remediation = evaluation.remediation
        self.element = JSONElement(evaluation: evaluation)
    }
}

private struct JSONElement: Codable {
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

private struct JSONFrame: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

private struct JSONRuleSummary: Codable {
    let ruleID: String
    let ruleName: String
    let severity: String
    let total: Int
    let pass: Int
    let fail: Int
    let warning: Int
    let validate: Int

    init(summary: RuleSummary) {
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
