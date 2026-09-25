//
//  ScanReportView.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 24/09/26.
//

import SwiftUI
import AppKit

struct ScanReportView: View {

    let report: AccessibilityScanResult

    var body: some View {

        ScrollView {

            VStack(
                alignment: .leading,
                spacing: 24
            ) {

                header

                summarySection

                screenshotSection

                screenResultsSection

                ruleResultsSection

                issuesSection

                passesSection

                ruleSummarySection
            }
            .padding(24)
        }
        .background(
            Color(nsColor: .windowBackgroundColor)
        )
        .navigationTitle("Accessibility Report")
    }

    // MARK: - Header

    private var header: some View {

        VStack(
            alignment: .leading,
            spacing: 8
        ) {

            HStack {

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {

                    Text("Accessibility Scan Report")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(report.applicationName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge(
                    report.overallStatus
                )
            }

            Divider()

            HStack(spacing: 24) {

                metadata(
                    title: "Bundle ID",
                    value: report.bundleID
                )

                metadata(
                    title: "Device",
                    value: report.deviceName
                )

                metadata(
                    title: "UDID",
                    value: report.deviceUDID
                )

                metadata(
                    title: "Started",
                    value: report.startedAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
            }
        }
    }

    // MARK: - Summary

    private var summarySection: some View {

        VStack(
            alignment: .leading,
            spacing: 16
        ) {

            sectionTitle("Global Summary")

            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: 12
            ) {

                summaryCard(
                    title: "Screens",
                    value: report.screens.count
                )

                summaryCard(
                    title: "Elements Tested",
                    value: report.totalElementsTested
                )

                summaryCard(
                    title: "Rules Executed",
                    value: report.rulesExecuted
                )

                summaryCard(
                    title: "Failures",
                    value: report.totalFailures
                )

                summaryCard(
                    title: "Warnings",
                    value: report.totalWarnings
                )

                summaryCard(
                    title: "Validate",
                    value: report.totalValidations
                )

                summaryCard(
                    title: "Passed",
                    value: report.totalPasses
                )

                summaryCard(
                    title: "Issues",
                    value: report.totalIssues
                )
            }
        }
    }

    // MARK: - Screenshot

    private var screenshotSection: some View {

        VStack(
            alignment: .leading,
            spacing: 16
        ) {

            sectionTitle("Accessibility Screenshot")

            ForEach(report.screens) { screen in

                screenshotCard(
                    screen: screen
                )
            }
        }
    }

    // MARK: - Screenshot Card

    private func screenshotCard(
        screen: ScreenScanResult
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 16
        ) {

            HStack {

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {

                    Text(screen.name)
                        .font(.headline)

                    Text(
                        "\(screen.annotations.count) annotated issue(s)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let screenshot = screen.screenshot {

                if let annotatedData =
                    screenshot.annotatedImageData,
                   let annotatedImage =
                    NSImage(data: annotatedData) {

                    Image(
                        nsImage: annotatedImage
                    )
                    .resizable()
                    .aspectRatio(
                        contentMode: .fit
                    )
                    .frame(
                        maxWidth: 500
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 12
                        )
                    )
                    .shadow(
                        radius: 6
                    )

                } else if let rawImage =
                            NSImage(
                                data: screenshot.imageData
                            ) {

                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {

                        Text(
                            "Annotated image unavailable — showing captured screenshot."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Image(
                            nsImage: rawImage
                        )
                        .resizable()
                        .aspectRatio(
                            contentMode: .fit
                        )
                        .frame(
                            maxWidth: 500
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 12
                            )
                        )
                    }

                } else {

                    Text(
                        "Screenshot data could not be displayed."
                    )
                    .foregroundStyle(.secondary)
                }

            } else {

                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {

                    Image(
                        systemName: "camera.slash"
                    )
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)

                    Text(
                        "No screenshot was captured for this screen."
                    )
                    .foregroundStyle(.secondary)
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .center
                )
                .padding(40)
            }

            if !screen.annotations.isEmpty {

                Divider()

                Text("Annotated Issues")
                    .font(.headline)

                VStack(
                    alignment: .leading,
                    spacing: 10
                ) {

                    ForEach(
                        screen.annotations
                    ) { annotation in

                        annotationRow(
                            annotation
                        )
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(
                cornerRadius: 12
            )
            .fill(
                Color.secondary.opacity(0.06)
            )
        )
    }

    // MARK: - Annotation Row

    private func annotationRow(
        _ annotation: ScreenshotAnnotation
    ) -> some View {

        HStack(
            alignment: .top,
            spacing: 12
        ) {

            Text(
                "\(annotation.number)"
            )
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .frame(
                width: 24,
                height: 24
            )
            .background(
                annotationColor(
                    annotation.severity
                )
            )
            .clipShape(
                Circle()
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {

                HStack {

                    Text(annotation.ruleName)
                        .font(.callout)
                        .fontWeight(.semibold)

                    severityBadge(
                        annotation.severity
                    )
                }

                if !annotation.elementLabel.isEmpty {

                    Text(
                        "\(annotation.elementType) — \(annotation.elementLabel)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                } else {

                    Text(
                        annotation.elementType
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text(
                    annotation.message
                )
                .font(.caption)

                Text(
                    String(
                        format:
                            "Frame: %.0f, %.0f — %.0f × %.0f",
                        annotation.frameX,
                        annotation.frameY,
                        annotation.frameWidth,
                        annotation.frameHeight
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Screens

    private var screenResultsSection: some View {

        VStack(
            alignment: .leading,
            spacing: 16
        ) {

            sectionTitle("Per-Screen Results")

            ForEach(
                report.screens
            ) { screen in

                VStack(
                    alignment: .leading,
                    spacing: 14
                ) {

                    HStack {

                        Text(screen.name)
                            .font(.headline)

                        Spacer()

                        Text(
                            "\(screen.elementCount) elements"
                        )
                        .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {

                        resultPill(
                            title: "FAIL",
                            value: screen.failures
                        )

                        resultPill(
                            title: "WARNING",
                            value: screen.warnings
                        )

                        resultPill(
                            title: "VALIDATE",
                            value: screen.validations
                        )

                        resultPill(
                            title: "PASS",
                            value: screen.passes
                        )
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(
                        cornerRadius: 12
                    )
                    .fill(
                        Color.secondary.opacity(0.08)
                    )
                )
            }
        }
    }

    // MARK: - Rule Results

    private var ruleResultsSection: some View {

        VStack(
            alignment: .leading,
            spacing: 16
        ) {

            sectionTitle("Rule-wise Results")

            ForEach(
                report.ruleSummaries
            ) { rule in

                VStack(
                    alignment: .leading,
                    spacing: 10
                ) {

                    HStack {

                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {

                            Text(rule.ruleName)
                                .font(.headline)

                            Text(rule.ruleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        severityBadge(
                            rule.severity
                        )
                    }

                    HStack(spacing: 18) {

                        metric(
                            "Failures",
                            rule.failures
                        )

                        metric(
                            "Warnings",
                            rule.warnings
                        )

                        metric(
                            "Validate",
                            rule.validations
                        )

                        metric(
                            "Pass",
                            rule.passes
                        )
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(
                        cornerRadius: 10
                    )
                    .stroke(
                        Color.secondary.opacity(0.2)
                    )
                )
            }
        }
    }

    // MARK: - Issues

    private var issuesSection: some View {

        VStack(
            alignment: .leading,
            spacing: 16
        ) {

            sectionTitle("Complete Issue List")

            if report.issueEvaluations.isEmpty {

                emptyState(
                    "No accessibility issues were detected."
                )

            } else {

                ForEach(
                    report.issueEvaluations
                ) { evaluation in

                    evaluationCard(
                        evaluation
                    )
                }
            }
        }
    }

    // MARK: - Passes

    private var passesSection: some View {

        VStack(
            alignment: .leading,
            spacing: 16
        ) {

            sectionTitle("Complete Pass List")

            if report.passEvaluations.isEmpty {

                emptyState(
                    "No passing evaluations were recorded."
                )

            } else {

                ForEach(
                    report.passEvaluations
                ) { evaluation in

                    evaluationCard(
                        evaluation
                    )
                }
            }
        }
    }

    // MARK: - Rule Summary

    private var ruleSummarySection: some View {

        VStack(
            alignment: .leading,
            spacing: 16
        ) {

            sectionTitle("Rule Summary")

            VStack(spacing: 0) {

                HStack {

                    tableHeader("Rule")

                    tableHeader("Failures")

                    tableHeader("Warnings")

                    tableHeader("Validate")

                    tableHeader("Pass")
                }
                .padding(12)

                Divider()

                ForEach(
                    report.ruleSummaries
                ) { rule in

                    HStack {

                        Text(rule.ruleName)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )

                        Text(
                            "\(rule.failures)"
                        )
                        .frame(
                            width: 70,
                            alignment: .center
                        )

                        Text(
                            "\(rule.warnings)"
                        )
                        .frame(
                            width: 70,
                            alignment: .center
                        )

                        Text(
                            "\(rule.validations)"
                        )
                        .frame(
                            width: 70,
                            alignment: .center
                        )

                        Text(
                            "\(rule.passes)"
                        )
                        .frame(
                            width: 70,
                            alignment: .center
                        )
                    }
                    .padding(12)

                    Divider()
                }
            }
            .background(
                RoundedRectangle(
                    cornerRadius: 10
                )
                .stroke(
                    Color.secondary.opacity(0.2)
                )
            )
        }
    }

    // MARK: - Evaluation Card

    private func evaluationCard(
        _ evaluation: AccessibilityRuleEvaluation
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 10
        ) {

            HStack {

                statusBadge(
                    evaluation.status
                )

                Text(
                    evaluation.ruleName
                )
                .font(.headline)

                Spacer()

                severityBadge(
                    evaluation.severity
                )
            }

            Text(
                evaluation.message
            )
            .font(.body)

            HStack(spacing: 8) {

                Text(
                    evaluation.elementType
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if !evaluation.elementLabel.isEmpty {

                    Text(
                        evaluation.elementLabel
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if !evaluation.identifier.isEmpty {

                Text(
                    "Identifier: \(evaluation.identifier)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            let frameText = String(
                format:
                    "Frame: %.0f, %.0f — %.0f × %.0f",
                evaluation.frameX,
                evaluation.frameY,
                evaluation.frameWidth,
                evaluation.frameHeight
            )

            Text(frameText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !evaluation.remediation.isEmpty {

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {

                    Text("Remediation")
                        .font(.caption)
                        .fontWeight(.semibold)

                    Text(
                        evaluation.remediation
                    )
                    .font(.callout)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(
                cornerRadius: 10
            )
            .fill(
                Color.secondary.opacity(0.07)
            )
        )
    }

    // MARK: - Components

    private func sectionTitle(
        _ title: String
    ) -> some View {

        Text(title)
            .font(.title2)
            .fontWeight(.bold)
    }

    private func metadata(
        title: String,
        value: String
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 3
        ) {

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.callout)
        }
    }

    private func summaryCard(
        title: String,
        value: Int
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 8
        ) {

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(
                "\(value)"
            )
            .font(.title)
            .fontWeight(.bold)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(16)
        .background(
            RoundedRectangle(
                cornerRadius: 10
            )
            .fill(
                Color.secondary.opacity(0.08)
            )
        )
    }

    private func resultPill(
        title: String,
        value: Int
    ) -> some View {

        HStack(spacing: 5) {

            Text(title)

            Text(
                "\(value)"
            )
            .fontWeight(.semibold)
        }
        .font(.caption)
    }

    private func metric(
        _ title: String,
        _ value: Int
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 3
        ) {

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(
                "\(value)"
            )
            .fontWeight(.semibold)
        }
    }

    private func tableHeader(
        _ title: String
    ) -> some View {

        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
    }

    private func emptyState(
        _ message: String
    ) -> some View {

        Text(message)
            .foregroundStyle(.secondary)
            .padding()
    }

    // MARK: - Status Badge

    private func statusBadge(
        _ status: RuleResultStatus
    ) -> some View {

        Text(
            status.displayName
        )
        .font(.caption)
        .fontWeight(.bold)
        .padding(
            .horizontal,
            9
        )
        .padding(
            .vertical,
            5
        )
        .background(
            Capsule()
                .fill(
                    Color.secondary.opacity(0.15)
                )
        )
    }

    // MARK: - Severity Badge

    private func severityBadge(
        _ severity: AccessibilityFinding.Severity
    ) -> some View {

        Text(
            severity.displayName
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Annotation Color

    private func annotationColor(
        _ severity: AccessibilityFinding.Severity
    ) -> Color {

        switch severity {

        case .error:
            return .red

        case .warning:
            return .orange

        case .info:
            return .blue
        }
    }
}
