//
//  ScannerViewModel.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 22/09/26.
//

import Foundation
import SwiftUI
import Combine
import AppKit

@MainActor
final class ScannerViewModel: ObservableObject {

    // MARK: - Devices

    @Published var devices: [Device] = []
    @Published var selectedDevice: Device?
    @Published var isLoadingDevices: Bool = false

    // MARK: - Applications

    @Published var applications: [InstalledApp] = []
    @Published var selectedApplication: InstalledApp?
    @Published var isLoadingApplications: Bool = false

    // MARK: - Scan State

    @Published var status: String = "Ready"
    @Published var isScanning: Bool = false
    @Published var findings: [AccessibilityFinding] = []
    @Published var scanResult: AccessibilityScanResult?
    @Published var errorMessage: String?

    // MARK: - Appium

    private let appiumURL = URL(
        string: "http://127.0.0.1:4723"
    )!

    // MARK: - Stable Snapshot Configuration

    /// Number of attempts allowed when the UI hierarchy changes
    /// while the screenshot is being captured.
    private let maximumSnapshotAttempts = 3

    /// Small delay allowing the target application's UI to settle
    /// before beginning a snapshot.
    private let initialUISettleDelayNanoseconds: UInt64 =
        500_000_000

    /// Delay between unstable snapshot attempts.
    private let snapshotRetryDelayNanoseconds: UInt64 =
        350_000_000

    // MARK: - Stable Scan Snapshot

    private struct StableScanSnapshot {
        let rootNode: AccessibilityNode
        let screenshotData: Data
        let screenshotWidth: Double
        let screenshotHeight: Double
    }

    // MARK: - Device Discovery

    func loadDevices() {

        isLoadingDevices = true
        errorMessage = nil

        Task {

            do {

                let discoveredDevices =
                    try await discoverDevices()

                devices = discoveredDevices

                if let bootedDevice =
                    discoveredDevices.first(
                        where: {
                            $0.state == "Booted"
                        }
                    ) {

                    selectedDevice = bootedDevice

                } else if let connectedDevice =
                            discoveredDevices.first(
                                where: {
                                    $0.state == "Connected"
                                }
                            ) {

                    selectedDevice = connectedDevice

                } else if let firstDevice =
                            discoveredDevices.first {

                    selectedDevice = firstDevice
                }

                isLoadingDevices = false

                if let device = selectedDevice {

                    await loadApplications(
                        for: device
                    )
                }

            } catch {

                isLoadingDevices = false

                errorMessage =
                    error.localizedDescription
            }
        }
    }

    private func discoverDevices()
        async throws -> [Device] {

        try await Task.detached {

            let service =
                await DeviceDiscoveryService()

            return try await service.discoverDevices()

        }.value
    }

    // MARK: - Device Changed

    func deviceChanged() {

        guard let device = selectedDevice else {

            applications = []
            selectedApplication = nil

            return
        }

        applications = []
        selectedApplication = nil

        Task {

            await loadApplications(
                for: device
            )
        }
    }

    // MARK: - Application Discovery

    func loadApplications(
        for device: Device
    ) async {

        isLoadingApplications = true
        errorMessage = nil

        do {

            let discoveredApps =
                try await discoverApplications(
                    for: device
                )

            applications = discoveredApps

            if let firstApp =
                discoveredApps.first {

                selectedApplication = firstApp
            }

            isLoadingApplications = false

        } catch {

            applications = []
            selectedApplication = nil
            isLoadingApplications = false

            errorMessage =
                error.localizedDescription
        }
    }

    private func discoverApplications(
        for device: Device
    ) async throws -> [InstalledApp] {

        try await Task.detached {

            let service =
                await AppDiscoveryService()

            return try await service.discoverApps(
                for: device
            )

        }.value
    }

    // MARK: - Refresh

    func refresh() {

        applications = []
        selectedApplication = nil
        scanResult = nil
        findings = []
        errorMessage = nil

        loadDevices()
    }

    // MARK: - Start Scan

    func startScan() {

        guard let device = selectedDevice else {

            errorMessage =
                "Please select a device."

            return
        }

        guard let application = selectedApplication else {

            errorMessage =
                "Please select an application."

            return
        }

        errorMessage = nil
        findings = []
        scanResult = nil

        isScanning = true

        status =
            "Connecting to Appium..."

        Task {

            await performScan(
                device: device,
                application: application
            )
        }
    }

    // MARK: - Perform Scan

