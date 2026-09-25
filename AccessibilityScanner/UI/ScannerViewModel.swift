//
//  ScannerViewModel.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 22/09/26.
//

import Foundation
import SwiftUI
import Combine

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

    // Legacy findings support
    @Published var findings: [AccessibilityFinding] = []

    // Complete scan report
    @Published var scanResult: AccessibilityScanResult?

    @Published var errorMessage: String?

    // MARK: - Appium

    private let appiumURL = URL(
        string: "http://127.0.0.1:4723"
    )!

    // MARK: - Device Discovery

    func loadDevices() {

        isLoadingDevices = true
        errorMessage = nil

        Task {

            do {

                let discoveredDevices =
                    try await discoverDevices()

                devices = discoveredDevices

                // Prefer a booted simulator.
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

                // Automatically discover apps
                // for the selected device.
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

    // MARK: - Device Selection

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

            // Automatically select the first
            // available application.
            if let firstApp =
                discoveredApps.first {

                selectedApplication =
                    firstApp
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
                bundleID:
                    application.bundleID,
                deviceName:
                    device.name,
                udid:
                    device.udid
            )

        let appium =
            AppiumClient(
                baseURL:
                    configuration.appiumURL
            )

        let scanStartedAt = Date()

        do {
            status =
                "Creating Appium session..."

            _ = try await appium.createSession(
                configuration:
                    configuration
            )

            status = "Reading UI hierarchy..."

            let xml =
                try await appium.getSource()

            status = "Capturing screenshot..."

            let screenshotData =
                try await appium.getScreenshot()

            status =
                "Parsing UI hierarchy..."

            let parser =
                WDAElementParser()

            let rootNode =
                try parser.parse(xml)
            
            guard rootNode.frame.width > 0,
                  rootNode.frame.height > 0 else {

                throw ScreenshotAnnotatorError.invalidImage
            }
            
            let scanner =
                AccessibilityScanner()
            
            status =
                "Running accessibility checks..."

            let evaluations =
                scanner.evaluateForReport(
                    rootNode:
                        rootNode
                )

            let results =
                scanner.scan(
                    rootNode:
                        rootNode
                )

            findings =
                results

            status =
                "Building accessibility report..."

            let report =
                scanner.scanReport(
                    rootNode:
                        rootNode,
                    applicationName:
                        application.name,
                    bundleID:
                        application.bundleID,
                    deviceName:
                        device.name,
                    deviceUDID:
                        device.udid
                )

            scanResult =
                report

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

            isScanning =
                false

            try? await appium.deleteSession()

        } catch {

            try? await appium.deleteSession()

            errorMessage =
                error.localizedDescription

            status =
                "Scan failed"

            isScanning =
                false
        }
    }
}
