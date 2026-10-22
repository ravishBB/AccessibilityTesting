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

    /// Findings grouped by rule, computed once per report rather than on every body pass.
    private let grouping: FindingGrouping
    /// Results by BB issue and category, computed once per report.
    private let bbReport: BBReport
    /// Fix guidance per rule, computed once per report.
    private let fixCenter: AccessibilityFixCenter

    init(report: AccessibilityScanResult) {
        self.report = report
        self.grouping = FindingGrouping(report: report)
        self.bbReport = BBReport(report: report)
        self.fixCenter = AccessibilityFixCenter.analyze(report: report)
    }

    @State private var selectedAnnotationID: UUID?
    @State private var selectedViewportID: UUID?
    /// Scroll position of the failure list only (not the whole report).
    @State private var listScrollID: UUID?
    @State private var selectedScreenID: UUID?
    /// One status filter for the BB Report and the Issue Explorer.
    @State private var reportFilter: ReportFilter = .all
    @State private var showAppMap = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                summarySection
                BBReportView(report: bbReport, statusFilter: $reportFilter, onSelect: selectEvaluation)
                issueExplorerSection
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

                screenResultsSection

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
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Quality Report")
        .onChange(of: reportFilter) { _, _ in reselectForFilter() }
        .onAppear {
            if selectedScreenID == nil {
                let firstScreen = report.screens.first
                selectedScreenID = firstScreen?.id
                selectedAnnotationID = firstScreen.flatMap { checks(in: $0).first?.id }
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
                    ShareReportMenu(report: report)
                    statusBadge(report.overallStatus)
                }
            }

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    metadata(title: "Bundle ID", value: report.bundleID)
                    metadata(title: "Device", value: report.deviceName)
                    if let environment = report.environment {
                        metadata(title: "Platform", value: environment.osDescription)
                        if let appVersion = environment.appVersionDescription {
                            metadata(title: "App version", value: appVersion)
                        }
                    }
                    metadata(title: "Checks", value: "\(report.automatedVerdictRuleCount) of \(report.verdictCapableRuleCount) \(report.platformName) rules gave results")
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
            }

            HStack(spacing: 12) {
                headlineMetric(
                    title: "Fail",
                    value: grouping.failureCount,
                    subtitle: "unique failed results",
                    symbol: "exclamationmark.triangle.fill",
                    prominent: grouping.issueCount > 0
                )
                headlineMetric(
                    title: "Validate",
                    value: grouping.manualReviewCount,
                    subtitle: "checks a tester confirms",
                    symbol: "checklist"
                )
                headlineMetric(
                    title: "Pass",
                    value: grouping.passCount,
                    subtitle: "unique passed results",
                    symbol: "checkmark.circle.fill"
                )
                headlineMetric(
                    title: "Screens",
                    value: report.screens.count,
                    subtitle: "screens reviewed",
                    symbol: "rectangle.on.rectangle"
                )
            }

            Text(
                grouping.failureCount > 0
                    ? "Fix the failures first, then confirm the Validate items."
                    : grouping.manualReviewCount > 0
                            ? "No failures were found. Confirm the Validate items before sign-off."
                            : "No findings were recorded by the \(report.automatedVerdictRuleCount) of \(AccessibilityRuleCatalog.ruleCount) rules that produced results. This is not a pass: the remaining rules need manual or assistive-technology testing."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func groupCard(_ group: GroupedFinding, showHowToTest: Bool) -> some View {
        let names = group.occurrences
            .prefix(3)
            .map { $0.evaluation.targetDescription }
            .joined(separator: ", ")
        let remaining = group.count - min(group.count, 3)
        let elementsLine = remaining > 0 ? "\(names) and \(remaining) more" : names
        let detail = group.remediation.isEmpty ? group.sampleMessage : group.remediation

        return Button {
            if let first = group.occurrences.first {
                selectEvaluation(first.evaluation)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group.displayTitle)
                        .font(.callout.bold())
                        .lineLimit(2)
                    Spacer()
                    statusBadge(group.status)
                }
                if !group.displayDescription.isEmpty {
                    Text(group.displayDescription)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    if let wcag = group.bbIssue?.wcag ?? group.bbIfConfirmed?.wcag {
                        tag("WCAG \(wcag)")
                    }
                    tag("\(group.metadata.impact.displayName) impact")
                    if let wcag = group.metadata.wcagLabel {
                        tag(wcag)
                    }
                    tag("\(group.count) element\(group.count == 1 ? "" : "s") · \(group.screenCount) screen\(group.screenCount == 1 ? "" : "s")")
                }

                if !elementsLine.isEmpty {
                    Text(elementsLine)
                        .font(.caption.bold())
                        .lineLimit(2)
                }

                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showHowToTest {
                    Label(group.metadata.howToTest, systemImage: "checklist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.055)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }

    private func selectEvaluation(_ evaluation: AccessibilityRuleEvaluation) {
        if let screen = report.screens.first(where: { $0.evaluations.contains(where: { $0.id == evaluation.id }) }) {
            selectedScreenID = screen.id
            if !reportFilter.includes(evaluation.status) {
                reportFilter = ReportFilter(evaluation.status)
            }
            if let annotation = checks(in: screen).first(where: {
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
                        selectedAnnotationID = checks(in: screen).first?.id
                        selectedViewportID = viewportContaining(
                            annotationID: selectedAnnotationID,
                            in: screen
                        )?.id ?? screen.viewportScreenshots.first?.id
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
                selectedAnnotationID = checks(in: screen).first?.id
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
                            let viewportChecks = checks(in: viewport)
                            if !viewportChecks.isEmpty {
                                Text("\(viewportChecks.count) \(reportFilter.noun)")
                                    .font(.caption)
                                    .foregroundStyle(reportFilter.color)
                            } else {
                                Text("No \(reportFilter.noun)")
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
                                annotations: checks(in: viewport),
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
        let viewportAnnotations = viewport.map { checks(in: $0) } ?? checks(in: screen)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    viewport.map { "Viewport \($0.index)" } ?? "Screen",
                    systemImage: "rectangle.on.rectangle"
                )
                .font(.headline)
                Spacer()
                Text("Only the selected component is highlighted")
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
                Label(reportFilter == .all ? "All results" : reportFilter.title, systemImage: reportFilter.symbol)
                    .font(.headline)
                    .foregroundStyle(reportFilter.color)
                Spacer()

                if !checks(in: screen).isEmpty {
                    navigationControls(for: screen)
                }
            }

            if checks(in: screen).isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No \(reportFilter.noun) on this screen", systemImage: "checkmark.circle")
                        .font(.callout)
                        .fontWeight(.semibold)
                    if !screen.viewportScreenshots.contains(where: { $0.checks != nil }), reportFilter != .fail {
                        Text("This report was saved before the screenshot filter existed. Run the scan again to see validate and pass results on the screenshot.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
            } else {
                if let selected = selectedAnnotation(in: screen) {
                    // Fixed minimum height: the detail text varies in length,
                    // and a changing height shifts everything below it.
                    selectedFailureDetail(selected, in: screen)
                        .frame(minHeight: 220, alignment: .topLeading)
                }

                // scrollPosition moves only this list. ScrollViewReader's
                // scrollTo also scrolled the whole report page, so the view
                // jumped up or down on every Next/Previous.
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(checks(in: screen)) { annotation in
                            issueExplorerRow(annotation)
                                .id(annotation.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.trailing, 4)
                }
                .scrollPosition(id: $listScrollID, anchor: .center)
                .frame(minWidth: 360, maxWidth: 500)
                .frame(height: 420)
                .onChange(of: selectedAnnotationID) { _, newID in
                    guard let newID else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        listScrollID = newID
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
            viewport.annotations.contains { $0.id == annotationID } ||
                (viewport.checks ?? []).contains { $0.id == annotationID }
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
        let items = checks(in: screen)
        guard let selectedAnnotationID else {
            return items.first
        }
        return items.first { $0.id == selectedAnnotationID }
            ?? items.first
    }

    private func navigationControls(for screen: ScreenScanResult) -> some View {
        let items = checks(in: screen)
        let currentIndex = items.firstIndex { $0.id == selectedAnnotationID } ?? 0
        let count = items.count

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
        let items = checks(in: screen)
        guard !items.isEmpty else { return }
        let currentIndex = items.firstIndex { $0.id == selectedAnnotationID } ?? 0
        let nextIndex = max(currentIndex - 1, 0)
        selectedAnnotationID = items[nextIndex].id
        selectedViewportID = viewportContaining(
            annotationID: selectedAnnotationID,
            in: screen
        )?.id
    }

    private func selectNextFailure(in screen: ScreenScanResult) {
        let items = checks(in: screen)
        guard !items.isEmpty else { return }
        let currentIndex = items.firstIndex { $0.id == selectedAnnotationID } ?? -1
        let nextIndex = min(currentIndex + 1, items.count - 1)
        selectedAnnotationID = items[nextIndex].id
        selectedViewportID = viewportContaining(
            annotationID: selectedAnnotationID,
            in: screen
        )?.id
    }

    private func selectedFailureDetail(
        _ annotation: ScreenshotAnnotation,
        in screen: ScreenScanResult
    ) -> some View {
        let items = checks(in: screen)
        let currentIndex = items.firstIndex { $0.id == annotation.id } ?? 0
        let status = annotation.displayStatus
        let color = statusColor(status)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(annotation.displayTitle)
                        .font(.title3)
                        .fontWeight(.bold)
                    if let description = annotation.displayDescription {
                        Text(description)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("\(reportFilter.title) \(currentIndex + 1) of \(items.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(status == .validate ? "VALIDATE" : status.displayName)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(color.opacity(0.12)))
            }

            detailRow(title: "ID", value: String(format: "%02d", annotation.number))
            if annotation.bbIfConfirmedID != nil {
                detailRow(title: "If confirmed", value: "Record as a failure")
            }
            if annotation.isScreenLevel {
                detailRow(title: "Element", value: "Whole screen (runtime check)")
            } else {
                detailRow(
                    title: "Element",
                    value: annotation.elementLabel.isEmpty
                        ? annotation.elementType
                        : annotation.elementLabel
                )
                detailRow(title: "Type", value: annotation.elementType)
            }
            detailRow(title: "Issue", value: annotation.message)

            if !annotation.remediation.isEmpty {
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
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.22), lineWidth: 1)
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
                    .background(annotation.displayStatus == .fail
                        ? annotationColor(annotation.severity)
                        : statusColor(annotation.displayStatus))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(annotation.displayTitle)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                        severityBadge(annotation.severity)
                    }
                    if let description = annotation.displayDescription {
                        Text(description)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(2)
                    }

                    if annotation.isScreenLevel {
                        Text("Whole screen (runtime check)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !annotation.elementLabel.isEmpty {
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

    // MARK: - Issues

    // MARK: - Passes

    // MARK: - Rule Summary

    // MARK: - Evaluation Card

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
        .foregroundStyle(statusColor(status))
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
                    statusColor(status).opacity(0.15)
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
        case .notTested:
            return .gray
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

                        if isSelected && !annotation.isScreenLevel &&
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
                            let color = Self.highlightColor(annotation.displayStatus)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(color.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(color, lineWidth: 4)
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

        static func highlightColor(_ status: RuleResultStatus) -> Color {
            switch status {
            case .pass: return .green
            case .validate, .notTested: return .blue
            case .warning: return .orange
            case .fail: return .red
            }
        }
    }

    // MARK: - Screenshot filter

    private func matchesFilter(_ annotation: ScreenshotAnnotation) -> Bool {
        reportFilter.includes(annotation.displayStatus)
    }

    /// Components shown for the current filter. Reports saved before the
    /// filter existed hold failures only.
    private func checks(in viewport: ScreenshotViewport) -> [ScreenshotAnnotation] {
        if let checks = viewport.checks {
            return checks.filter(matchesFilter)
        }
        return reportFilter == .fail || reportFilter == .all ? viewport.annotations : []
    }

    private func checks(in screen: ScreenScanResult) -> [ScreenshotAnnotation] {
        if screen.viewportScreenshots.isEmpty {
            return reportFilter == .fail || reportFilter == .all ? screen.annotations : []
        }
        return screen.viewportScreenshots.flatMap { checks(in: $0) }
    }

    /// Keeps the screenshot selection on an item the filter still shows.
    private func reselectForFilter() {
        guard let screen = selectedScreen else { return }
        let selectedStillShown = checks(in: screen).contains { $0.id == selectedAnnotationID }
        if !selectedStillShown {
            selectedAnnotationID = checks(in: screen).first?.id
            selectedViewportID = viewportContaining(
                annotationID: selectedAnnotationID,
                in: screen
            )?.id ?? screen.viewportScreenshots.first?.id
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
