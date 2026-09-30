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
    private let maximumSnapshotAttempts = 3

 
    private let initialUISettleDelayNanoseconds: UInt64 =
        500_000_000

    /// Delay between unstable snapshot attempts.
    private let snapshotRetryDelayNanoseconds: UInt64 =
        350_000_000

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
        
        self.isScanning = true

            defer {
                self.isScanning = false
            }
        let startedAt = Date()

        do {
            status = "Connecting to Appium..."

            let configuration = ScannerConfiguration(
                appiumURL: appiumURL,
                bundleID: application.bundleID,
                deviceName: device.name,
                udid: device.udid
            )

            let appium = AppiumClient(baseURL: configuration.appiumURL)
            status = "Creating Appium session..."

            _ = try await appium.createSession(configuration: configuration)

            try await Task.sleep(for: .milliseconds(500))
            status = "Reading initial accessibility hierarchy..."

            let initialSnapshot = try await captureStableSnapshot(
                appium: appium
            )

            let scanner = AccessibilityScanner()


            status = "Crawling application..."

            let crawler = AppCrawler(
                appium: appium,
                scanner: scanner
            )

            let crawledScreens = try await crawler.crawl(
                initialSnapshot: initialSnapshot
            ) { message in

                Task { @MainActor in
                    self.status = message
                }

            }

            status = "Building accessibility report..."

            var screenResults: [ScreenScanResult] = []

            for crawledScreen in crawledScreens {

                let elementCount = countNodes(
                    crawledScreen.rootNode
                )
                
                let screenshotContext = AccessibilityRuleContext(
                    screenshotData: crawledScreen.screenshotData,
                    screenshotWidth: crawledScreen.screenshotWidth,
                    screenshotHeight: crawledScreen.screenshotHeight,
                    hierarchyWidth: crawledScreen.rootNode.frame.width,
                    hierarchyHeight: crawledScreen.rootNode.frame.height
                )

                let contextualEvaluations = scanner.evaluateForReport(
                    rootNode: crawledScreen.rootNode,
                    context: screenshotContext
                )

                let evaluations = mergeEvaluations(
                    crawledScreen.evaluations,
                    contextualEvaluations
                )
                let screenshotEvaluations = mergeEvaluations(
                    crawledScreen.screenshotEvaluations,
                    contextualEvaluations
                )

                let annotations = ScreenshotAnnotation.makeAnnotations(
                    from: screenshotEvaluations
                )

                let annotatedImageData =
                    ScreenshotAnnotator().annotate(
                        imageData: crawledScreen.screenshotData,
                        screenshotWidth: crawledScreen.screenshotWidth,
                        screenshotHeight: crawledScreen.screenshotHeight,
                        hierarchyWidth: crawledScreen.rootNode.frame.width,
                        hierarchyHeight: crawledScreen.rootNode.frame.height,
                        evaluations: screenshotEvaluations
                    )

                let screenResult = ScreenScanResult(
                    name: "Screen \(screenResults.count + 1)",
                    elementCount: elementCount,
                    evaluations: evaluations,
                    screenshot: ScanScreenshot(
                        imageData: crawledScreen.screenshotData,
                        annotatedImageData: annotatedImageData,
                        width: crawledScreen.screenshotWidth,
                        height: crawledScreen.screenshotHeight,
                        hierarchyWidth: crawledScreen.rootNode.frame.width,
                        hierarchyHeight: crawledScreen.rootNode.frame.height
                    ),
                    annotations: annotations
                )

                screenResults.append(screenResult)
            }

            let finishedAt = Date()

            let result = AccessibilityScanResult(
                applicationName: application.name,
                bundleID: application.bundleID,
                deviceName: device.name,
                deviceUDID: device.udid,
                startedAt: startedAt,
                finishedAt: finishedAt,
                screens: screenResults,
                rulesExecuted: AccessibilityRules.all.count
            )

            self.scanResult = result

            self.findings = result.allEvaluations
                .filter {
                    $0.status == .fail ||
                    $0.status == .warning
                }
                .map {
                    AccessibilityFinding(
                        ruleID: $0.ruleID,
                        severity: $0.severity,
                        message: $0.message,
                        elementType: $0.elementType,
                        elementLabel: $0.elementLabel,
                        identifier: $0.identifier,
                        value: $0.value,
                        frame: $0.frame,
                        remediation: $0.remediation
                    )
                }

            status = """
            Scan complete — \(screenResults.count) screens discovered
            """
            
            print("Screens: \(screenResults.count)")
            print("Elements: \(result.totalElementsTested)")
            print("Failures: \(result.totalFailures)")
            print("Warnings: \(result.totalWarnings)")
            print("Validations: \(result.totalValidations)")
            print("Passes: \(result.totalPasses)")


            try? await appium.deleteSession()

        } catch {
            
            status = "Scan failed"
            errorMessage = error.localizedDescription
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

            let sourceBefore =
                try await appium.getSource()

            let parserBefore =
                WDAElementParser()

            let rootBefore =
                try parserBefore.parse(
                    sourceBefore
                )


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

                Attempt:
                    \(attempt)

                Screenshot:
                    \(screenshotWidth) × \(screenshotHeight)

                Hierarchy:
                    \(rootBefore.frame.width) × \(rootBefore.frame.height)

                Result:
                    STABLE
                """)

                return StableScanSnapshot(
                    rootNode: rootBefore,
                    screenshotData: screenshotData,
                    screenshotWidth: screenshotWidth,
                    screenshotHeight: screenshotHeight
                )
            }

            print("""

            Attempt:
                \(attempt)

            Result:
                UI hierarchy changed between
                screenshot boundaries.

            Before hierarchy:
                \(rootBefore.frame.width) × \(rootBefore.frame.height)

            After hierarchy:
                \(rootAfter.frame.width) × \(rootAfter.frame.height)
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
    
    private func mergeEvaluations(
        _ base: [AccessibilityRuleEvaluation],
        _ additions: [AccessibilityRuleEvaluation]
    ) -> [AccessibilityRuleEvaluation] {
        var replacementByKey: [String: AccessibilityRuleEvaluation] = [:]
        for evaluation in additions {
            replacementByKey[evaluationKey(evaluation)] = evaluation
        }

        var result: [AccessibilityRuleEvaluation] = []
        var consumed = Set<String>()

        for evaluation in base {
            let key = evaluationKey(evaluation)
            if let replacement = replacementByKey[key] {
                result.append(replacement)
                consumed.insert(key)
            } else {
                result.append(evaluation)
            }
        }

        for evaluation in additions {
            let key = evaluationKey(evaluation)
            if !consumed.contains(key) && !base.contains(where: { evaluationKey($0) == key }) {
                result.append(evaluation)
                consumed.insert(key)
            }
        }

        return result
    }

    private func evaluationKey(
        _ evaluation: AccessibilityRuleEvaluation
    ) -> String {
        [
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

    private func countNodes(
        _ node: AccessibilityNode
    ) -> Int {

        if node.identifier == "A11YScannerIgnore" {
            return 0
        }

        return 1 + node.children.reduce(0) {
            $0 + countNodes($1)
        }
    }
}

// MARK: - Stable Scan Snapshot

struct StableScanSnapshot {
    let rootNode: AccessibilityNode
    let screenshotData: Data
    let screenshotWidth: Double
    let screenshotHeight: Double
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