    private func performScan(
        device: Device,
        application: InstalledApp
    ) async {

        let configuration =
            ScannerConfiguration(
                appiumURL: appiumURL,
                bundleID: application.bundleID,
                deviceName: device.name,
                udid: device.udid
            )

        let appium =
            AppiumClient(
                baseURL:
                    configuration.appiumURL
            )

        let scanStartedAt = Date()

        do {

            // -------------------------------------------------
            // 1. Create Appium session
            // -------------------------------------------------

            status =
                "Creating Appium session..."

            _ = try await appium.createSession(
                configuration: configuration
            )

            // -------------------------------------------------
            // 2. Allow target UI to settle
            // -------------------------------------------------

            status =
                "Waiting for application UI to settle..."

            try await Task.sleep(
                nanoseconds:
                    initialUISettleDelayNanoseconds
            )

            // -------------------------------------------------
            // 3. Capture a stable hierarchy + screenshot
            // -------------------------------------------------

            status =
                "Synchronizing screenshot and UI hierarchy..."

            let stableSnapshot =
                try await captureStableSnapshot(
                    appium: appium
                )

            let rootNode =
                stableSnapshot.rootNode

            let screenshotData =
                stableSnapshot.screenshotData

            let screenshotWidth =
                stableSnapshot.screenshotWidth

            let screenshotHeight =
                stableSnapshot.screenshotHeight

            // -------------------------------------------------
            // 4. Evaluate accessibility rules
            // -------------------------------------------------

            status =
                "Running accessibility checks..."

            let scanner =
                AccessibilityScanner()

            let evaluations =
                scanner.evaluateForReport(
                    rootNode: rootNode
                )

            // -------------------------------------------------
            // 5. Create screenshot annotations
            // -------------------------------------------------

            status =
                "Annotating accessibility issues..."

            let issueEvaluations =
                evaluations.filter {

                    $0.status == .fail ||
                    $0.status == .warning ||
                    $0.status == .validate
                }

            let annotations =
                issueEvaluations.enumerated().map {
                    index,
                    evaluation in

                    ScreenshotAnnotation(
                        number: index + 1,
                        evaluation: evaluation
                    )
                }

            // -------------------------------------------------
            // 6. Annotate screenshot
            // -------------------------------------------------

            status =
                "Drawing accessibility annotations..."

            let annotator =
                ScreenshotAnnotator()

            let annotatedImageData =
                annotator.annotate(
                    imageData: screenshotData,
                    screenshotWidth: screenshotWidth,
                    screenshotHeight: screenshotHeight,
                    hierarchyWidth: rootNode.frame.width,
                    hierarchyHeight: rootNode.frame.height,
                    evaluations: evaluations
                )

            let screenshot =
                ScanScreenshot(
                    imageData: screenshotData,
                    annotatedImageData:
                        annotatedImageData,
                    width: screenshotWidth,
                    height: screenshotHeight
                )

            // -------------------------------------------------
            // 7. Create findings
            // -------------------------------------------------

            let scanFindings =
                evaluations.compactMap {
                    evaluation
                    -> AccessibilityFinding? in

                    guard
                        evaluation.status == .fail ||
                        evaluation.status == .warning
                    else {
                        return nil
                    }

                    return AccessibilityFinding(
                        ruleID:
                            evaluation.ruleID,

                        severity:
                            evaluation.severity,

                        message:
                            evaluation.message,

                        elementType:
                            evaluation.elementType,

                        elementLabel:
                            evaluation.elementLabel,

                        identifier:
                            evaluation.identifier,

                        value:
                            evaluation.value,

                        frame:
                            evaluation.frame,

                        remediation:
                            evaluation.remediation
                    )
                }

            findings = scanFindings

            // -------------------------------------------------
            // 8. Build accessibility report
            // -------------------------------------------------

            status =
                "Building accessibility report..."

            let report =
                scanner.scanReport(
                    rootNode: rootNode,

                    applicationName:
                        application.name,

                    bundleID:
                        application.bundleID,

                    deviceName:
                        device.name,

                    deviceUDID:
                        device.udid,

                    screenshot:
                        screenshot,

                    annotations:
                        annotations
                )

            scanResult = report

            // -------------------------------------------------
            // 9. Finish
            // -------------------------------------------------

            let elapsed =
                Date().timeIntervalSince(
                    scanStartedAt
                )

            status =
                String(
                    format:
                        "Scan complete — %.1f seconds",
                    elapsed
                )

            isScanning = false

            try? await appium.deleteSession()

        } catch {

            // Always try to close Appium session.

            try? await appium.deleteSession()

            errorMessage =
                error.localizedDescription

            status =
                "Scan failed"

            isScanning = false
        }
    }

    // MARK: - Stable Snapshot Capture

