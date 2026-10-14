//
//  DeviceDiscoveryService.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 22/09/26.
//

import Foundation

nonisolated final class DeviceDiscoveryService {

    // MARK: - Public

    func discoverDevices() throws -> [Device] {

        var devices: [Device] = []
        var firstError: Error?
        do {
            devices.append(contentsOf: try discoverSimulators())
        } catch {
            firstError = firstError ?? error
            trace("Simulator discovery failed: \(error.localizedDescription)", Log.devices)
        }

        do {
            devices.append(contentsOf: try discoverPhysicalDevices())
        } catch {
            firstError = firstError ?? error
            trace("Physical device discovery failed: \(error.localizedDescription)", Log.devices)
        }

        // Android emulators and devices (empty when adb is not installed).
        devices.append(
            contentsOf: AndroidDeviceService().discoverDevices()
        )

        if devices.isEmpty, let firstError {
            throw firstError
        }

        return devices
    }

    // MARK: - Simulators
    private func discoverSimulators() throws -> [Device] {
        let output = try runCommand(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "available", "-j"]
        )
        guard let json = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
              let runtimes = json["devices"] as? [String: [[String: Any]]]
        else {
            return try discoverSimulatorsFromText()
        }

        var devices: [Device] = []
        for (runtime, entries) in runtimes.sorted(by: { $0.key > $1.key }) where runtime.contains(".iOS-") {
            for entry in entries {
                guard let udid = entry["udid"] as? String,
                      let name = entry["name"] as? String,
                      (entry["isAvailable"] as? Bool) ?? true
                else { continue }
                devices.append(Device(
                    id: udid,
                    name: name,
                    udid: udid,
                    state: (entry["state"] as? String) ?? "Shutdown",
                    type: .simulator
                ))
            }
        }
        return devices
    }

    private func discoverSimulatorsFromText() throws -> [Device] {

        let output = try runCommand(
            executable: "/usr/bin/xcrun",
            arguments: [
                "simctl",
                "list",
                "devices",
                "available"
            ]
        )

        var devices: [Device] = []

        let lines = output.components(
            separatedBy: .newlines
        )

        for line in lines {

            let trimmed =
                line.trimmingCharacters(
                    in: .whitespaces
                )

            guard trimmed.contains("("),
                  trimmed.contains(")") else {
                continue
            }

            guard trimmed.contains("Booted")
                    || trimmed.contains("Shutdown") else {
                continue
            }

            guard let openParen =
                    trimmed.firstIndex(
                        of: "("
                    ),
                  let closeParen =
                    trimmed.firstIndex(
                        of: ")"
                    ) else {
                continue
            }

            let name =
                String(
                    trimmed[
                        trimmed.startIndex..<openParen
                    ]
                )
                .trimmingCharacters(
                    in: .whitespaces
                )

            let udid =
                String(
                    trimmed[
                        trimmed.index(
                            after: openParen
                        )..<closeParen
                    ]
                )

            let state: String

            if trimmed.contains("Booted") {
                state = "Booted"
            } else {
                state = "Shutdown"
            }

            devices.append(
                Device(
                    id: udid,
                    name: name,
                    udid: udid,
                    state: state,
                    type: .simulator
                )
            )
        }

        return devices
    }

    // MARK: - Physical Devices
    private func discoverPhysicalDevices() throws -> [Device] {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("accessibility-scanner-devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        _ = try runCommand(
            executable: "/usr/bin/xcrun",
            arguments: ["devicectl", "list", "devices", "--json-output", outputURL.path]
        )

        guard let data = try? Data(contentsOf: outputURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = (json["result"] as? [String: Any])?["devices"] as? [[String: Any]]
        else {
            return try discoverPhysicalDevicesFromText()
        }

        return entries.compactMap { entry in
            let hardware = entry["hardwareProperties"] as? [String: Any] ?? [:]
            let properties = entry["deviceProperties"] as? [String: Any] ?? [:]
            let connection = entry["connectionProperties"] as? [String: Any] ?? [:]

            guard (hardware["platform"] as? String) == "iOS",
                  (hardware["reality"] as? String) == "physical",
                  let udid = hardware["udid"] as? String
            else { return nil }

            let connected = (connection["tunnelState"] as? String) == "connected"
            return Device(
                id: udid,
                name: (properties["name"] as? String)
                    ?? (hardware["marketingName"] as? String)
                    ?? "iPhone",
                udid: udid,
                state: connected ? "Connected" : "Unavailable",
                type: .physical
            )
        }
    }

    private func discoverPhysicalDevicesFromText() throws -> [Device] {

        let output = try runCommand(
            executable: "/usr/bin/xcrun",
            arguments: [
                "devicectl",
                "list",
                "devices"
            ]
        )

        trace(output, Log.devices)

        return parsePhysicalDevices(
            output
        )
    }

    // MARK: - Parse Physical Devices
    private func parsePhysicalDevices(
        _ output: String
    ) -> [Device] {

        var devices: [Device] = []

        let lines =
            output.components(
                separatedBy: .newlines
            )

        for line in lines {

            let trimmed =
                line.trimmingCharacters(
                    in: .whitespaces
                )

            guard !trimmed.isEmpty else {
                continue
            }

            guard let udid =
                    extractPhysicalUDID(
                        from: trimmed
                    ) else {
                continue
            }

            let name =
                extractDeviceName(
                    from: trimmed,
                    udid: udid
                )

            let state =
                determineState(
                    from: trimmed
                )

            let device =
                Device(
                    id: udid,
                    name: name,
                    udid: udid,
                    state: state,
                    type: .physical
                )

            trace("Name: \(device.name)", Log.devices)
            trace("UDID: \(device.udid)", Log.devices)
            trace("State: \(device.state)", Log.devices)
            trace("Type: \(device.type)", Log.devices)

            devices.append(device)
        }
        
        var uniqueDevices:
            [String: Device] = [:]

        for device in devices {

            uniqueDevices[
                device.udid
            ] = device
        }

        return Array(
            uniqueDevices.values
        )
        .sorted {
            $0.name.localizedCaseInsensitiveCompare(
                $1.name
            ) == .orderedAscending
        }
    }

    // MARK: - Extract Physical UDID

    private func extractPhysicalUDID(
        from line: String
    ) -> String? {

        let pattern =
            #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}"#

        guard let regex =
                try? NSRegularExpression(
                    pattern: pattern
                ) else {

            return nil
        }

        let range =
            NSRange(
                line.startIndex..<line.endIndex,
                in: line
            )

        guard let match =
                regex.firstMatch(
                    in: line,
                    range: range
                ) else {

            return nil
        }

        guard let matchRange =
                Range(
                    match.range,
                    in: line
                ) else {

            return nil
        }

        let udid =
            String(
                line[matchRange]
            )

        trace(
            "Extracted physical UDID: \(udid)"
        , Log.devices)

        return udid
    }

    // MARK: - Extract Device Name

    private func extractDeviceName(
        from line: String,
        udid: String
    ) -> String {

        guard let range =
                line.range(
                    of: udid
                ) else {

            return "iPhone"
        }

        let beforeUDID =
            String(
                line[..<range.lowerBound]
            )
            .trimmingCharacters(
                in: .whitespaces
            )

        let cleaned =
            beforeUDID
                .replacingOccurrences(
                    of: "│",
                    with: " "
                )
                .replacingOccurrences(
                    of: "┃",
                    with: " "
                )
                .replacingOccurrences(
                    of: "|",
                    with: " "
                )
                .trimmingCharacters(
                    in: .whitespaces
                )

        if !cleaned.isEmpty {
            return cleaned
        }

        return "iPhone"
    }

    // MARK: - Determine State
    private func determineState(
        from line: String
    ) -> String {

        let lower =
            line.lowercased()

        if lower.contains(
            "unavailable"
        ) {

            return "Unavailable"
        }

        if lower.contains(
            "available"
        ) {

            return "Connected"
        }

        if lower.contains(
            "connected"
        ) {

            return "Connected"
        }

        return "Connected"
    }

    // MARK: - Run Command

    private func runCommand(
        executable: String,
        arguments: [String]
    ) throws -> String {

        let result = try ProcessRunner.run(executable, arguments, timeout: 30)

        guard result.status == 0 else {
            throw DeviceDiscoveryError.commandFailed(
                command: "\(executable) \(arguments.joined(separator: " "))",
                message: result.stderrText.isEmpty ? result.stdoutText : result.stderrText
            )
        }

        return result.stdoutText
    }
}

// MARK: - Errors

nonisolated enum DeviceDiscoveryError:
    Error,
    LocalizedError {

    case commandFailed(
        command: String,
        message: String
    )

    var errorDescription: String? {

        switch self {

        case .commandFailed(
            let command,
            let message
        ):

            return """
            Device discovery command failed.

            Command:

            \(command)

            Error:

            \(message)
            """
        }
    }
}
