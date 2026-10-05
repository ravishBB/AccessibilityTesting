//
//  AndroidDeviceService.swift
//  AccessibilityScanner
//
//  Discovers Android devices/emulators and installed apps through `adb`.
//

import Foundation

final class AndroidDeviceService {

    // MARK: - Errors

    enum AndroidServiceError: LocalizedError {

        case adbNotFound
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .adbNotFound:
                return "adb was not found. Install Android platform-tools or set ANDROID_HOME."
            case .commandFailed(let message):
                return "adb command failed: \(message)"
            }
        }
    }

    // MARK: - adb location

    func adbPath() -> String? {

        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment

        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let root = environment[key], !root.isEmpty {
                candidates.append("\(root)/platform-tools/adb")
            }
        }

        candidates.append(
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb"
        )
        candidates.append("/opt/homebrew/bin/adb")
        candidates.append("/usr/local/bin/adb")

        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    // MARK: - Devices

    /// Returns connected Android devices. Returns an empty list (never throws)
    /// when adb is not installed so iOS-only setups keep working.
    func discoverDevices() -> [Device] {

        guard let adb = adbPath(),
              let output = try? run(adb, ["devices", "-l"])
        else {
            return []
        }

        var devices: [Device] = []

        for line in output.components(separatedBy: .newlines).dropFirst() {

            let parts = line
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)

            guard parts.count >= 2, parts[1] == "device" else { continue }

            let serial = parts[0]
            let isEmulator = serial.hasPrefix("emulator-")

            let model = parts
                .first(where: { $0.hasPrefix("model:") })
                .map { String($0.dropFirst("model:".count)) }
                .map { $0.replacingOccurrences(of: "_", with: " ") }

            var device = Device(
                id: serial,
                name: model ?? serial,
                udid: serial,
                state: isEmulator ? "Booted" : "Connected",
                type: isEmulator ? .simulator : .physical
            )

            device.platform = .android
            device.displayDensity = displayDensity(serial: serial, adb: adb)

            devices.append(device)
        }

        return devices
    }

    /// Override density if set, otherwise the physical density.
    private func displayDensity(serial: String, adb: String) -> Int? {

        guard let output = try? run(adb, ["-s", serial, "shell", "wm", "density"]) else {
            return nil
        }

        var physical: Int?
        var override: Int?

        for line in output.components(separatedBy: .newlines) {

            guard let value = line
                .split(separator: ":")
                .last
                .flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) })
            else { continue }

            if line.contains("Override") {
                override = value
            } else if line.contains("Physical") {
                physical = value
            }
        }

        return override ?? physical
    }

    // MARK: - Apps

    /// Lists user-installed (third-party) packages.
    func discoverApps(for device: Device) throws -> [InstalledApp] {

        guard let adb = adbPath() else {
            throw AndroidServiceError.adbNotFound
        }

        let output = try run(
            adb,
            ["-s", device.udid, "shell", "pm", "list", "packages", "-3"]
        )

        let apps = output
            .components(separatedBy: .newlines)
            .compactMap { line -> InstalledApp? in

                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("package:") else { return nil }

                let package = String(trimmed.dropFirst("package:".count))
                guard !package.isEmpty else { return nil }

                let lastComponent = package
                    .split(separator: ".")
                    .last
                    .map(String.init) ?? package

                return InstalledApp(
                    id: package,
                    name: lastComponent.capitalized,
                    bundleID: package
                )
            }

        return apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Launcher activity

    /// Resolves the launcher activity so Appium can start the app.
    /// Returns nil if it cannot be resolved (Appium will try its own detection).
    func launchableActivity(package: String, serial: String) -> String? {

        guard let adb = adbPath(),
              let output = try? run(
                adb,
                ["-s", serial, "shell", "cmd", "package", "resolve-activity", "--brief", package]
              )
        else {
            return nil
        }

        guard let line = output
            .components(separatedBy: .newlines)
            .last(where: { $0.contains("/") })?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return nil
        }

        guard let activity = line.split(separator: "/").last else {
            return nil
        }

        return String(activity)
    }

    // MARK: - Process

    private func run(_ executable: String, _ arguments: [String]) throws -> String {

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // Read before waiting so a full pipe cannot deadlock the process.
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw AndroidServiceError.commandFailed(
                message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return String(data: outputData, encoding: .utf8) ?? ""
    }
}