    private func captureStableSnapshot(
        appium: AppiumClient
    ) async throws -> StableScanSnapshot {

        for attempt in 1...maximumSnapshotAttempts {

            status =
                "Synchronizing UI state " +
                "\(attempt)/\(maximumSnapshotAttempts)..."

            // -------------------------------------------------
            // A. Read hierarchy BEFORE screenshot
            // -------------------------------------------------

            let sourceBefore =
                try await appium.getSource()

            let parserBefore =
                WDAElementParser()

            let rootBefore =
                try parserBefore.parse(
                    sourceBefore
                )

            // -------------------------------------------------
            // B. Capture screenshot immediately
            // -------------------------------------------------

            status =
                "Capturing synchronized screenshot..."

            let screenshotData =
                try await appium.getScreenshot()

            guard let image =
                    NSImage(
                        data: screenshotData
                    )
            else {

                throw ScannerViewModelError
                    .invalidScreenshot
            }

            let screenshotWidth =
                image.size.width

            let screenshotHeight =
                image.size.height

            guard
                screenshotWidth > 0,
                screenshotHeight > 0
            else {

                throw ScannerViewModelError
                    .invalidScreenshot
            }

            // -------------------------------------------------
            // C. Read hierarchy AFTER screenshot
            // -------------------------------------------------

            status =
                "Verifying UI stability..."

            let sourceAfter =
                try await appium.getSource()

            let parserAfter =
                WDAElementParser()

            let rootAfter =
                try parserAfter.parse(
                    sourceAfter
                )

            // -------------------------------------------------
            // D. Compare hierarchy before/after screenshot
            // -------------------------------------------------

            let beforeSignature =
                hierarchySignature(
                    rootBefore
                )

            let afterSignature =
                hierarchySignature(
                    rootAfter
                )

            if beforeSignature == afterSignature {

                print("""
                ==========================================
                STABLE UI SNAPSHOT
                ==========================================

                Attempt:
                    \(attempt)

                Screenshot:
                    \(screenshotWidth) × \(screenshotHeight)

                Hierarchy:
                    \(rootBefore.frame.width) × \(rootBefore.frame.height)

                Result:
                    STABLE

                ==========================================
                """)

                return StableScanSnapshot(
                    rootNode: rootBefore,
                    screenshotData: screenshotData,
                    screenshotWidth: screenshotWidth,
                    screenshotHeight: screenshotHeight
                )
            }

            // -------------------------------------------------
            // E. UI changed while capturing snapshot
            // -------------------------------------------------

            print("""
            ==========================================
            UNSTABLE UI SNAPSHOT
            ==========================================

            Attempt:
                \(attempt)

            Result:
                UI hierarchy changed between
                screenshot boundaries.

            Before hierarchy:
                \(rootBefore.frame.width) × \(rootBefore.frame.height)

            After hierarchy:
                \(rootAfter.frame.width) × \(rootAfter.frame.height)

            ==========================================
            """)

            if attempt < maximumSnapshotAttempts {

                status =
                    "UI changed — retrying synchronization..."

                try await Task.sleep(
                    nanoseconds:
                        snapshotRetryDelayNanoseconds
                )
            }
        }

        throw ScannerViewModelError
            .unstableUI
    }

    // MARK: - Hierarchy Signature

    /// Creates a deterministic representation of the
    /// accessibility hierarchy.
    ///
    /// We intentionally include the properties that matter
    /// to accessibility scanning and screenshot coordinates.
    ///
    /// If this signature is identical before and after the
    /// screenshot call, the hierarchy was stable across the
    /// screenshot operation.
    private func hierarchySignature(
        _ node: AccessibilityNode
    ) -> String {

        var result = ""

        result += node.type
        result += "|"

        result += node.identifier
        result += "|"

        result += node.label
        result += "|"

        result += node.value ?? ""
        result += "|"

        result += node.placeholderValue ?? ""
        result += "|"

        result += node.traits
        result += "|"

        result += String(
            format: "%.2f",
            node.frame.origin.x
        )
        result += "|"

        result += String(
            format: "%.2f",
            node.frame.origin.y
        )
        result += "|"

        result += String(
            format: "%.2f",
            node.frame.width
        )
        result += "|"

        result += String(
            format: "%.2f",
            node.frame.height
        )
        result += "|"

        result += node.exists
            ? "exists=1|"
            : "exists=0|"

        result += node.hittable
            ? "hittable=1|"
            : "hittable=0|"

        result += node.enabled
            ? "enabled=1|"
            : "enabled=0|"

        result += node.visible
            ? "visible=1|"
            : "visible=0|"

        result += node.accessible
            ? "accessible=1|"
            : "accessible=0|"

        result += "children=\(node.children.count)|"

        for child in node.children {

            result += hierarchySignature(
                child
            )
        }

        return result
    }
}

// MARK: - Errors

private enum ScannerViewModelError:
    Error,
    LocalizedError {

    case invalidScreenshot
    case unstableUI

    var errorDescription: String? {

        switch self {

        case .invalidScreenshot:

            return
                "Appium returned screenshot data that could not be decoded as an image."

        case .unstableUI:

            return
                "The application's UI changed while the screenshot and accessibility hierarchy were being synchronized. Please try the scan again."
        }
    }
}
