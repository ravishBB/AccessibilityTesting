//
//  ScannerSettings.swift
//  AccessibilityScanner
//
//  Per-user settings that used to be hard-coded: the Appium server and the
//  Apple signing details WebDriverAgent needs on a physical iPhone.
//

import SwiftUI

nonisolated enum ScannerSettings {

    enum Key {
        static let appiumURL = "settings.appiumURL"
        static let teamID = "settings.xcodeTeamID"
        static let signingID = "settings.xcodeSigningID"
        static let androidSDKPath = "settings.androidSDKPath"
    }

    static let defaultAppiumURL = "http://127.0.0.1:4723"
    static let defaultSigningID = "Apple Development"

    static var appiumURL: URL {
        let text = UserDefaults.standard.string(forKey: Key.appiumURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return validAppiumURL(text) ?? URL(string: defaultAppiumURL)!
    }

    /// Apple Developer team ID for signing WebDriverAgent. Empty when unset:
    /// simulators and an already-signed WebDriverAgent do not need one.
    static var teamID: String {
        UserDefaults.standard.string(forKey: Key.teamID)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var signingID: String {
        let value = UserDefaults.standard.string(forKey: Key.signingID)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? defaultSigningID : value
    }

    /// Android SDK folder set by the user, or empty.
    static var androidSDKPath: String {
        let value = UserDefaults.standard.string(forKey: Key.androidSDKPath)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (value as NSString).expandingTildeInPath
    }

    static func validAppiumURL(_ text: String) -> URL? {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }
}

struct ScannerSettingsView: View {

    @AppStorage(ScannerSettings.Key.appiumURL) private var appiumURL = ScannerSettings.defaultAppiumURL
    @AppStorage(ScannerSettings.Key.teamID) private var teamID = ""
    @AppStorage(ScannerSettings.Key.signingID) private var signingID = ScannerSettings.defaultSigningID
    @AppStorage(ScannerSettings.Key.androidSDKPath) private var androidSDKPath = ""

    private var adbExists: Bool {
        FileManager.default.isExecutableFile(atPath: "\(ScannerSettings.androidSDKPath)/platform-tools/adb")
    }

    var body: some View {
        Form {
            Section("Appium server") {
                TextField("Server URL", text: $appiumURL, prompt: Text(ScannerSettings.defaultAppiumURL))
                if ScannerSettings.validAppiumURL(appiumURL) == nil {
                    Text("Enter a full URL, for example \(ScannerSettings.defaultAppiumURL). The default is used until then.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                TextField("Team ID", text: $teamID, prompt: Text("e.g. ABCDE12345"))
                TextField("Signing identity", text: $signingID, prompt: Text(ScannerSettings.defaultSigningID))
            } header: {
                Text("Physical iPhone signing")
            } footer: {
                Text("Used to sign WebDriverAgent on a connected iPhone. Find your team ID in Xcode › Settings › Accounts. Not needed for simulators or Android.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Android SDK folder", text: $androidSDKPath, prompt: Text("~/Library/Android/sdk"))
                if !androidSDKPath.isEmpty, !adbExists {
                    Text("No adb found at \(ScannerSettings.androidSDKPath)/platform-tools/adb.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Android")
            } footer: {
                Text("Only needed when adb is not found automatically. Use the folder that contains platform-tools.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding(.vertical, 8)
    }
}
