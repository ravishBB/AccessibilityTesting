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

enum ScanMode: String, CaseIterable, Identifiable {
    case fullApp = "Full App"
    case currentPage = "Current Page"
    case limited = "Stop After N Pages"

    var id: String { rawValue }
}

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
    @Published var scanMode: ScanMode = .fullApp
    @Published var maximumScreens: Int = 10
    @Published private(set) var partialScreenCount: Int = 0

    private var scanTask: Task<Void, Never>?
    private var partialCrawledScreens: [CrawledScreen] = []

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

    // MARK: - Stop Scan

    func stopScan() {
        guard isScanning else { return }

        status = "Stopping scan and preparing partial report..."
        scanTask?.cancel()
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
        partialCrawledScreens = []
        partialScreenCount = 0

        status =
            scanMode == .currentPage
            ? "Preparing current-page scan..."
            : "Connecting to Appium..."

        let selectedMode = scanMode
        let selectedMaximumScreens = maximumScreens

        scanTask = Task {
            await performScan(
                device: device,
                application: application,
                mode: selectedMode,
                maximumScreens: selectedMaximumScreens
            )
        }
    }

    // MARK: - Perform Scan
    private func performScan(
        device: Device,
        application: InstalledApp,
        mode: ScanMode,
        maximumScreens: Int
    ) async {
        
        self.isScanning = true

            defer {
                self.isScanning = false
                self.scanTask = nil
            }
        let startedAt = Date()
        var activeAppium: AppiumClient?

        // Always release an Appium session, including when crawling, parsing,
        // reporting, or screenshot processing fails midway through a scan.
        defer {
            if let appium = activeAppium {
                Task {
                    try? await appium.deleteSession()
                }
            }
        }

        do {
            try Task.checkCancellation()
            status = "Connecting to Appium..."

            var appActivity: String?

            if device.platform == .android {
                let package = application.bundleID
                let serial = device.udid

                appActivity = await Task.detached {
                    AndroidDeviceService().launchableActivity(
                        package: package,
                        serial: serial
                    )
                }.value
            }

            let configuration = ScannerConfiguration(
                appiumURL: appiumURL,
                bundleID: application.bundleID,
                deviceName: device.name,
                udid: device.udid,
                platform: device.platform,
                appActivity: appActivity,
                displayDensity: device.displayDensity,
                autoLaunch: mode != .currentPage
            )

            let appium = AppiumClient(baseURL: configuration.appiumURL)
            activeAppium = appium
            status = "Creating Appium session..."

            _ = try await appium.createSession(configuration: configuration)
            try Task.checkCancellation()

            // Full/limited scans intentionally launch the selected app.
            // Current Page mode attaches without replacing the page the tester
            // has already opened in the app.
            if mode != .currentPage {
                status = "Launching application..."
                await appium.activateApp(bundleID: application.bundleID)
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(1000))
            } else {
                status = "Capturing current page..."
                try await Task.sleep(for: .milliseconds(300))
            }
            status = "Reading initial accessibility hierarchy..."

            let initialSnapshot = try await captureStableSnapshot(
                appium: appium
            )

            let scanner = AccessibilityScanner()


            status = "Crawling application..."

            let crawlerLimit: Int
            switch mode {
            case .currentPage:
                crawlerLimit = 1
            case .limited:
                crawlerLimit = max(1, maximumScreens)
            case .fullApp:
                crawlerLimit = 100
            }

            let crawler = AppCrawler(
                appium: appium,
                scanner: scanner,
                configuration: AppCrawlerConfiguration(
                    maximumScreens: crawlerLimit,
                    maximumDepth: 20,
                    maximumActionsPerScreen: 30,
                    settleDelayNanoseconds: 500_000_000
                )
            )

            let crawledScreens = try await crawler.crawl(
                initialSnapshot: initialSnapshot,
                statusHandler: { message in
                    Task { @MainActor in
                        self.status = message
                    }
                },
                screenHandler: { screen in
                    self.partialCrawledScreens.append(screen)
                    self.partialScreenCount = self.partialCrawledScreens.count
                }
            )

            status = "Running responsive accessibility checks..."

            let responsiveResult = await runResponsiveAccessibilityCheck(
                appium: appium,
                scanner: scanner
            )

            status = "Building accessibility report..."

            var screenResults: [ScreenScanResult] = []

            for crawledScreen in crawledScreens {

                try Task.checkCancellation()

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

                // Build screenshot evidence for every unique viewport discovered
                // while scrolling this screen. This fixes two report problems: the
                // top screenshot being repeated and newly revealed scroll content
                // having no screenshot evidence.
                var viewportScreenshots: [ScreenshotViewport] = []
                var viewportEvaluations: [AccessibilityRuleEvaluation] = []

                for (viewportIndex, capture) in crawledScreen.viewportCaptures.enumerated() {
                    let viewportContext = AccessibilityRuleContext(
                        screenshotData: capture.snapshot.screenshotData,
                        screenshotWidth: capture.snapshot.screenshotWidth,
                        screenshotHeight: capture.snapshot.screenshotHeight,
                        hierarchyWidth: capture.snapshot.rootNode.frame.width,
                        hierarchyHeight: capture.snapshot.rootNode.frame.height
                    )

                    let contextualEvaluations = scanner.evaluateForReport(
                        rootNode: capture.snapshot.rootNode,
                        context: viewportContext
                    )

                    let evaluations = mergeEvaluations(
                        capture.evaluations,
                        contextualEvaluations
                    )
                    viewportEvaluations.append(contentsOf: evaluations)

                    let annotations = ScreenshotAnnotation.makeAnnotations(
                        from: evaluations
                    )

                    let annotatedImageData = ScreenshotAnnotator().annotate(
                        imageData: capture.snapshot.screenshotData,
                        screenshotWidth: capture.snapshot.screenshotWidth,
                        screenshotHeight: capture.snapshot.screenshotHeight,
                        hierarchyWidth: capture.snapshot.rootNode.frame.width,
                        hierarchyHeight: capture.snapshot.rootNode.frame.height,
                        evaluations: evaluations
                    )

                    viewportScreenshots.append(
                        ScreenshotViewport(
                            index: viewportIndex + 1,
                            screenshot: ScanScreenshot(
                                imageData: capture.snapshot.screenshotData,
                                annotatedImageData: annotatedImageData,
                                width: capture.snapshot.screenshotWidth,
                                height: capture.snapshot.screenshotHeight,
                                hierarchyWidth: capture.snapshot.rootNode.frame.width,
                                hierarchyHeight: capture.snapshot.rootNode.frame.height
                            ),
                            annotations: annotations
                        )
                    )
                }

                // Defensive fallback for screens that were captured before the
                // viewport capture path existed.
                if viewportScreenshots.isEmpty {
                    let contextualEvaluations = scanner.evaluateForReport(
                        rootNode: crawledScreen.rootNode,
                        context: screenshotContext
                    )
                    viewportEvaluations.append(contentsOf: contextualEvaluations)

                    let annotations = ScreenshotAnnotation.makeAnnotations(
                        from: contextualEvaluations
                    )
                    let annotatedImageData = ScreenshotAnnotator().annotate(
                        imageData: crawledScreen.screenshotData,
                        screenshotWidth: crawledScreen.screenshotWidth,
                        screenshotHeight: crawledScreen.screenshotHeight,
                        hierarchyWidth: crawledScreen.rootNode.frame.width,
                        hierarchyHeight: crawledScreen.rootNode.frame.height,
                        evaluations: contextualEvaluations
                    )

                    viewportScreenshots.append(
                        ScreenshotViewport(
                            index: 1,
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
                    )
                }

                var nextAnnotationNumber = 1
                var normalizedViewports: [ScreenshotViewport] = []
                var allAnnotations: [ScreenshotAnnotation] = []

                for viewport in viewportScreenshots {
                    let normalizedAnnotations = viewport.annotations.map { annotation -> ScreenshotAnnotation in
                        let normalized = annotation.renumbered(nextAnnotationNumber)
                        nextAnnotationNumber += 1
                        allAnnotations.append(normalized)
                        return normalized
                    }

                    normalizedViewports.append(
                        ScreenshotViewport(
                            index: viewport.index,
                            screenshot: viewport.screenshot,
                            annotations: normalizedAnnotations
                        )
                    )
                }

                let evaluations = mergeEvaluations(
                    mergeEvaluations(
                        crawledScreen.evaluations,
                        viewportEvaluations
                    ),
                    crawledScreen.keyboardFocusEvaluations
                )

                let primaryScreenshot = normalizedViewports.first?.screenshot
                    ?? ScanScreenshot(
                        imageData: crawledScreen.screenshotData,
                        width: crawledScreen.screenshotWidth,
                        height: crawledScreen.screenshotHeight,
                        hierarchyWidth: crawledScreen.rootNode.frame.width,
                        hierarchyHeight: crawledScreen.rootNode.frame.height
                    )

                let screenResult = ScreenScanResult(
                    name: "Screen \(screenResults.count + 1)",
                    signature: crawledScreen.signature,
                    elementCount: elementCount,
                    evaluations: evaluations,
                    transitions: crawledScreen.transitions,
                    screenshot: primaryScreenshot,
                    annotations: allAnnotations,
                    viewportScreenshots: normalizedViewports
                )

                screenResults.append(screenResult)
            }

            let finishedAt = Date()

            let draftResult = AccessibilityScanResult(
                applicationName: application.name,
                bundleID: application.bundleID,
                deviceName: device.name,
                deviceUDID: device.udid,
                startedAt: startedAt,
                finishedAt: finishedAt,
                screens: screenResults,
                rulesExecuted: AccessibilityRules.all.count
            )

            let integrityIssues = AccessibilityReportIntegrity.validate(draftResult)
            guard integrityIssues.isEmpty else {
                let details = integrityIssues.map(\.message).joined(separator: " ")
                throw ScannerViewModelError.reportIntegrityFailure(details)
            }

            status = "Building accessibility intelligence..."

            let baseline = AccessibilityRegressionStore.shared.load(
                bundleID: application.bundleID
            )

            let intelligence = AccessibilityIntelligenceEngine.analyze(
                report: draftResult,
                baseline: baseline,
                responsive: responsiveResult
            )

            let result = draftResult.settingIntelligence(intelligence)

            // Store the completed scan as the baseline for the next scan of
            // this application. The current report retains the comparison
            // result calculated against the previous baseline.
            AccessibilityRegressionStore.shared.save(report: result)

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


        } catch {
            
            if Task.isCancelled {
                if !partialCrawledScreens.isEmpty {
                    let partial = makePartialReport(
                        crawledScreens: partialCrawledScreens,
                        application: application,
                        device: device,
                        startedAt: startedAt,
                        scanner: AccessibilityScanner()
                    )
                    scanResult = partial
                    findings = partial.allEvaluations
                        .filter { $0.status == .fail || $0.status == .warning }
                        .map { evaluation in
                            AccessibilityFinding(
                                ruleID: evaluation.ruleID,
                                severity: evaluation.severity,
                                message: evaluation.message,
                                elementType: evaluation.elementType,
                                elementLabel: evaluation.elementLabel,
                                identifier: evaluation.identifier,
                                value: evaluation.value,
                                frame: evaluation.frame,
                                remediation: evaluation.remediation
                            )
                        }
                    status = "Scan stopped — partial report ready (\(partial.screens.count) page(s))"
                    errorMessage = "The scan was stopped. The report contains the pages completed before stopping."
                } else {
                    status = "Scan stopped"
                    errorMessage = "The scan was stopped before a page was completed."
                }
            } else {
                status = "Scan failed"
                errorMessage = userFacingScanError(error)
            }
        }
    }

    private func makePartialReport(
        crawledScreens: [CrawledScreen],
        application: InstalledApp,
        device: Device,
        startedAt: Date,
        scanner: AccessibilityScanner
    ) -> AccessibilityScanResult {
        let screenResults: [ScreenScanResult] = crawledScreens.enumerated().map { index, screen in
            let context = AccessibilityRuleContext(
                screenshotData: screen.screenshotData,
                screenshotWidth: screen.screenshotWidth,
                screenshotHeight: screen.screenshotHeight,
                hierarchyWidth: screen.rootNode.frame.width,
                hierarchyHeight: screen.rootNode.frame.height
            )
            let contextual = scanner.evaluateForReport(rootNode: screen.rootNode, context: context)
            let evaluations = mergeEvaluations(
                mergeEvaluations(screen.evaluations, contextual),
                screen.keyboardFocusEvaluations
            )
            let annotations = ScreenshotAnnotation.makeAnnotations(from: evaluations)
            let annotated = ScreenshotAnnotator().annotate(
                imageData: screen.screenshotData,
                screenshotWidth: screen.screenshotWidth,
                screenshotHeight: screen.screenshotHeight,
                hierarchyWidth: screen.rootNode.frame.width,
                hierarchyHeight: screen.rootNode.frame.height,
                evaluations: evaluations
            )
            let screenshot = ScanScreenshot(
                imageData: screen.screenshotData,
                annotatedImageData: annotated,
                width: screen.screenshotWidth,
                height: screen.screenshotHeight,
                hierarchyWidth: screen.rootNode.frame.width,
                hierarchyHeight: screen.rootNode.frame.height
            )
            let viewport = ScreenshotViewport(
                index: 1,
                screenshot: screenshot,
                annotations: annotations
            )
            return ScreenScanResult(
                name: "Screen \(index + 1)",
                signature: screen.signature,
                elementCount: countNodes(screen.rootNode),
                evaluations: evaluations,
                transitions: screen.transitions,
                screenshot: screenshot,
                annotations: annotations,
                viewportScreenshots: [viewport]
            )
        }

        return AccessibilityScanResult(
            applicationName: application.name,
            bundleID: application.bundleID,
            deviceName: device.name,
            deviceUDID: device.udid,
            startedAt: startedAt,
            finishedAt: Date(),
            screens: screenResults,
            rulesExecuted: AccessibilityRules.all.count
        )
    }

    private func userFacingScanError(_ error: Error) -> String {
        if let appiumError = error as? AppiumError {
            return appiumError.errorDescription ?? "Appium could not complete the scan."
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .networkConnectionLost, .timedOut:
                return "AccessibilityScanner could not communicate with Appium. Verify that the Appium server is running (with WebDriverAgent for iOS or UiAutomator2 for Android), then try again."
            default:
                return urlError.localizedDescription
            }
        }

        return error.localizedDescription
    }

    // MARK: - Responsive Accessibility Checks

    private func runResponsiveAccessibilityCheck(
        appium: AppiumClient,
        scanner: AccessibilityScanner
    ) async -> ResponsiveAccessibilityResult {
        var originalOrientation: String?
        do {
            originalOrientation = try await appium.getOrientation()
            guard let originalOrientation else { throw AppiumError.invalidResponse }
            let landscape = "LANDSCAPE"

            // The scan has already completed its crawl. This is deliberately a
            // runtime smoke test of the current app state so the crawler does
            // not need to be redesigned or replayed in a second orientation.
            try await appium.setOrientation(landscape)
            try await Task.sleep(for: .milliseconds(700))

            let source = try await appium.getSource()
            let root = try appium.makeParser().parse(source)
            let screenshotData = try await appium.getScreenshot()

            guard let image = NSImage(data: screenshotData) else {
                try? await appium.setOrientation(originalOrientation)
                return ResponsiveAccessibilityResult(
                    tested: true,
                    originalOrientation: originalOrientation,
                    testedOrientation: landscape,
                    orientationChanged: originalOrientation != landscape,
                    landscapeElementCount: countNodes(root),
                    landscapeFailureCount: 0,
                    landscapeWarningCount: 0,
                    landscapeValidationCount: 0,
                    landscapeScreenshotCaptured: false,
                    dynamicTypeValidationCount: 0,
                    dynamicTypeFailureCount: 0,
                    status: .validate,
                    note: "Landscape UI was reached, but the runtime screenshot could not be decoded."
                )
            }

            let evaluations = scanner.evaluateForReport(
                rootNode: root,
                context: AccessibilityRuleContext(
                    screenshotData: screenshotData,
                    screenshotWidth: image.size.width,
                    screenshotHeight: image.size.height,
                    hierarchyWidth: root.frame.width,
                    hierarchyHeight: root.frame.height
                )
            )

            let failures = evaluations.filter { $0.status == .fail }.count
            let warnings = evaluations.filter { $0.status == .warning }.count
            let validations = evaluations.filter { $0.status == .validate }.count

            let dynamicTypeEvaluations = evaluations.filter {
                $0.ruleID == "text-resize" || $0.ruleID == "text-clipping"
            }
            let dynamicTypeFailures = dynamicTypeEvaluations.filter { $0.status == .fail }.count
            let dynamicTypeValidations = dynamicTypeEvaluations.filter { $0.status == .validate }.count

            let status: IntelligenceStatus
            if failures > 0 {
                status = .fail
            } else if warnings > 0 {
                status = .warning
            } else if validations > 0 || dynamicTypeValidations > 0 {
                status = .validate
            } else {
                status = .pass
            }

            try? await appium.setOrientation(originalOrientation)

            return ResponsiveAccessibilityResult(
                tested: true,
                originalOrientation: originalOrientation,
                testedOrientation: landscape,
                orientationChanged: originalOrientation != landscape,
                landscapeElementCount: countNodes(root),
                landscapeFailureCount: failures,
                landscapeWarningCount: warnings,
                landscapeValidationCount: validations,
                landscapeScreenshotCaptured: true,
                dynamicTypeValidationCount: dynamicTypeValidations,
                dynamicTypeFailureCount: dynamicTypeFailures,
                status: status,
                note: "Landscape was tested on the final crawled app state. Dynamic Type findings remain hierarchy-based; changing system text size is not performed automatically by the black-box scanner."
            )
        } catch {
            if let originalOrientation {
                try? await appium.setOrientation(originalOrientation)
            }
            return ResponsiveAccessibilityResult(
                tested: false,
                originalOrientation: nil,
                testedOrientation: "LANDSCAPE",
                orientationChanged: false,
                landscapeElementCount: 0,
                landscapeFailureCount: 0,
                landscapeWarningCount: 0,
                landscapeValidationCount: 0,
                landscapeScreenshotCaptured: false,
                dynamicTypeValidationCount: 0,
                dynamicTypeFailureCount: 0,
                status: .validate,
                note: "Runtime orientation testing could not be completed. Review the device/Appium orientation capability before relying on this result."
            )
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
                appium.makeParser()

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
                appium.makeParser()

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
    case reportIntegrityFailure(String)

    var errorDescription: String? {

        switch self {

        case .invalidScreenshot:

            return
                "Appium returned screenshot data that could not be decoded as an image."

        case .unstableUI:

            return
                "The application's UI changed while the screenshot and accessibility hierarchy were being synchronized. Please try the scan again."

        case .reportIntegrityFailure(let details):
            return "The scan completed, but the generated report failed an internal consistency check. No report was saved. \(details)"
        }
    }
}
