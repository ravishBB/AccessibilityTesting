//
//  AndroidDeviceService.swift
//  AccessibilityScanner


import Foundation

nonisolated final class AndroidDeviceService {

    // MARK: - Errors

    enum AndroidServiceError: LocalizedError {

        case adbNotFound
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .adbNotFound:
                return "adb was not found. Install Android platform-tools, or set the Android SDK folder in Settings (⌘,)."
            case .commandFailed(let message):
                return "adb command failed: \(message)"
            }
        }
    }

    // MARK: - adb location
    func adbPath() -> String? {

        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment

        let configured = ScannerSettings.androidSDKPath
        if !configured.isEmpty {
            candidates.append("\(configured)/platform-tools/adb")
            candidates.append(configured)  // the adb binary itself
        }

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
        } ?? Self.adbFromLoginShell
    }

    private static let adbFromLoginShell: String? = {
        guard let output = try? ProcessRunner.run("/bin/zsh", ["-lc", "command -v adb"], timeout: 10),
              output.status == 0
        else { return nil }
        let path = output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }()

    // MARK: - Devices
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

    /// Phones adb sees but cannot use yet, as instructions for the tester.
    /// They are not listed as devices: nothing can be scanned on them.
    func blockedDeviceNotes() -> [String] {
        guard let adb = adbPath(),
              let output = try? run(adb, ["devices", "-l"])
        else { return [] }

        let notes: [String] = output.components(separatedBy: .newlines).dropFirst().compactMap { line in
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2 else { return nil }
            let model = parts.first { $0.hasPrefix("model:") }
                .map { String($0.dropFirst("model:".count)).replacingOccurrences(of: "_", with: " ") }
            let name = model.map { "\($0) (\(parts[0]))" } ?? parts[0]
            switch parts[1] {
            case "unauthorized":
                return "\(name) is waiting for permission. Unlock the phone, tap Allow on \"Allow USB debugging?\", then refresh."
            case "offline":
                return "\(name) is offline to adb. Unplug and reconnect the cable, or toggle USB debugging off and on, then refresh."
            case "no", "no permissions":
                return "\(name) cannot be accessed by adb (no permissions). Reconnect the cable and refresh."
            default:
                return nil
            }
        }

        let adbSerials = output.components(separatedBy: .newlines).dropFirst()
            .compactMap { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) }
        return notes + usbPhonesInvisibleToADB(knownSerials: Set(adbSerials))
    }

    /// Android phones plugged in over USB that adb cannot see at all: USB
    /// debugging is off, or the phone is in a mode without the debugging
    /// interface (USB tethering, charging only).
    private func usbPhonesInvisibleToADB(knownSerials: Set<String>) -> [String] {
        guard let output = try? ProcessRunner.run("/usr/sbin/ioreg", ["-p", "IOUSB", "-l", "-w0"], timeout: 10)
        else { return [] }

        var notes: [String] = []
        var product: String?
        for line in output.stdoutText.components(separatedBy: .newlines) {
            if line.contains("\"USB Product Name\" = ") {
                product = line.components(separatedBy: "= ").last?.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            } else if line.contains("\"USB Serial Number\" = "), let name = product,
                      name.localizedCaseInsensitiveContains("android") {
                let serial = line.components(separatedBy: "= ").last?.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) ?? ""
                if !knownSerials.contains(serial) {
                    notes.append("\(name.replacingOccurrences(of: "_", with: " ")) (\(serial)) is connected by USB but adb cannot see it. Turn off USB tethering, choose \"File transfer\" in the phone's USB notification, make sure USB debugging is on, then reconnect and tap Allow.")
                }
                product = nil
            }
        }
        return notes
    }

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

    /// versionName and versionCode of an installed package, for the report.
    func appVersion(package: String, serial: String) -> (version: String?, build: String?) {
        guard let adb = adbPath(),
              let output = try? run(adb, ["-s", serial, "shell", "dumpsys", "package", package])
        else { return (nil, nil) }

        func value(after key: String) -> String? {
            guard let range = output.range(of: key) else { return nil }
            let rest = output[range.upperBound...]
            let token = rest.prefix { !$0.isWhitespace }
            return token.isEmpty ? nil : String(token)
        }
        return (value(after: "versionName="), value(after: "versionCode="))
    }

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
    func fontScale(serial: String) throws -> String? {
        guard let adb = adbPath() else { throw AndroidServiceError.adbNotFound }
        let output = try run(adb, ["-s", serial, "shell", "settings", "get", "system", "font_scale"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (output.isEmpty || output == "null") ? nil : output
    }

    /// Sets the system font scale; nil restores the default.
    func setFontScale(serial: String, value: String?) throws {
        guard let adb = adbPath() else { throw AndroidServiceError.adbNotFound }
        if let value {
            _ = try run(adb, ["-s", serial, "shell", "settings", "put", "system", "font_scale", value])
        } else {
            _ = try run(adb, ["-s", serial, "shell", "settings", "delete", "system", "font_scale"])
        }
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> String {
        let output = try ProcessRunner.run(executable, arguments, timeout: 30)
        guard output.status == 0 else {
            throw AndroidServiceError.commandFailed(
                output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return output.stdoutText
    }
}
