
//  AppDiscoveryService.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 23/09/26.
//

import Foundation

final class AppDiscoveryService {

    // MARK: - Public

    func discoverApps(
        for device: Device
    ) throws -> [InstalledApp] {

        if device.isSimulator {
            return try discoverSimulatorApps(
                for: device
            )
        }

        return try discoverPhysicalDeviceApps(
            for: device
        )
    }

    // MARK: - Simulator

    private func discoverSimulatorApps(
        for device: Device
    ) throws -> [InstalledApp] {

        // Do not call simctl listapps on a shutdown simulator.
        guard device.state.lowercased() == "booted" else {
            print("")
            print("======================================")
            print("SIMULATOR NOT BOOTED")
            print("======================================")
            print("Device: \(device.name)")
            print("State: \(device.state)")
            print("Skipping application discovery.")
            print("======================================")

            return []
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(
            fileURLWithPath: "/usr/bin/xcrun"
        )

        process.arguments = [
            "simctl",
            "listapps",
            device.udid,
            "--json"
        ]

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let data =
            outputPipe.fileHandleForReading
                .readDataToEndOfFile()

        guard process.terminationStatus == 0 else {

            let errorData =
                errorPipe.fileHandleForReading
                    .readDataToEndOfFile()

            let errorText =
                String(
                    data: errorData,
                    encoding: .utf8
                ) ?? ""

            print("")
            print("======================================")
            print("SIMULATOR APP DISCOVERY FAILED")
            print("======================================")
            print("Device: \(device.name)")
            print("UDID: \(device.udid)")
            print(errorText)
            print("======================================")

            throw AppDiscoveryError.commandFailed(
                "Unable to retrieve applications from the simulator."
            )
        }

        let plist =
            try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )

        guard let appsDictionary =
                plist as? [String: Any]
        else {
            throw AppDiscoveryError.invalidResponse
        }

        var apps: [InstalledApp] = []

        for (_, value) in appsDictionary {

            guard let app =
                    value as? [String: Any]
            else {
                continue
            }

            guard let bundleID =
                    app["CFBundleIdentifier"] as? String
            else {
                continue
            }

            let name =
                app["CFBundleDisplayName"] as? String
                ?? app["CFBundleName"] as? String
                ?? bundleID

            apps.append(
                InstalledApp(
                    id: bundleID,
                    name: name,
                    bundleID: bundleID
                )
            )
        }

        let cleanedApps = cleanAndSort(apps)

        print("")
        print("======================================")
        print("SIMULATOR APPLICATIONS")
        print("======================================")
        print("Device: \(device.name)")
        print("UDID: \(device.udid)")
        print("Apps found: \(cleanedApps.count)")
        print("")

        for app in cleanedApps {
            print(
                "• \(app.name) — \(app.bundleID)"
            )
        }

        print("======================================")

        return cleanedApps
    }

    // MARK: - Physical Device

