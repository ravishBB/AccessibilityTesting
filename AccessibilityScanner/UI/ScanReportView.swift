//
//  ScanReportView.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 24/09/26.
//

import SwiftUI
import AppKit
import ImageIO

struct ScanReportView: View {

    let report: AccessibilityScanResult

    @State private var selectedAnnotationID: UUID?
    @State private var selectedScreenID: UUID?
    @State private var showDetailedResults = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                summarySection
                issueExplorerSection
                screenResultsSection

                DisclosureGroup(isExpanded: $showDetailedResults) {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ruleResultsSection
                        issuesSection
                        passesSection
                        ruleSummarySection
                    }
                    .padding(.top, 12)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Detailed Rule Results")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Open this only when you need the complete rule-by-rule audit.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Accessibility Report")
        .onAppear {
            if selectedScreenID == nil {
                selectedScreenID = report.screens.first?.id
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Accessibility Scan Report")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(report.applicationName)
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Text("Review issues screen by screen. Select any numbered issue to see exactly what needs attention.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                HStack(spacing: 12) {
                    ShareJSONButton(report: report)
                    statusBadge(report.overallStatus)
                }
            }

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    metadata(title: "Bundle ID", value: report.bundleID)
                    metadata(title: "Device", value: report.deviceName)
                    metadata(title: "UDID", value: report.deviceUDID)
                    metadata(
                        title: "Started",
                        value: report.startedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("At a Glance")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                spacing: 12
            ) {
                summaryCard(title: "Screens", value: report.screens.count)
                summaryCard(title: "Elements Tested", value: report.totalElementsTested)
                summaryCard(title: "Rules Executed", value: report.rulesExecuted)
                summaryCard(title: "Failures", value: report.totalFailures)
                summaryCard(title: "Warnings", value: report.totalWarnings)
                summaryCard(title: "Validate", value: report.totalValidations)
                summaryCard(title: "Passed", value: report.totalPasses)
                summaryCard(title: "Issues", value: report.totalIssues)
            }
        }
    }

    // MARK: - Issue Explorer

    private var issueExplorerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    sectionTitle("Issue Explorer")
                    Text("Select a screen, then select an issue. The affected area stays visible while you review the fix.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let screen = selectedScreen {
                    Text("\(screen.annotations.count) issue(s)")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }

            screenSelector

            if let screen = selectedScreen {
                issueExplorerCard(screen: screen)
            } else {
                emptyState("No screens were captured in this scan.")
            }
        }
    }

    private var screenSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(report.screens) { screen in
                    Button {
                        selectedScreenID = screen.id
                        selectedAnnotationID = nil
                    } label: {
                        HStack(spacing: 8) {
                            Text(screen.name)
                                .fontWeight(.semibold)

                            Text("\(screen.annotations.count)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(
                                        screen.annotations.isEmpty
                                            ? Color.secondary.opacity(0.14)
                                            : Color.accentColor.opacity(0.16)
                                    )
                                )
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(
                                    selectedScreenID == screen.id
                                        ? Color.accentColor.opacity(0.14)
                                        : Color.secondary.opacity(0.08)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(
                                    selectedScreenID == screen.id
                                        ? Color.accentColor
                                        : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var selectedScreen: ScreenScanResult? {
        guard let selectedScreenID else { return report.screens.first }
        return report.screens.first { $0.id == selectedScreenID }
    }

    private func issueExplorerCard(screen: ScreenScanResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(screen.name)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("\(screen.elementCount) elements • \(screen.failures) failures • \(screen.warnings) warnings • \(screen.validations) to validate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if screen.annotations.isEmpty {
                    Label("No annotated issues", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let screenshot = screen.screenshot,
               let screenshotImage = thumbnailImage(from: screenshot.imageData, maxPixelSize: 900) {
                HStack(alignment: .top, spacing: 20) {
                    screenshotPanel(
                        screen: screen,
                        screenshot: screenshot,
                        image: screenshotImage
                    )
                    issueListPanel(screen: screen)
                }
            } else {
                emptyState("No screenshot was captured for this screen.")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func screenshotPanel(
        screen: ScreenScanResult,
        screenshot: ScanScreenshot,
        image: NSImage
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Screen preview", systemImage: "rectangle.on.rectangle")
                    .font(.headline)
                Spacer()
                Text("Tap a number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            InteractiveScreenshotView(
                image: image,
                screenshotWidth: screenshot.width,
                screenshotHeight: screenshot.height,
                hierarchyWidth: screenshot.hierarchyWidth,
                hierarchyHeight: screenshot.hierarchyHeight,
                annotations: screen.annotations,
                selectedAnnotationID: $selectedAnnotationID
            )
            .frame(width: 390, height: 620)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
            )
        }
        .frame(minWidth: 410, alignment: .topLeading)
    }

    private func issueListPanel(screen: ScreenScanResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Issues", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Spacer()
                if selectedAnnotationID != nil {
                    Button("Clear selection") {
                        selectedAnnotationID = nil
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            if screen.annotations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No annotated issues", systemImage: "checkmark.circle")
                        .font(.callout)
                        .fontWeight(.semibold)
                    Text("This screen has no failures, warnings, or validation markers to review here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(screen.annotations) { annotation in
                                issueExplorerRow(annotation)
                                    .id(annotation.id)
                            }
                        }
                        .padding(.trailing, 4)
                    }
                    .frame(minWidth: 360, maxWidth: 500)
                    .frame(height: 620)
                    .onChange(of: selectedAnnotationID) { _, newID in
                        guard let newID else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 360, maxWidth: 500, alignment: .topLeading)
    }

    private func issueExplorerRow(_ annotation: ScreenshotAnnotation) -> some View {
        let selected = selectedAnnotationID == annotation.id

        return Button {
            selectedAnnotationID = annotation.id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("\(annotation.number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(annotationColor(annotation.severity))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(annotation.ruleName)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                        severityBadge(annotation.severity)
                    }

                    if !annotation.elementLabel.isEmpty {
                        Text("\(annotation.elementType) — \(annotation.elementLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        Text(annotation.elementType)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(annotation.message)
                        .font(.caption)
                        .lineLimit(selected ? 6 : 2)

                    if selected && !annotation.remediation.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("How to fix")
                                .font(.caption)
                                .fontWeight(.bold)
                            Text(annotation.remediation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 3)
                    }
                }

                Spacer(minLength: 4)
            }
            .padding(10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(selected ? Color.accentColor.opacity(0.13) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(selected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.10), lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Image Thumbnail

    private func thumbnailImage(
        from data: Data,
        maxPixelSize: Int
    ) -> NSImage? {

        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            nil
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(
                width: cgImage.width,
                height: cgImage.height
            )
        )
    }

    // MARK: - Annotation Row

    private func annotationRow(
        _ annotation: ScreenshotAnnotation
    ) -> some View {

        Button {
            selectedAnnotationID = annotation.id
        } label: {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    selectedAnnotationID == annotation.id
                        ? Color.accentColor.opacity(0.12)
                        : Color.clear
                )
        )
    }

    // MARK: - Screens

    private var screenResultsSection: some View {

        LazyVStack(
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

        LazyVStack(
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

        LazyVStack(
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

        LazyVStack(
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

        LazyVStack(
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


    // MARK: - Interactive Screenshot

    private struct InteractiveScreenshotView: View {
        let image: NSImage
        let screenshotWidth: Double
        let screenshotHeight: Double
        let hierarchyWidth: Double
        let hierarchyHeight: Double
        let annotations: [ScreenshotAnnotation]
        @Binding var selectedAnnotationID: UUID?

        private let markerSize: CGFloat = 30

        var body: some View {
            GeometryReader { proxy in
                let availableWidth = min(proxy.size.width, 500)
                let aspectRatio = max(
                    CGFloat(screenshotWidth / max(screenshotHeight, 1)),
                    0.01
                )
                let displayWidth = availableWidth
                let displayHeight = displayWidth / aspectRatio
                let scaleX = displayWidth / CGFloat(max(hierarchyWidth, 1))
                let scaleY = displayHeight / CGFloat(max(hierarchyHeight, 1))

                ZStack(alignment: .topLeading) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(
                            width: displayWidth,
                            height: displayHeight
                        )

                    ForEach(annotations) { annotation in
                        let frame = annotation.frame
                        let x = frame.minX * scaleX
                        let y = frame.minY * scaleY
                        let width = max(frame.width * scaleX, 1)
                        let height = max(frame.height * scaleY, 1)
                        let markerX = min(
                            max(x, 0),
                            max(displayWidth - markerSize, 0)
                        )
                        let markerY = min(
                            max(y, 0),
                            max(displayHeight - markerSize, 0)
                        )
                        let isSelected = selectedAnnotationID == annotation.id

                        if isSelected {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor.opacity(0.18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.accentColor, lineWidth: 4)
                                )
                                .frame(width: width, height: height)
                                .position(
                                    x: x + width / 2,
                                    y: y + height / 2
                                )
                                .allowsHitTesting(false)
                        }

                        Button {
                            selectedAnnotationID = annotation.id
                        } label: {
                            Text("\(annotation.number)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: markerSize, height: markerSize)
                                .background(Self.annotationColor(annotation.severity))
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(
                                            isSelected ? Color.white : Color.clear,
                                            lineWidth: 3
                                        )
                                )
                                .shadow(radius: isSelected ? 5 : 2)
                        }
                        .buttonStyle(.plain)
                        .position(
                            x: markerX + markerSize / 2,
                            y: markerY + markerSize / 2
                        )
                        .zIndex(isSelected ? 100 : Double(annotation.number))
                    }
                }
                .frame(width: displayWidth, height: displayHeight)
                .position(
                    x: proxy.size.width / 2,
                    y: displayHeight / 2
                )
            }
            .aspectRatio(
                CGFloat(screenshotWidth / max(screenshotHeight, 1)),
                contentMode: .fit
            )
        }

        private static func annotationColor(
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
