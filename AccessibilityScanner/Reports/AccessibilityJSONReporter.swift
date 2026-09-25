//
//  AccessibilityJSONReporter.swift
//  AccessibilityScannerDemo
//
//  Created by Ravish Kumar on 21/09/26.
//

import Foundation

struct AccessibilityJSONReporter {

    static func generateReport(
        findings: [AccessibilityFinding]
    ) -> String {

        let report = JSONReport(
            summary: Summary(
                totalViolations: findings.count,
                errors: findings.filter {
                    $0.severity == .error
                }.count,
                warnings: findings.filter {
                    $0.severity == .warning
                }.count,
                info: findings.filter {
                    $0.severity == .info
                }.count
            ),
            violations: findings.map {
                JSONViolation(
                    ruleID: $0.ruleID,
                    severity: $0.severity.rawValue,
                    message: $0.message,
                    element: JSONElement(
                        type: String(describing: $0.elementType),
                        label: $0.elementLabel,
                        identifier: $0.identifier,
                        value: $0.value,
                        frame: JSONFrame(
                            x: $0.frame.origin.x,
                            y: $0.frame.origin.y,
                            width: $0.frame.size.width,
                            height: $0.frame.size.height
                        )
                    ),
                    remediation: $0.remediation
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]

        do {
            let data = try encoder.encode(report)

            return String(
                data: data,
                encoding: .utf8
            ) ?? "{}"

        } catch {
            return """
            {
                "error": "Unable to generate JSON report",
                "message": "\(error)"
            }
            """
        }
    }
}

// MARK: - JSON Models

private struct JSONReport: Codable {

    let summary: Summary

    let violations: [JSONViolation]
}

private struct Summary: Codable {

    let totalViolations: Int

    let errors: Int

    let warnings: Int

    let info: Int
}

private struct JSONViolation: Codable {

    let ruleID: String

    let severity: String

    let message: String

    let element: JSONElement

    let remediation: String
}

private struct JSONElement: Codable {

    let type: String

    let label: String

    let identifier: String

    let value: String?

    let frame: JSONFrame
}

private struct JSONFrame: Codable {

    let x: Double

    let y: Double

    let width: Double

    let height: Double
}