    private func discoverPhysicalDeviceApps(
        for device: Device
    ) throws -> [InstalledApp] {

        let outputURL = URL(
            fileURLWithPath:
                "/tmp/accessibility-scanner-apps-\(device.udid).json"
        )

        // Remove stale output before every request.
        try? FileManager.default.removeItem(
            at: outputURL
        )

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(
            fileURLWithPath: "/usr/bin/xcrun"
        )

        process.arguments = [
            "devicectl",
            "device",
            "info",
            "apps",
            "--device",
            device.udid,
            "--json-output",
            outputURL.path
        ]

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        print("")
        print("======================================")
        print("PHYSICAL DEVICE APP DISCOVERY")
        print("======================================")
        print("Device: \(device.name)")
        print("UDID: \(device.udid)")
        print("======================================")

        do {
            try process.run()
        } catch {
            print("❌ Unable to start devicectl:")
            print(error.localizedDescription)

            throw AppDiscoveryError.commandFailed(
                "Unable to start device application discovery."
            )
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {

            let errorData =
                errorPipe.fileHandleForReading
                    .readDataToEndOfFile()

            let errorText =
                String(
                    data: errorData,
                    encoding: .utf8
                ) ?? "Unknown devicectl error."

            print("")
            print("======================================")
            print("DEVICECTL APP DISCOVERY FAILED")
            print("======================================")
            print(errorText)
            print("======================================")

            throw AppDiscoveryError.commandFailed(
                "Unable to retrieve applications from the connected iPhone.\n\(errorText)"
            )
        }

        guard FileManager.default.fileExists(
            atPath: outputURL.path
        ) else {

            print("❌ devicectl did not create JSON output.")

            throw AppDiscoveryError.invalidResponse
        }

        let data: Data

        do {
            data = try Data(
                contentsOf: outputURL
            )
        } catch {
            print("❌ Unable to read devicectl JSON:")
            print(error.localizedDescription)

            throw AppDiscoveryError.invalidResponse
        }

        let apps = try parsePhysicalApps(
            from: data
        )

        print("")
        print("======================================")
        print("PHYSICAL DEVICE APPLICATIONS")
        print("======================================")
        print("Device: \(device.name)")
        print("UDID: \(device.udid)")
        print("Apps found: \(apps.count)")
        print("")

        for app in apps {
            print(
                "• \(app.name) — \(app.bundleID)"
            )
        }

        print("======================================")

        return apps
    }

    // MARK: - Physical App Parsing

    private func parsePhysicalApps(
        from data: Data
    ) throws -> [InstalledApp] {

        let json: Any

        do {
            json = try JSONSerialization.jsonObject(
                with: data,
                options: []
            )
        } catch {
            print("❌ Invalid JSON returned by devicectl:")
            print(error.localizedDescription)

            throw AppDiscoveryError.invalidResponse
        }

        guard let root =
                json as? [String: Any]
        else {
            print("❌ devicectl response is not a dictionary.")
            throw AppDiscoveryError.invalidResponse
        }

        guard let result =
                root["result"] as? [String: Any]
        else {
            print("❌ Missing 'result' in devicectl response.")
            print("Top-level keys: \(root.keys)")

            throw AppDiscoveryError.invalidResponse
        }

        guard let appObjects =
                result["apps"] as? [[String: Any]]
        else {
            print("❌ Missing 'apps' in devicectl response.")
            print("Result keys: \(result.keys)")

            throw AppDiscoveryError.invalidResponse
        }

        var apps: [InstalledApp] = []

        for app in appObjects {

            guard let bundleID =
                    app["bundleIdentifier"] as? String
            else {
                continue
            }

            let name =
                app["name"] as? String
                ?? bundleID

            apps.append(
                InstalledApp(
                    id: bundleID,
                    name: name,
                    bundleID: bundleID
                )
            )
        }

        return cleanAndSort(apps)
    }

    // MARK: - Cleanup

    private func cleanAndSort(
        _ apps: [InstalledApp]
    ) -> [InstalledApp] {

        var uniqueApps: [InstalledApp] = []
        var seenBundleIDs = Set<String>()

        for app in apps {

            guard !seenBundleIDs.contains(
                app.bundleID
            ) else {
                continue
            }

            // Hide Apple's internal/system apps.
            if app.bundleID.hasPrefix(
                "com.apple."
            ) {
                continue
            }

            seenBundleIDs.insert(
                app.bundleID
            )

            uniqueApps.append(
                app
            )
        }

        return uniqueApps.sorted {
            $0.name.localizedCaseInsensitiveCompare(
                $1.name
            ) == .orderedAscending
        }
    }
}

// MARK: - Errors

enum AppDiscoveryError:
    Error,
    LocalizedError {

    case commandFailed(String)
    case invalidResponse

    var errorDescription: String? {

        switch self {

        case .commandFailed(let message):
            return message

        case .invalidResponse:
            return "Apple returned an invalid application list."
        }
    }
}
