//
//  ContentView.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 22/09/26.
//

import SwiftUI

struct ContentView: View {

    // MARK: - View Model

    @StateObject private var viewModel = ScannerViewModel()

    // Controls presentation of the full accessibility report.
    @State private var showingReport = false

    // MARK: - Body

    var body: some View {

        VStack(spacing: 0) {
            header

            Divider()
            ScrollView {

                VStack(
                    alignment: .leading,
                    spacing: 24
                ) {

                    configurationSection

                    Divider()

                    resultsSection
                }
                .padding(24)
            }

            Divider()

            statusBar
        }
        .frame(
            minWidth: 900,
            minHeight: 700
        )
        .background(
            Color(nsColor: .windowBackgroundColor)
        )
        .onAppear {
            viewModel.loadDevices()
        }
        .alert(
            "Scan Error",
            isPresented: Binding(
                get: {
                    viewModel.errorMessage != nil
                },
                set: { value in
                    if !value {
                        viewModel.errorMessage = nil
                    }
                }
            )
        ) {

            Button("OK") {
                viewModel.errorMessage = nil
            }

        } message: {

            Text(
                viewModel.errorMessage ?? ""
            )
        }
        .sheet(
            isPresented: $showingReport
        ) {

            if let report = viewModel.scanResult {

                ScanReportView(
                    report: report
                )
                .frame(
                    minWidth: 1000,
                    minHeight: 750
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {

        HStack(spacing: 16) {

            Image(
                systemName:
                    "figure.roll.runningpace"
            )
            .font(.system(size: 32))
            .foregroundStyle(.blue)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {

                Text("Mobile Accessibility Scanner")
                    .font(.title)
                    .fontWeight(.bold)

                Text(
                    "Black-box accessibility testing"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isScanning {

                ProgressView()
                    .controlSize(.small)
            }

            Button {

                viewModel.refresh()

            } label: {

                Image(
                    systemName: "arrow.clockwise"
                )

                Text("Refresh")
            }
            .buttonStyle(.bordered)
            .disabled(
                viewModel.isScanning ||
                viewModel.isLoadingDevices
            )
        }
        .padding(20)
    }

    // MARK: - Configuration Section

    private var configurationSection: some View {

        VStack(
            alignment: .leading,
            spacing: 18
        ) {

            Text("Scan Configuration")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(
                alignment: .leading,
                spacing: 8
            ) {

                Text("Device")
                    .font(.headline)

                HStack {

                    if viewModel.isLoadingDevices {

                        ProgressView()
                            .controlSize(.small)
                    }

                    Picker(
                        "Device",
                        selection:
                            $viewModel.selectedDevice
                    ) {

                        Text("Select a device")
                            .tag(
                                Optional<Device>.none
                            )

                        ForEach(
                            viewModel.devices
                        ) { device in

                            Text(
                                device.displayName
                            )
                            .tag(
                                Optional(device)
                            )
                        }
                    }
                    .labelsHidden()
                    .frame(
                        maxWidth: .infinity
                    )
                    .disabled(
                        viewModel.isScanning ||
                        viewModel.isLoadingDevices
                    )
                    .onChange(
                        of: viewModel.selectedDevice
                    ) { _, _ in

                        viewModel.deviceChanged()
                    }
                }
            }

            VStack(
                alignment: .leading,
                spacing: 8
            ) {

                Text("Application")
                    .font(.headline)

                HStack {

                    if viewModel.isLoadingApplications {

                        ProgressView()
                            .controlSize(.small)
                    }

                    Picker(
                        "Application",
                        selection:
                            $viewModel.selectedApplication
                    ) {

                        Text("Select an application")
                            .tag(
                                Optional<InstalledApp>.none
                            )

                        ForEach(
                            viewModel.applications
                        ) { application in

                            Text(
                                application.displayName
                            )
                            .tag(
                                Optional(application)
                            )
                        }
                    }
                    .labelsHidden()
                    .frame(
                        maxWidth: .infinity
                    )
                    .disabled(
                        viewModel.isScanning ||
                        viewModel.isLoadingApplications ||
                        viewModel.selectedDevice == nil
                    )
                }
            }

            if let device = viewModel.selectedDevice,
               let application =
                    viewModel.selectedApplication {

                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {

                    Text("Selected Configuration")
                        .font(.headline)

                    VStack(
                        alignment: .leading,
                        spacing: 5
                    ) {

                        configurationRow(
                            title: "Device",
                            value: device.name
                        )

                        configurationRow(
                            title: "UDID",
                            value: device.udid
                        )

                        configurationRow(
                            title: "Application",
                            value: application.name
                        )

                        configurationRow(
                            title: "Bundle ID",
                            value: application.bundleID
                        )
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(
                            cornerRadius: 10
                        )
                        .fill(
                            Color.secondary.opacity(
                                0.08
                            )
                        )
                    )
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Scan Scope")
                    .font(.headline)

                Picker("Scan Scope", selection: $viewModel.scanMode) {
                    ForEach(ScanMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.isScanning)

                if viewModel.scanMode == .limited {
                    HStack {
                        Text("Stop after")
                        Picker("Pages", selection: $viewModel.maximumScreens) {
                            ForEach([1, 5, 10, 25, 50], id: \.self) { count in
                                Text("\(count) pages").tag(count)
                            }
                        }
                        .frame(width: 130)
                        Spacer()
                    }
                }

                Text(
                    viewModel.scanMode == .currentPage
                    ? "Open the desired page in the selected app before starting. AccessibilityScanner will capture and report only that page."
                    : viewModel.scanMode == .limited
                    ? "The scanner stops automatically after the selected number of discovered pages. A report is available for the completed pages."
                    : "The scanner explores the application until the configured crawl limit or until you stop it."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {

                Spacer()

                if viewModel.isScanning {
                    Button {
                        viewModel.stopScan()
                    } label: {
                        Image(systemName: "stop.fill")
                        Text("Stop Scan & Report")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else {
                    Button {
                        viewModel.startScan()

                } label: {

                    HStack(spacing: 8) {

                        if viewModel.isScanning {

                            ProgressView()
                                .controlSize(.small)

                            Text("Scanning...")
                        } else {

                            Image(
                                systemName:
                                    "play.fill"
                            )

                            Text("Start Scan")
                        }
                    }
                    .frame(
                        minWidth: 130
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(
                    viewModel.isScanning ||
                    viewModel.selectedDevice == nil ||
                    viewModel.selectedApplication == nil
                )
                }

                Spacer()
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Results Section

    private var resultsSection: some View {

        VStack(
            alignment: .leading,
            spacing: 18
        ) {

            resultsHeader

            if viewModel.isScanning {

                scanningState

            } else if viewModel.findings.isEmpty {

                if viewModel.scanResult != nil {

                    noIssuesState

                } else {

                    emptyResultsState
                }

            } else {

                findingsList
            }
        }
    }

    // MARK: - Results Header

    private var resultsHeader: some View {

        VStack(
            alignment: .leading,
            spacing: 14
        ) {

            HStack {

                Text("Scan Results")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                if viewModel.scanResult != nil {

                    Button {

                        showingReport = true

                    } label: {

                        Image(
                            systemName:
                                "doc.text.magnifyingglass"
                        )

                        Text("View Full Report")
                    }
                    .buttonStyle(.bordered)
                }

                if !viewModel.findings.isEmpty {

                    Text(
                        "\(viewModel.findings.count) issue\(viewModel.findings.count == 1 ? "" : "s") found"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            if !viewModel.findings.isEmpty {

                summaryCards
            }
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {

        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 12
        ) {

            SummaryCard(
                title: "Issues",
                value:
                    viewModel.findings.count,
                icon: "exclamationmark.triangle"
            )

            SummaryCard(
                title: "Errors",
                value:
                    viewModel.findings.filter {
                        $0.severity == .error
                    }.count,
                icon: "xmark.circle"
            )

            SummaryCard(
                title: "Warnings",
                value:
                    viewModel.findings.filter {
                        $0.severity == .warning
                    }.count,
                icon: "exclamationmark.circle"
            )

            SummaryCard(
                title: "Info",
                value:
                    viewModel.findings.filter {
                        $0.severity == .info
                    }.count,
                icon: "info.circle"
            )
        }
    }

    // MARK: - Findings List

    private var findingsList: some View {

        LazyVStack(
            alignment: .leading,
            spacing: 12
        ) {

            ForEach(
                Array(
                    viewModel.findings.enumerated()
                ),
                id: \.offset
            ) { _, finding in

                FindingCard(
                    finding: finding
                )
            }
        }
    }

    // MARK: - Scanning State

    private var scanningState: some View {

        VStack(
            alignment: .center,
            spacing: 14
        ) {

            ProgressView()
                .controlSize(.large)

            Text(viewModel.scanMode == .currentPage ? "Testing current page..." : "Scanning application...")
                .font(.headline)

            Text(
                viewModel.status
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text(
                viewModel.scanMode == .currentPage
                ? "The selected page is being tested. Stop is not required for a single-page scan."
                : "Reading the application's accessibility hierarchy and running accessibility rules. You can stop at any time; completed pages remain available in the report."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(
            maxWidth: .infinity
        )
        .padding(50)
        .background(
            RoundedRectangle(
                cornerRadius: 12
            )
            .fill(
                Color.secondary.opacity(
                    0.07
                )
            )
        )
    }

    // MARK: - Empty Results

    private var emptyResultsState: some View {

        VStack(
            alignment: .center,
            spacing: 12
        ) {

            Image(
                systemName:
                    "doc.text.magnifyingglass"
            )
            .font(
                .system(size: 36)
            )
            .foregroundStyle(.secondary)

            Text("No scan results yet")
                .font(.headline)

            Text(
                "Select a device and application, then start a scan."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(
            maxWidth: .infinity
        )
        .padding(50)
        .background(
            RoundedRectangle(
                cornerRadius: 12
            )
            .fill(
                Color.secondary.opacity(
                    0.07
                )
            )
        )
    }

    // MARK: - No Issues State

    private var noIssuesState: some View {

        VStack(
            alignment: .center,
            spacing: 12
        ) {

            Image(
                systemName:
                    "checkmark.circle"
            )
            .font(
                .system(size: 36)
            )
            .foregroundStyle(.green)

            Text(
                "No accessibility issues detected"
            )
            .font(.headline)

            Text(
                "The executed accessibility rules did not report any failures or warnings."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            if viewModel.scanResult != nil {

                Button {

                    showingReport = true

                } label: {

                    Image(
                        systemName:
                            "doc.text.magnifyingglass"
                    )

                    Text("View Full Report")
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .frame(
            maxWidth: .infinity
        )
        .padding(50)
        .background(
            RoundedRectangle(
                cornerRadius: 12
            )
            .fill(
                Color.secondary.opacity(
                    0.07
                )
            )
        )
    }

    // MARK: - Configuration Row

    private func configurationRow(
        title: String,
        value: String
    ) -> some View {

        HStack(
            alignment: .top,
            spacing: 10
        ) {

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(
                    width: 90,
                    alignment: .leading
                )

            Text(value)
                .font(.caption)
                .textSelection(
                    .enabled
                )

            Spacer()
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {

        HStack(spacing: 8) {

            Circle()
                .fill(
                    viewModel.isScanning
                    ? Color.orange
                    : Color.green
                )
                .frame(
                    width: 8,
                    height: 8
                )

            Text(
                viewModel.status
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            if let report =
                viewModel.scanResult {

                Text(
                    "\(report.totalElementsTested) elements • \(report.rulesExecuted) rules"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(
            .horizontal,
            16
        )
        .padding(
            .vertical,
            10
        )
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
