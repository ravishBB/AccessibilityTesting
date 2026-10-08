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
    @State private var selectedViewportID: UUID?
    @State private var selectedScreenID: UUID?
    @State private var showDetailedResults = false
    @State private var showDiff = false
    @State private var showAppMap = false
    @State private var showIntelligence = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                summarySection
                testerActionCenterSection

                AccessibilityQualityGateView(
                    gate: report.resolvedIntelligence.qualityGate
                )

                if let diff = report.resolvedIntelligence.diff {
                    DisclosureGroup(isExpanded: $showDiff) {
                        AccessibilityDiffView(diff: diff)
                            .padding(.top, 10)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Accessibility Diff")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Changes since the previous scan.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                DisclosureGroup(isExpanded: $showAppMap) {
                    AccessibilityAppMapView(report: report)
                        .padding(.top, 10)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Application Map")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                }

                DisclosureGroup(isExpanded: $showIntelligence) {
                    AccessibilityIntelligenceView(
                        intelligence: report.resolvedIntelligence
                    )
                    .padding(.top, 10)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility Analysis")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                }

                if let impactCenter = report.resolvedIntelligence.impactCenter {
                    DisclosureGroup(isExpanded: .constant(true)) {
                        AccessibilityImpactCenterView(impact: impactCenter)
                            .padding(.top, 10)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fix Priorities")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                    }
                }

                if let fixCenter = report.resolvedIntelligence.fixCenter {
                    DisclosureGroup(isExpanded: .constant(true)) {
                        AccessibilityFixCenterView(fixCenter: fixCenter)
                            .padding(.top, 10)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Developer Fix Center")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                    }
                }

                actionSummarySection
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
                        Text("Detailed Results")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Complete rule-level results and evidence.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Quality Report")
        .onAppear {
            if selectedScreenID == nil {
                let firstScreen = report.screens.first
                selectedScreenID = firstScreen?.id
                selectedAnnotationID = firstScreen?.annotations.first?.id
                selectedViewportID = firstScreen?.viewportScreenshots.first?.id
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Accessibility Quality Report")
                        .font(.largeTitle)
                        .fontWeight(.bold)
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
                    metadata(title: "Checks", value: "\(report.rulesExecuted) rules")
                    metadata(title: "Duration", value: formattedDuration)
                    metadata(
                        title: "Started",
                        value: report.startedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var formattedDuration: String {
        let seconds = max(0, report.finishedAt.timeIntervalSince(report.startedAt))
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let remaining = Int(seconds) % 60
        return "\(minutes)m \(remaining)s"
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Scan Summary")
                Spacer()
                statusBadge(report.overallStatus)
            }

            HStack(spacing: 12) {
                headlineMetric(
                    title: "Open findings",
                    value: report.totalFailures + report.totalWarnings + report.totalValidations,
                    subtitle: "failures, warnings & review",
                    symbol: "exclamationmark.triangle.fill",
                    prominent: true
                )
                headlineMetric(
                    title: "Passed checks",
                    value: report.totalPasses,
                    subtitle: "successful checks",
                    symbol: "checkmark.circle.fill"
                )
                headlineMetric(
                    title: "Manual review",
                    value: report.totalValidations,
                    subtitle: "checks needing tester verification",
                    symbol: "checklist"
                )
                headlineMetric(
                    title: "Screens",
                    value: report.screens.count,
                    subtitle: "screens reviewed",
                    symbol: "rectangle.on.rectangle"
                )
            }

            Text(
                report.totalFailures > 0
                    ? "Fix the automated failures first, then complete the manual checks listed in Tester Action Center."
                    : report.totalWarnings > 0
                        ? "Review the warnings and complete the manual checks before sign-off."
                        : report.totalValidations > 0
                            ? "Automated checks did not prove every requirement. Complete the manual checks before sign-off."
                            : "No accessibility findings were recorded in the scanned screens."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var testerActionCenterSection: some View {
        let actionable = report.issueEvaluations
            .sorted {
                let rank: [AccessibilityFinding.Severity: Int] = [.error: 0, .warning: 1, .info: 2]
                let lhs = rank[$0.severity] ?? 9
                let rhs = rank[$1.severity] ?? 9
                if lhs != rhs { return lhs < rhs }
                if $0.status != $1.status { return $0.status == .fail }
                return $0.ruleName.localizedCaseInsensitiveCompare($1.ruleName) == .orderedAscending
            }
            .prefix(8)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("Tester Action Center")
                Spacer()
                Text("What to verify before sign-off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if actionable.isEmpty {
                Label("No tester action is currently required", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)))
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(actionable.enumerated()), id: \.element.id) { index, evaluation in
                        Button {
                            selectEvaluation(evaluation)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.caption2.bold())
                                        .frame(width: 22, height: 22)
                                        .background(statusColor(evaluation.status))
                                        .foregroundStyle(.white)
                                        .clipShape(Circle())

                                    Text(evaluation.ruleName)
                                        .font(.callout.bold())
                                        .lineLimit(2)

                                    Spacer()
                                    statusBadge(evaluation.status)
                                }

                                Text(evaluation.targetDescription)
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)

                                Text(evaluation.evidenceSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Label(evaluation.testerAction, systemImage: "checklist")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.055)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var actionSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Open Findings")

            if report.issueEvaluations.isEmpty {
                Label("No open findings", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)))
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(report.issueEvaluations.prefix(6).enumerated()), id: \.offset) { index, evaluation in
                        Button {
                            selectEvaluation(evaluation)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(statusColor(evaluation.status))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(evaluation.ruleName)
                                            .font(.callout)
                                            .fontWeight(.semibold)
                                            .lineLimit(2)
                                        statusBadge(evaluation.status)
                                    }

                                    Text(evaluation.elementLabel.isEmpty ? evaluation.elementType : evaluation.elementLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)

                                    Text(evaluation.remediation.isEmpty ? evaluation.message : evaluation.remediation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.055)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if report.issueEvaluations.count > 6 {
                    Text("\(report.issueEvaluations.count - 6) additional findings in Issue Explorer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func selectEvaluation(_ evaluation: AccessibilityRuleEvaluation) {
        if let screen = report.screens.first(where: { $0.evaluations.contains(where: { $0.id == evaluation.id }) }) {
            selectedScreenID = screen.id
            if let annotation = screen.annotations.first(where: {
                $0.ruleID == evaluation.ruleID &&
                $0.elementType == evaluation.elementType &&
                abs($0.frameX - evaluation.frameX) < 0.5 &&
                abs($0.frameY - evaluation.frameY) < 0.5 &&
                $0.message == evaluation.message
            }) {
                selectedAnnotationID = annotation.id
                selectedViewportID = viewportContaining(
                    annotationID: annotation.id,
                    in: screen
                )?.id
            }
        }
    }

    // MARK: - Issue Explorer

    private var issueExplorerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    sectionTitle("Issue Explorer")
                    Text("Review findings by screen with the affected element and recommended fix.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let screen = selectedScreen {
                    Text("\(screen.annotations.count) failures")
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
                        selectedAnnotationID = screen.annotations.first?.id
                        selectedViewportID = screen.viewportScreenshots.first?.id
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
                    Text("\(screen.elementCount) elements • \(screen.failures) failures • \(screen.warnings) warnings • \(screen.validations) review")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if screen.annotations.isEmpty {
                    Label("No failed checks on this screen", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let viewport = selectedViewport(in: screen),
               let screenshotImage = thumbnailImage(from: viewport.screenshot.imageData, maxPixelSize: 900) {
                HStack(alignment: .top, spacing: 20) {
                    screenshotPanel(
                        screen: screen,
                        viewport: viewport,
                        image: screenshotImage
                    )
                    issueListPanel(screen: screen)
                }

                if screen.viewportScreenshots.count > 1 {
                    scrollViewportSection(screen: screen)
                }
            } else if let screenshot = screen.screenshot,
                      let screenshotImage = thumbnailImage(from: screenshot.imageData, maxPixelSize: 900) {
                HStack(alignment: .top, spacing: 20) {
                    screenshotPanel(
                        screen: screen,
                        viewport: nil,
                        image: screenshotImage
                    )
                    issueListPanel(screen: screen)
                }
            } else {
                emptyState("No screenshot was captured for this screen.")
            }
        }
        .padding(18)
        .onAppear {
            if selectedAnnotationID == nil {
                selectedAnnotationID = screen.annotations.first?.id
            }
            if selectedViewportID == nil {
                selectedViewportID = viewportContaining(
                    annotationID: selectedAnnotationID,
                    in: screen
                )?.id ?? screen.viewportScreenshots.first?.id
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func scrollViewportSection(screen: ScreenScanResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Scrollable Content", systemImage: "arrow.up.and.down")
                    .font(.headline)
                Spacer()
                Text("\(screen.viewportScreenshots.count) unique viewport screenshots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Each screenshot represents a distinct viewport captured while scrolling this screen. Duplicate screenshots are removed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(screen.viewportScreenshots.dropFirst()) { viewport in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Viewport \(viewport.index)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            if !viewport.annotations.isEmpty {
                                Text("\(viewport.annotations.count) failures")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            } else {
                                Text("No failed checks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let image = thumbnailImage(
                            from: viewport.screenshot.imageData,
                            maxPixelSize: 900
                        ) {
                            InteractiveScreenshotView(
                                image: image,
                                screenshotWidth: viewport.screenshot.width,
                                screenshotHeight: viewport.screenshot.height,
                                hierarchyWidth: viewport.screenshot.hierarchyWidth,
                                hierarchyHeight: viewport.screenshot.hierarchyHeight,
                                annotations: viewport.annotations,
                                selectedAnnotationID: selectedViewportID == viewport.id ? selectedAnnotationID : nil
                            )
                            .frame(width: 390, height: 620)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                            )
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.04))
                    )
                }
            }
        }
        .padding(.top, 4)
    }

    private func screenshotPanel(
        screen: ScreenScanResult,
        viewport: ScreenshotViewport?,
        image: NSImage
    ) -> some View {
        let screenshot = viewport?.screenshot ?? screen.screenshot
        let viewportAnnotations = viewport?.annotations ?? screen.annotations

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    viewport.map { "Viewport \($0.index)" } ?? "Screen",
                    systemImage: "rectangle.on.rectangle"
                )
                .font(.headline)
                Spacer()
                Text("Only the selected failure is highlighted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let screenshot {
                InteractiveScreenshotView(
                    image: image,
                    screenshotWidth: screenshot.width,
                    screenshotHeight: screenshot.height,
                    hierarchyWidth: screenshot.hierarchyWidth,
                    hierarchyHeight: screenshot.hierarchyHeight,
                    annotations: viewportAnnotations,
                    selectedAnnotationID: viewport?.id == selectedViewportID ? selectedAnnotationID : nil
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
        }
        .frame(minWidth: 410, alignment: .topLeading)
    }

    private func issueListPanel(screen: ScreenScanResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Failures", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                Spacer()

                if !screen.annotations.isEmpty {
                    navigationControls(for: screen)
                }
            }

            if screen.annotations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No failed checks", systemImage: "checkmark.circle")
                        .font(.callout)
                        .fontWeight(.semibold)
                    Text("Warnings and manual-review items are shown elsewhere in the report and are not highlighted on the screenshot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
            } else {
                if let selected = selectedAnnotation(in: screen) {
                    selectedFailureDetail(selected, in: screen)
                }

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
                    .frame(height: 420)
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

    private func viewportContaining(
        annotationID: UUID?,
        in screen: ScreenScanResult
    ) -> ScreenshotViewport? {
        guard let annotationID else { return nil }
        return screen.viewportScreenshots.first { viewport in
            viewport.annotations.contains { $0.id == annotationID }
        }
    }

    private func selectedViewport(in screen: ScreenScanResult) -> ScreenshotViewport? {
        if let selectedViewportID,
           let viewport = screen.viewportScreenshots.first(where: { $0.id == selectedViewportID }) {
            return viewport
        }

        if let selectedAnnotationID,
           let viewport = viewportContaining(annotationID: selectedAnnotationID, in: screen) {
            return viewport
        }

        return screen.viewportScreenshots.first
    }

    private func selectedAnnotation(in screen: ScreenScanResult) -> ScreenshotAnnotation? {
        guard let selectedAnnotationID else {
            return screen.annotations.first
        }
        return screen.annotations.first { $0.id == selectedAnnotationID }
            ?? screen.annotations.first
    }

    private func navigationControls(for screen: ScreenScanResult) -> some View {
        let currentIndex = screen.annotations.firstIndex { $0.id == selectedAnnotationID } ?? 0
        let count = screen.annotations.count

        return HStack(spacing: 8) {
            Text("\(currentIndex + 1) of \(count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                selectPreviousFailure(in: screen)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .disabled(count < 2 || currentIndex == 0)

            Button {
                selectNextFailure(in: screen)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .disabled(count < 2 || currentIndex >= count - 1)
        }
    }

    private func selectPreviousFailure(in screen: ScreenScanResult) {
        guard !screen.annotations.isEmpty else { return }
        let currentIndex = screen.annotations.firstIndex { $0.id == selectedAnnotationID } ?? 0
        let nextIndex = max(currentIndex - 1, 0)
        selectedAnnotationID = screen.annotations[nextIndex].id
        selectedViewportID = viewportContaining(
            annotationID: selectedAnnotationID,
            in: screen
        )?.id
    }

    private func selectNextFailure(in screen: ScreenScanResult) {
        guard !screen.annotations.isEmpty else { return }
        let currentIndex = screen.annotations.firstIndex { $0.id == selectedAnnotationID } ?? -1
        let nextIndex = min(currentIndex + 1, screen.annotations.count - 1)
        selectedAnnotationID = screen.annotations[nextIndex].id
        selectedViewportID = viewportContaining(
            annotationID: selectedAnnotationID,
            in: screen
        )?.id
    }

    private func selectedFailureDetail(
        _ annotation: ScreenshotAnnotation,
        in screen: ScreenScanResult
    ) -> some View {
        let currentIndex = screen.annotations.firstIndex { $0.id == annotation.id } ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(annotation.ruleName)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Issue \(currentIndex + 1) of \(screen.annotations.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("FAIL")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.red.opacity(0.12)))
            }

            detailRow(title: "ID", value: String(format: "%02d", annotation.number))
            detailRow(
                title: "Element",
                value: annotation.elementLabel.isEmpty
                    ? annotation.elementType
                    : annotation.elementLabel
            )
            detailRow(title: "Type", value: annotation.elementType)
            detailRow(title: "Issue", value: annotation.message)

            VStack(alignment: .leading, spacing: 5) {
                Text("Recommendation")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text(annotation.remediation)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.22), lineWidth: 1)
        )
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.callout)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func issueExplorerRow(_ annotation: ScreenshotAnnotation) -> some View {
        let selected = selectedAnnotationID == annotation.id

        return Button {
            selectedAnnotationID = annotation.id
            if let screen = selectedScreen {
                selectedViewportID = viewportContaining(
                    annotationID: annotation.id,
                    in: screen
                )?.id
            }
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
                            Text("Recommended fix")
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
            if let screen = selectedScreen {
                selectedViewportID = viewportContaining(
                    annotationID: annotation.id,
                    in: screen
                )?.id
            }
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

            sectionTitle("Screen Results")

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
                            title: "MANUAL",
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

            sectionTitle("Rule Results")

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
                            "Manual",
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

            sectionTitle("All Findings")

            if report.issueEvaluations.isEmpty {

                emptyState(
                    "No accessibility findings were recorded."
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

            sectionTitle("Passed Checks")

            if report.passEvaluations.isEmpty {

                emptyState(
                    "No passed checks were recorded."
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

        let statusColumnWidth: CGFloat = 100

        return LazyVStack(
            alignment: .leading,
            spacing: 16
        ) {

            sectionTitle("Rule Summary")

            VStack(spacing: 0) {

                // Keep the header columns exactly the same width as the
                // corresponding value columns below so counts stay aligned.
                HStack(spacing: 0) {
                    Text("Rule")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ruleSummaryHeader("Failures", width: statusColumnWidth)
                    ruleSummaryHeader("Warnings", width: statusColumnWidth)
                    ruleSummaryHeader("Manual", width: statusColumnWidth)
                    ruleSummaryHeader("Pass", width: statusColumnWidth)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)

                Divider()

                ForEach(report.ruleSummaries) { rule in
                    HStack(spacing: 0) {
                        Text(rule.ruleName)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ruleSummaryValue(rule.failures, width: statusColumnWidth)
                        ruleSummaryValue(rule.warnings, width: statusColumnWidth)
                        ruleSummaryValue(rule.validations, width: statusColumnWidth)
                        ruleSummaryValue(rule.passes, width: statusColumnWidth)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)

                    Divider()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2))
            )
        }
    }

    private func ruleSummaryHeader(
        _ title: String,
        width: CGFloat
    ) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .frame(width: width, alignment: .center)
    }

    private func ruleSummaryValue(
        _ value: Int,
        width: CGFloat
    ) -> some View {
        Text("\(value)")
            .frame(width: width, alignment: .center)
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

    private func headlineMetric(
        title: String,
        value: Int,
        subtitle: String,
        symbol: String,
        prominent: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(prominent ? Color.accentColor : Color.secondary)

            Text("\(value)")
                .font(.title)
                .fontWeight(.bold)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.secondary.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.secondary.opacity(0.10)))
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

    private func statusColor(_ status: RuleResultStatus) -> Color {
        switch status {
        case .fail:
            return .red
        case .warning:
            return .orange
        case .validate:
            return .blue
        case .pass:
            return .green
        }
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
        let selectedAnnotationID: UUID?

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
                        let screenshotBounds = CGRect(
                            x: 0,
                            y: 0,
                            width: max(hierarchyWidth, 1),
                            height: max(hierarchyHeight, 1)
                        )
                        let visibleFrame = frame.intersection(screenshotBounds)
                        let isSelected = selectedAnnotationID == annotation.id

                        if isSelected &&
                            !visibleFrame.isNull &&
                            visibleFrame.width > 0 &&
                            visibleFrame.height > 0 {
                            let x = visibleFrame.minX * scaleX
                            let y = visibleFrame.minY * scaleY
                            let width = max(visibleFrame.width * scaleX, 1)
                            let height = max(visibleFrame.height * scaleY, 1)
                            // Keep the screenshot visually clean: only the
                            // currently selected failed component is highlighted.
                            // Validation and warning items are never rendered here.
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.red.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.red, lineWidth: 4)
                                )
                                .frame(width: width, height: height)
                                .position(
                                    x: x + width / 2,
                                    y: y + height / 2
                                )
                                .allowsHitTesting(false)
                                .zIndex(100)
                        }
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
