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
    /// Full and limited scans attach to the app as the tester left it
    /// instead of relaunching it, so in-memory state (settings, sign-in, an
    /// open flow) survives. The larger-text check needs a relaunch and is
    /// skipped.
    @Published var keepAppRunning: Bool = UserDefaults.standard.bool(forKey: "settings.keepAppRunning") {
        didSet { UserDefaults.standard.set(keepAppRunning, forKey: "settings.keepAppRunning") }
    }
    @Published var maximumScreens: Int = 10
    @Published private(set) var partialScreenCount: Int = 0

    private var scanTask: Task<Void, Never>?
    private var partialCrawledScreens: [CrawledScreen] = []

    // MARK: - Appium

    /// Read at the start of each scan, so a change in Settings applies to the next scan.
    private var appiumURL: URL { ScannerSettings.appiumURL }

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

                // A phone adb sees but cannot use is not in the list; say why.
                let blocked = await Task.detached { AndroidDeviceService().blockedDeviceNotes() }.value
                if !blocked.isEmpty {
                    errorMessage = blocked.joined(separator: "\n")
                }

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
                // Setting selectedDevice above already loads its apps
                // through the picker's change handler (deviceChanged).

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
                DeviceDiscoveryService()

            return try service.discoverDevices()

        }.value
    }

    // MARK: - Device Changed

    func deviceChanged() {

        guard let device = selectedDevice else {

            applications = []
            selectedApplication = nil

            return
        }

        // Runs after the current view update: changing published state
        // while SwiftUI is applying the picker change is not allowed.
        Task {
            applications = []
            selectedApplication = nil

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

            guard selectedDevice?.id == device.id else { return }

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
                AppDiscoveryService()

            return try service.discoverApps(
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
        TextRecognizer.warmUp()

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
        let notes = ScanNotes()
        var environment: ScanEnvironment?


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
                autoLaunch: mode != .currentPage && !keepAppRunning
            )

            let appium = AppiumClient(baseURL: configuration.appiumURL)
            try await appium.checkServer()
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
                if let foreground = await appium.foregroundAppID(),
                   foreground != application.bundleID {
                    notes.record(.launchFailed)
                }
            } else {
                status = "Capturing current page..."
                try await Task.sleep(for: .milliseconds(300))
                // Current Page scans whatever is on screen. Refuse to scan a
                // different app (Settings, the Home screen, another app) and
                // report it as the selected one.
                if let foreground = await appium.foregroundAppID(),
                   foreground != application.bundleID {
                    throw ScannerViewModelError.wrongAppInForeground(
                        expected: application.name,
                        actual: foreground
                    )
                }
            }
            environment = await makeEnvironment(appium: appium, device: device, application: application)

            status = "Reading initial accessibility hierarchy..."

            var initialSnapshot = try await captureStableSnapshot(
                appium: appium,
                notes: notes
            )
            // Flutter builds its accessibility tree only once it is asked
            // for, so the first read after launch can be nearly empty.
            var waits = 0
            while ProbeNodes.meaningfulCount(in: initialSnapshot.rootNode) < 3, waits < 4 {
                waits += 1
                status = "Waiting for the app's accessibility tree..."
                try await Task.sleep(for: .seconds(2))
                initialSnapshot = try await captureStableSnapshot(appium: appium, notes: notes)
            }

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
                ),
                notes: notes,
                probeEnvironment: RuntimeProbeEnvironment(
                    bundleID: application.bundleID,
                    platform: device.platform,
                    udid: device.udid,
                    allowAppRelaunch: mode != .currentPage && !keepAppRunning,
                    allowAppInteraction: mode != .currentPage
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
            if !responsiveResult.tested {
                notes.record(.responsiveCheckFailed)
            }

            status = "Building accessibility report..."

            var screenResults: [ScreenScanResult] = []

            for (screenNumber, crawledScreen) in crawledScreens.enumerated() {

                // Pixel analysis and annotation run off the main thread, one
                // screen at a time, so the window stays responsive and Stop is
                // handled between screens.
                try Task.checkCancellation()
                status = "Building accessibility report (screen \(screenNumber + 1) of \(crawledScreens.count))..."

                let number = screenResults.count + 1
                let screenResult = try await ProcessRunner.offMain {
                    ScreenResultBuilder.build(crawledScreen, number: number)
                }
                screenResults.append(screenResult)
            }

            let finishedAt = Date()

            var draftResult = AccessibilityScanResult(
                applicationName: application.name,
                bundleID: application.bundleID,
                deviceName: device.name,
                deviceUDID: device.udid,
                startedAt: startedAt,
                finishedAt: finishedAt,
                screens: ScreenNaming.uniquified(screenResults),
                rulesExecuted: AccessibilityRules.all.count
            )
            draftResult.environment = environment
            draftResult.scanNotes = notes.summaries
                + AccessibilityReportIntegrity.consistencyNotes(draftResult)

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
            
            trace("Screens: \(screenResults.count)", Log.scan)
            trace("Elements: \(result.totalElementsTested)", Log.scan)
            trace("Failures: \(result.totalFailures)", Log.scan)
            trace("Warnings: \(result.totalWarnings)", Log.scan)
            trace("Validations: \(result.totalValidations)", Log.scan)
            trace("Passes: \(result.totalPasses)", Log.scan)


        } catch {
            
            if Task.isCancelled {
                if !partialCrawledScreens.isEmpty {
                    var partial = makePartialReport(
                        crawledScreens: partialCrawledScreens,
                        application: application,
                        device: device,
                        startedAt: startedAt,
                        scanner: AccessibilityScanner()
                    )
                    partial.environment = environment
                    partial.scanNotes = ["The scan was stopped before it finished; screens not reached are not included."] + notes.summaries
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

        // Always release the Appium session, including after a failure or
        // Stop, and before the UI allows the next scan to start.
        if let appium = activeAppium, appium.sessionID != nil {
            await DeviceRestore.run {
                try? await appium.deleteSession()
            }
        }

        // Only needed to build a partial report on Stop; the full-resolution
        // screenshots it holds can take hundreds of megabytes.
        partialCrawledScreens = []
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
                imageData: Self.storedImage(screen.screenshotData),
                annotatedImageData: annotated.map { Self.storedImage($0) },
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
                name: ScreenNaming.name(for: screen.rootNode, number: index + 1),
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
            screens: ScreenNaming.uniquified(screenResults),
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
                await DeviceRestore.run { try? await appium.setOrientation(originalOrientation) }
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

            await DeviceRestore.run { try? await appium.setOrientation(originalOrientation) }

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
                note: "Landscape was tested on the final crawled app state. Larger text is tested separately on the first screen by relaunching the app at the largest text size."
            )
        } catch {
            if let originalOrientation {
                await DeviceRestore.run { try? await appium.setOrientation(originalOrientation) }
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

    private static func storedImage(_ data: Data) -> Data {
        ScreenResultBuilder.storedImage(data)
    }

    /// Device, OS, app and scanner versions for the report.
    private func makeEnvironment(
        appium: AppiumClient,
        device: Device,
        application: InstalledApp
    ) async -> ScanEnvironment {
        var version = application.version
        var build = application.build
        if device.platform == .android {
            let package = application.bundleID
            let serial = device.udid
            let android = try? await ProcessRunner.offMain {
                AndroidDeviceService().appVersion(package: package, serial: serial)
            }
            version = android?.version ?? version
            build = android?.build ?? build
        }
        return ScanEnvironment(
            platform: device.platform.rawValue,
            osVersion: appium.deviceOSVersion,
            deviceModel: appium.deviceModel,
            isSimulator: device.isSimulator,
            appVersion: version,
            appBuild: build,
            automationName: appium.automationName,
            appiumVersion: appium.serverVersion,
            scannerVersion: ScannerBuildInfo.displayVersion,
            ruleSetVersion: AccessibilityRuleCatalog.version,
            bbMappingVersion: BBIssueCatalog.version,
            wcagVersion: ScannerBuildInfo.wcagVersion
        )
    }

    private func captureStableSnapshot(
        appium: AppiumClient,
        notes: ScanNotes
    ) async throws -> StableScanSnapshot {

        var lastCapture: StableScanSnapshot?

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

            lastCapture = StableScanSnapshot(
                rootNode: rootBefore,
                screenshotData: screenshotData,
                screenshotWidth: screenshotWidth,
                screenshotHeight: screenshotHeight
            )

            if beforeSignature == afterSignature {

                trace("""

                Attempt:
                    \(attempt)

                Screenshot:
                    \(screenshotWidth) × \(screenshotHeight)

                Hierarchy:
                    \(rootBefore.frame.width) × \(rootBefore.frame.height)

                Result:
                    STABLE
                """, Log.scan)

                return StableScanSnapshot(
                    rootNode: rootBefore,
                    screenshotData: screenshotData,
                    screenshotWidth: screenshotWidth,
                    screenshotHeight: screenshotHeight
                )
            }

            trace("""

            Attempt:
                \(attempt)

            Result:
                UI hierarchy changed between
                screenshot boundaries.

            Before hierarchy:
                \(rootBefore.frame.width) × \(rootBefore.frame.height)

            After hierarchy:
                \(rootAfter.frame.width) × \(rootAfter.frame.height)
            """, Log.scan)

            if attempt < maximumSnapshotAttempts {

                status =
                    "UI changed — retrying synchronization..."

                try await Task.sleep(
                    nanoseconds:
                        snapshotRetryDelayNanoseconds
                )
            }
        }

        // Carousels, animations and live counters never hold still. Scan the
        // last capture rather than failing the whole scan, and say so.
        if let lastCapture {
            notes.record(.unstableScreen, example: "first screen")
            return lastCapture
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
        ScreenResultBuilder.mergeEvaluations(base, additions)
    }



    private func countNodes(_ node: AccessibilityNode) -> Int {
        ScreenResultBuilder.countNodes(node)
    }
}

// MARK: - Stable Scan Snapshot

nonisolated struct StableScanSnapshot {
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
    case wrongAppInForeground(expected: String, actual: String)

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

        case .wrongAppInForeground(let expected, let actual):
            let shown = actual == "com.apple.springboard" ? "the Home screen" : actual == "com.apple.Preferences" ? "the Settings app" : actual
            return "Current Page scans the screen that is open on the device, but the device is showing \(shown), not \(expected). Open the page you want to scan in \(expected), then start the scan again."
        }
    }
}
