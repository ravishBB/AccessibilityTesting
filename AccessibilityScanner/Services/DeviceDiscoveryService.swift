//
//  DeviceDiscoveryService.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 22/09/26.
//

import Foundation

final class DeviceDiscoveryService {

    // MARK: - Public

    func discoverDevices() throws -> [Device] {

        var devices: [Device] = []

        // Discover simulators

        devices.append(
            contentsOf: try discoverSimulators()
        )

        // Discover physical devices

        devices.append(
            contentsOf: try discoverPhysicalDevices()
        )

        return devices
    }

    // MARK: - Simulators

    private func discoverSimulators() throws -> [Device] {

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

        let output = try runCommand(
            executable: "/usr/bin/xcrun",
            arguments: [
                "devicectl",
                "list",
                "devices"
            ]
        )

        print("")
        print("======================================")
        print("DEVICECTL OUTPUT")
        print("======================================")
        print(output)
        print("======================================")

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

            print("")
            print("======================================")
            print("PHYSICAL DEVICE FOUND")
            print("======================================")
            print("Name: \(device.name)")
            print("UDID: \(device.udid)")
            print("State: \(device.state)")
            print("Type: \(device.type)")
            print("======================================")

            devices.append(device)
        }

        // Remove duplicates by UDID.

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

        /*
         Physical Apple device UDID:

         00008030-001E11943641802E

         Format:
         8 hexadecimal characters
         -
         16 hexadecimal characters

         Total:
         25 characters
         */

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

        print(
            "Extracted physical UDID: \(udid)"
        )

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

        /*
         Check unavailable first because
         "unavailable" contains the word
         "available".
         */

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

        let process =
            Process()

        process.executableURL =
            URL(
                fileURLWithPath:
                    executable
            )

        process.arguments =
            arguments

        let outputPipe =
            Pipe()

        let errorPipe =
            Pipe()

        process.standardOutput =
            outputPipe

        process.standardError =
            errorPipe

        try process.run()

        process.waitUntilExit()

        let outputData =
            outputPipe
                .fileHandleForReading
                .readDataToEndOfFile()

        let errorData =
            errorPipe
                .fileHandleForReading
                .readDataToEndOfFile()

        let output =
            String(
                data: outputData,
                encoding: .utf8
            )
            ?? ""

        let error =
            String(
                data: errorData,
                encoding: .utf8
            )
            ?? ""

        guard process.terminationStatus == 0 else {

            throw DeviceDiscoveryError.commandFailed(
                command:
                    "\(executable) \(arguments.joined(separator: " "))",
                message:
                    error.isEmpty
                    ? output
                    : error
            )
        }

        return output
    }
}

// MARK: - Errors

enum DeviceDiscoveryError:
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
