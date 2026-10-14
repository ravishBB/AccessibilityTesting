
//  AppDiscoveryService.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 23/09/26.
//

import Foundation

/// Nonisolated: its xcrun calls block, so callers run it off the main actor.
nonisolated final class AppDiscoveryService {

    // MARK: - Public

    func discoverApps(
        for device: Device
    ) throws -> [InstalledApp] {

        if device.platform == .android {
            return try AndroidDeviceService().discoverApps(
                for: device
            )
        }

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
            trace("Device: \(device.name)", Log.devices)
            trace("State: \(device.state)", Log.devices)

            return []
        }

        let result = try ProcessRunner.run(
            "/usr/bin/xcrun",
            ["simctl", "listapps", device.udid, "--json"],
            timeout: 60
        )
        let data = result.stdout

        guard result.status == 0 else {
            trace("simctl listapps failed for \(device.name): \(result.stderrText)", Log.devices)
            throw AppDiscoveryError.commandFailed(
                "Unable to retrieve applications from the simulator.\n\(result.stderrText)"
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
                    bundleID: bundleID,
                    version: app["CFBundleShortVersionString"] as? String,
                    build: app["CFBundleVersion"] as? String
                )
            )
        }

        let cleanedApps = cleanAndSort(apps)
        trace("Device: \(device.name)", Log.devices)
        trace("UDID: \(device.udid)", Log.devices)
        trace("Apps found: \(cleanedApps.count)", Log.devices)
        trace("", Log.devices)

        for app in cleanedApps {
            trace(
                "• \(app.name) — \(app.bundleID)"
            , Log.devices)
        }

        return cleanedApps
    }

    // MARK: - Physical Device

    private func discoverPhysicalDeviceApps(
        for device: Device
    ) throws -> [InstalledApp] {

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("accessibility-scanner-apps-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        // Remove stale output before every request.
        try? FileManager.default.removeItem(
            at: outputURL
        )

        let result: ProcessRunner.Output
        do {
            result = try ProcessRunner.run(
                "/usr/bin/xcrun",
                ["devicectl", "device", "info", "apps", "--device", device.udid, "--json-output", outputURL.path],
                timeout: 120
            )
        } catch let error as ProcessRunner.RunnerError {
            throw AppDiscoveryError.commandFailed(error.localizedDescription)
        } catch {
            throw AppDiscoveryError.commandFailed(
                "Unable to start device application discovery: \(error.localizedDescription)"
            )
        }

        guard result.status == 0 else {
            let errorText = result.stderrText.isEmpty ? "Unknown devicectl error." : result.stderrText
            throw AppDiscoveryError.commandFailed(
                "Unable to retrieve applications from the connected iPhone.\n\(errorText)"
            )
        }

        guard FileManager.default.fileExists(
            atPath: outputURL.path
        ) else {

            throw AppDiscoveryError.invalidResponse
        }

        let data: Data

        do {
            data = try Data(
                contentsOf: outputURL
            )
        } catch {
            trace(error.localizedDescription, Log.devices)

            throw AppDiscoveryError.invalidResponse
        }

        let apps = try parsePhysicalApps(
            from: data
        )

        trace("Device: \(device.name)", Log.devices)
        trace("UDID: \(device.udid)", Log.devices)
        trace("Apps found: \(apps.count)", Log.devices)
        trace("", Log.devices)

        for app in apps {
            trace(
                "• \(app.name) — \(app.bundleID)"
            , Log.devices)
        }

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
            trace(error.localizedDescription, Log.devices)

            throw AppDiscoveryError.invalidResponse
        }

        guard let root =
                json as? [String: Any]
        else {
            throw AppDiscoveryError.invalidResponse
        }

        guard let result =
                root["result"] as? [String: Any]
        else {
            trace("Top-level keys: \(root.keys)", Log.devices)

            throw AppDiscoveryError.invalidResponse
        }

        guard let appObjects =
                result["apps"] as? [[String: Any]]
        else {
            trace("Result keys: \(result.keys)", Log.devices)

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
                    bundleID: bundleID,
                    version: app["version"] as? String,
                    build: app["bundleVersion"] as? String
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

nonisolated enum AppDiscoveryError:
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
