//
//  AppiumClient.swift
//  AccessibilityScannerDemo
//  Created by Ravish Kumar on 22/09/26.

import Foundation
import os
import CoreGraphics

final class AppiumClient {

    private let baseURL: URL
    private(set) var sessionID: String?
    #if DEBUG
    private let showXcodeLog = true
    #else
    private let showXcodeLog = false
    #endif

    /// Platform of the active session. Set by `createSession`.
    private(set) var platform: MobilePlatform = .ios

    /// Pixels per dp on Android (1 on iOS, where WDA already reports points).
    private(set) var displayScale: CGFloat = 1

    /// Reported by the server and session, for the report's environment.
    private(set) var serverVersion: String?
    private(set) var deviceOSVersion: String?
    private(set) var deviceModel: String?
    private(set) var automationName: String?

    init(baseURL: URL) {
        self.baseURL = baseURL
    }
    
    /// Fails fast with a clear message when no Appium server is listening,
    /// instead of a generic connection error after a long timeout.
    func checkServer() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("status"))
        request.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode < 500 else {
                throw AppiumError.invalidResponse
            }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let value = json?["value"] as? [String: Any]
            serverVersion = (value?["build"] as? [String: Any])?["version"] as? String
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AppiumError.serverUnreachable(baseURL.absoluteString)
        }
    }

    func createSession(
        configuration: ScannerConfiguration
    ) async throws -> String {

        let url =
            baseURL
                .appendingPathComponent("session")

        var request =
            URLRequest(
                url: url
            )

        request.httpMethod =
            "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )

        // The first WebDriverAgent build on a physical iPhone can take
        // several minutes; UiAutomator2 installs its server on first use.
        request.timeoutInterval =
            configuration.platform == .ios ? 600 : 240

        // A session left by a crashed or stopped scan holds the device.
        await releaseSessions(forUDID: configuration.udid)

        let body = sessionBody(for: configuration)

        request.httpBody =
            try JSONSerialization.data(
                withJSONObject:
                    body
            )

        do {

            let (
                data,
                response
            ) =
                try await URLSession.shared.data(
                    for: request
                )

            trace(
                "Appium response received."
            , Log.appium)

            let statusCode =
                (
                    response
                    as? HTTPURLResponse
                )?.statusCode ?? 0

            trace(
                "HTTP Status: \(statusCode)"
            , Log.appium)

            if (200...299).contains(
                statusCode
            ) {

                guard let json =
                        try JSONSerialization
                            .jsonObject(
                                with: data
                            )
                        as? [String: Any]
                else {
                    throw AppiumError.invalidResponse
                }

                trace(
                    "Appium JSON response received."
                , Log.appium)

                if let value =
                    json["value"]
                    as? [String: Any],

                   let sessionID =
                    value["sessionId"]
                    as? String {

                    self.sessionID =
                        sessionID
                    Self.openSessions.append((baseURL, sessionID))
                    RememberedSessions.remember(sessionID, udid: configuration.udid)

                    configureSession(
                        capabilities: value["capabilities"] as? [String: Any],
                        configuration: configuration
                    )

                    return sessionID
                }

                if let sessionID =
                    json["sessionId"]
                    as? String {

                    self.sessionID =
                        sessionID
                    Self.openSessions.append((baseURL, sessionID))
                    RememberedSessions.remember(sessionID, udid: configuration.udid)

                    configureSession(
                        capabilities: json["capabilities"] as? [String: Any],
                        configuration: configuration
                    )

                    return sessionID
                }
                trace(
                    String(
                        data: data,
                        encoding: .utf8
                    ) ?? ""
                , Log.appium)

                throw AppiumError.invalidResponse
            }

            var message = extractErrorMessage(from: data)
            Log.appium.error("Session could not be created (HTTP \(statusCode)): \(message, privacy: .public)")

            // The usual physical-iPhone failure: WebDriverAgent cannot be
            // signed because no team is configured.
            let lower = message.lowercased()
            if configuration.platform == .ios,
               configuration.xcodeOrgID.isEmpty,
               lower.contains("xcodebuild") || lower.contains("code 65") || lower.contains("signing") || lower.contains("webdriveragent") {
                message += "\n\nWebDriverAgent could not be built for this device. For a physical iPhone, enter your Apple Team ID in Settings (⌘,) so it can be signed."
            }

            throw AppiumError.appiumError(
                statusCode: statusCode,
                message: message
            )

        } catch let error
            as AppiumError {
            
            throw error

        } catch {

            // Timed out or stopped: Appium may still finish creating the
            // session after we gave up. Release it so the device is not held.
            let udid = configuration.udid
            await DeviceRestore.run {
                await self.releaseSessions(forUDID: udid)
            }
            throw error
        }
    }

    /// Deletes sessions left on the device by an earlier scan: first the
    /// ones this app created and remembered (always works), then any others
    /// the server lists (Appium 3 only lists sessions when started with
    /// `--allow-insecure session_discovery`).
    func releaseSessions(forUDID udid: String) async {
        for sessionID in RememberedSessions.ids(forUDID: udid) {
            var delete = URLRequest(url: baseURL.appendingPathComponent("session").appendingPathComponent(sessionID))
            delete.httpMethod = "DELETE"
            delete.timeoutInterval = 30
            _ = try? await URLSession.shared.data(for: delete)
            RememberedSessions.forget(sessionID)
            Log.appium.info("Released remembered Appium session \(sessionID, privacy: .public)")
        }

        for path in ["appium/sessions", "sessions"] {
            var request = URLRequest(url: baseURL.appendingPathComponent(path))
            request.timeoutInterval = 10
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessions = json["value"] as? [[String: Any]]
            else { continue }

            for session in sessions {
                guard let id = session["id"] as? String,
                      let capabilities = session["capabilities"] as? [String: Any],
                      (capabilities["udid"] as? String ?? capabilities["appium:udid"] as? String) == udid
                else { continue }
                var delete = URLRequest(url: baseURL.appendingPathComponent("session").appendingPathComponent(id))
                delete.httpMethod = "DELETE"
                delete.timeoutInterval = 30
                _ = try? await URLSession.shared.data(for: delete)
                Log.appium.info("Released leftover Appium session \(id, privacy: .public) for \(udid, privacy: .private)")
            }
            return
        }
    }

    // MARK: - Quit

    /// Sessions open in this process, deleted when the app quits.
    private static var openSessions: [(baseURL: URL, sessionID: String)] = []

    /// Deletes open sessions before the app exits. Blocks for at most a few
    /// seconds: it runs from the terminate notification, where async work
    /// would never complete.
    static func deleteOpenSessionsBeforeQuit() {
        let group = DispatchGroup()
        for (baseURL, sessionID) in openSessions {
            var request = URLRequest(url: baseURL.appendingPathComponent("session").appendingPathComponent(sessionID))
            request.httpMethod = "DELETE"
            request.timeoutInterval = 3
            group.enter()
            URLSession.shared.dataTask(with: request) { _, _, _ in group.leave() }.resume()
        }
        _ = group.wait(timeout: .now() + 4)
        openSessions.removeAll()
    }

    func getScreenshot() async throws -> Data {
        try await retryingTransientFailure { try await self.getScreenshotOnce() }
    }

    private func getScreenshotOnce() async throws -> Data {

        guard let sessionID = sessionID else {
            throw AppiumError.noActiveSession
        }

        let url = baseURL
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("screenshot")

        var request = URLRequest(url: url)

        request.httpMethod = "GET"

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        let (data, response) =
            try await URLSession.shared.data(
                for: request
            )
        try validateResponse(
            response,
            data: data
        )

        guard
            let json =
                try JSONSerialization.jsonObject(
                    with: data
                ) as? [String: Any],

            let base64String =
                json["value"] as? String,

            let imageData =
                Data(
                    base64Encoded:
                        base64String
                )
        else {

            throw AppiumError.invalidResponse
        }

        return imageData
    }
    

    // MARK: - Get Source
    func getSource() async throws -> String {
        try await retryingTransientFailure { try await self.getSourceOnce() }
    }

    private func getSourceOnce() async throws -> String {

        guard let sessionID else {
            throw AppiumError.noActiveSession
        }

        let url =
            baseURL
                .appendingPathComponent(
                    "session"
                )
                .appendingPathComponent(
                    sessionID
                )
                .appendingPathComponent(
                    "source"
                )

        var request =
            URLRequest(
                url: url
            )

        request.httpMethod =
            "GET"

        request.timeoutInterval =
            60

        let (
            data,
            response
        ) =
            try await URLSession.shared.data(
                for: request
            )

        try validateResponse(
            response,
            data: data
        )

        guard let json =
                try JSONSerialization
                    .jsonObject(
                        with: data
                    )
                as? [String: Any],

              let source =
                json["value"]
                as? String
        else {
            throw AppiumError.invalidResponse
        }

        trace(
            "UI source received."
        , Log.appium)

        trace(
            "Source length: \(source.count)"
        , Log.appium)

        return source
    }

    // MARK: - Device Orientation

    func getOrientation() async throws -> String {
        try await retryingTransientFailure { try await self.getOrientationOnce() }
    }

    private func getOrientationOnce() async throws -> String {
        guard let sessionID else {
            throw AppiumError.noActiveSession
        }

        let url = baseURL
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("orientation")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = json["value"] as? String
        else {
            throw AppiumError.invalidResponse
        }

        return value.uppercased()
    }

    func setOrientation(_ orientation: String) async throws {
        guard let sessionID else {
            throw AppiumError.noActiveSession
        }

        let normalized = orientation.uppercased()
        guard normalized == "PORTRAIT" || normalized == "LANDSCAPE" else {
            throw AppiumError.appiumError(statusCode: 400, message: "Unsupported orientation: \(orientation)")
        }

        let url = baseURL
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("orientation")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["orientation": normalized])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
    }

    // MARK: - Delete Session

    func deleteSession() async throws {

        guard let sessionID else {
            return
        }

        let url =
            baseURL
                .appendingPathComponent(
                    "session"
                )
                .appendingPathComponent(
                    sessionID
                )

        var request =
            URLRequest(
                url: url
            )

        request.httpMethod =
            "DELETE"

        request.timeoutInterval =
            30

        trace("", Log.appium)
        trace(
            "Deleting Appium session..."
        , Log.appium)

        let (
            data,
            response
        ) =
            try await URLSession.shared.data(
                for: request
            )

        try validateResponse(
            response,
            data: data
        )
        
        Self.openSessions.removeAll { $0.sessionID == sessionID }
        RememberedSessions.forget(sessionID)
        self.sessionID =
            nil

        Log.appium.info("Appium session deleted.")
    }

    // MARK: - Validate Response
    /// Retries a read-only request once after a transient failure: a dropped
    /// connection, a timeout, or a 5xx from a WebDriverAgent/UiAutomator2
    /// server that is restarting. One blip must not abort a 100-screen crawl.
    private func retryingTransientFailure<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            guard Self.isTransient(error) else { throw error }
            Log.appium.info("Retrying after transient Appium error: \(error.localizedDescription, privacy: .public)")
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return try await operation()
        }
    }

    private static func isTransient(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let urlError = error as? URLError {
            return [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet]
                .contains(urlError.code)
        }
        if case AppiumError.appiumError(let statusCode, _) = error {
            return statusCode >= 500
        }
        return false
    }

    private func validateResponse(
        _ response: URLResponse,
        data: Data
    ) throws {

        guard let httpResponse =
                response
                as? HTTPURLResponse
        else {
            throw AppiumError.invalidResponse
        }

        let statusCode =
            httpResponse.statusCode

        guard (200...299).contains(
            statusCode
        )
        else {

            _ =
                String(
                    data: data,
                    encoding: .utf8
                ) ?? ""

            throw AppiumError.appiumError(
                statusCode:
                    statusCode,
                message:
                    extractErrorMessage(
                        from: data
                    )
            )
        }
    }
    
    /// Presses at `start`, slides to `end` and releases there: the gesture a
    /// user makes to cancel an accidental press (pointer cancellation).
    func pressAndSlideAway(from start: CGPoint, to end: CGPoint) async throws {
        guard let sessionID = sessionID else {
            throw AppiumError.noActiveSession
        }
        var request = URLRequest(url: baseURL
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("actions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let payload: [String: Any] = [
            "actions": [[
                "type": "pointer",
                "id": "a11yCancellationPointer",
                "parameters": ["pointerType": "touch"],
                "actions": [
                    ["type": "pointerMove", "duration": 0, "x": Int(start.x * displayScale), "y": Int(start.y * displayScale)],
                    ["type": "pointerDown", "button": 0],
                    ["type": "pause", "duration": 150],
                    ["type": "pointerMove", "duration": 250, "x": Int(end.x * displayScale), "y": Int(end.y * displayScale)],
                    ["type": "pointerUp", "button": 0]
                ]
            ]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
    }

    func tap(at point: CGPoint) async throws {

        guard let sessionID = sessionID else {
            throw AppiumError.noActiveSession
        }

        let url = baseURL
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("actions")

        var request = URLRequest(url: url)

        request.httpMethod = "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        let payload: [String: Any] = [
            "actions": [
                [
                    "type": "pointer",
                    "id": "a11yCrawlerPointer",
                    "parameters": [
                        "pointerType": "touch"
                    ],
                    "actions": [
                        [
                            "type": "pointerMove",
                            "duration": 0,
                            "x": Int(point.x * displayScale),
                            "y": Int(point.y * displayScale)
                        ],
                        [
                            "type": "pointerDown",
                            "button": 0
                        ],
                        [
                            "type": "pause",
                            "duration": 100
                        ],
                        [
                            "type": "pointerUp",
                            "button": 0
                        ]
                    ]
                ]
            ]
        ]

        request.httpBody =
            try JSONSerialization.data(
                withJSONObject: payload
            )

        let (data, response) =
            try await URLSession.shared.data(
                for: request
            )

        try validateResponse(
            response,
            data: data
        )
    }


    // MARK: - Keyboard input

    /// Sends a single W3C Tab key action to the active Appium session.
    /// On iOS XCUITest, this is used by the keyboard-focus probe to advance
    /// the native keyboard focus without tapping a particular control.
    func pressTab() async throws {
        try await pressKey(value: "\u{E004}")
    }

    /// Activates the keyboard-focused control: Space on iOS (Full Keyboard
    /// Access), Enter on Android.
    func pressActivate() async throws {
        try await pressKey(value: platform == .ios ? "\u{E00D}" : "\u{E007}")
    }

    private func pressKey(value: String) async throws {
        guard let sessionID else {
            throw AppiumError.noActiveSession
        }

        let url = baseURL
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("actions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let payload: [String: Any] = [
            "actions": [[
                "type": "key",
                "id": "accessibilityScannerKeyboard",
                "actions": [
                    ["type": "keyDown", "value": value],
                    ["type": "keyUp", "value": value]
                ]
            ]]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
    }

    func goBack() async throws {

        guard let sessionID = sessionID else {
            throw AppiumError.noActiveSession
        }

        let url = baseURL
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("back")

        var request = URLRequest(url: url)

        request.httpMethod = "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        request.httpBody = Data("{}".utf8)

        let (data, response) =
            try await URLSession.shared.data(
                for: request
            )

        try validateResponse(
            response,
            data: data
        )
    }
    
    func scrollUp() async throws {
        if platform == .android {
            try await androidScroll(direction: "up", percent: 0.5)
            return
        }
        guard let sessionID = sessionID else {
            throw AppiumError.noActiveSession
        }

        let url = baseURL
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("execute")
            .appendingPathComponent("sync")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        let payload: [String: Any] = [
            "script": "mobile: scroll",
            "args": [
                [
                    "direction": "up"
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(
            withJSONObject: payload
        )

        let (data, response) =
            try await URLSession.shared.data(
                for: request
            )

        try validateResponse(
            response,
            data: data
        )
    }
    
    // MARK: - Scroll Down
    func scrollDown() async throws {
        if platform == .android {
            try await androidScroll(direction: "down", percent: 0.85)
            return
        }

        guard let sessionID = sessionID else {
            throw AppiumError.noActiveSession
        }

        let url = baseURL
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("execute")
            .appendingPathComponent("sync")

        var request = URLRequest(url: url)

        request.httpMethod = "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        let payload: [String: Any] = [

            "script": "mobile: scroll",

            "args": [
                [
                    "direction": "down",

                    // Approximately one viewport.
                    //
                    // This is the key change.
                    "distance": 0.85
                ]
            ]
        ]

        request.httpBody =
            try JSONSerialization.data(
                withJSONObject: payload
            )

        let (data, response) =
            try await URLSession.shared.data(
                for: request
            )

        try validateResponse(
            response,
            data: data
        )
    }
    
    
    func tapElement(
        usingXPath xpath: String
    ) async throws {

        guard let sessionID = sessionID else {
            throw AppiumError.noActiveSession
        }

        // Find element
        let findURL = baseURL
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("element")

        var findRequest = URLRequest(url: findURL)

        findRequest.httpMethod = "POST"

        findRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        let findPayload: [String: Any] = [
            "using": "xpath",
            "value": xpath
        ]

        findRequest.httpBody =
            try JSONSerialization.data(
                withJSONObject: findPayload
            )

        let (findData, findResponse) =
            try await URLSession.shared.data(
                for: findRequest
            )

        try validateResponse(
            findResponse,
            data: findData
        )

        guard
            let findJSON =
                try JSONSerialization.jsonObject(
                    with: findData
                ) as? [String: Any],
            let value =
                findJSON["value"] as? [String: Any]
        else {
            throw AppiumError.invalidResponse
        }

        let elementID =
            value["element-6066-11e4-a52e-4f735466cecf"]
            as? String
            ??
            value["ELEMENT"] as? String

        guard let elementID else {
            throw AppiumError.invalidResponse
        }

        // Click element
        let clickURL = baseURL
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("element")
            .appendingPathComponent(elementID)
            .appendingPathComponent("click")

        var clickRequest =
            URLRequest(url: clickURL)

        clickRequest.httpMethod = "POST"

        clickRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        clickRequest.httpBody =
            Data("{}".utf8)

        let (clickData, clickResponse) =
            try await URLSession.shared.data(
                for: clickRequest
            )

        try validateResponse(
            clickResponse,
            data: clickData
        )
    }

    // MARK: - Launch / Activate App

    /// Brings the app under test to the foreground, launching it if needed.
    /// Works on both platforms (`mobile: activateApp`):
    ///  - iOS (XCUITest) takes `bundleId`
    ///  - Android (UiAutomator2) takes `appId`
    /// Failure is non-fatal: the session capabilities already request a launch.
    func activateApp(bundleID: String) async {

        guard let sessionID else { return }

        let url = baseURL
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("execute")
            .appendingPathComponent("sync")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let argument: [String: Any]

        switch platform {
        case .ios:
            argument = ["bundleId": bundleID]
        case .android:
            argument = ["appId": bundleID]
        }

        let payload: [String: Any] = [
            "script": "mobile: activateApp",
            "args": [argument]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            try validateResponse(response, data: data)
        } catch {
            trace("Warning: could not activate app \(bundleID): \(error.localizedDescription)", Log.appium)
        }
    }

    // MARK: - App lifecycle (runtime probes)

    /// Terminates the app (`mobile: terminateApp`). Throws on failure.
    func terminateApp(bundleID: String) async throws {
        let key = platform == .ios ? "bundleId" : "appId"
        try await executeMobile("mobile: terminateApp", arguments: [key: bundleID])
    }

    /// Launches the app with launch arguments (`mobile: launchApp`, iOS only).
    /// On Android the app is started without arguments.
    func launchApp(bundleID: String, arguments: [String]) async throws {
        switch platform {
        case .ios:
            var argument: [String: Any] = ["bundleId": bundleID]
            if !arguments.isEmpty { argument["arguments"] = arguments }
            try await executeMobile("mobile: launchApp", arguments: argument)
        case .android:
            await activateApp(bundleID: bundleID)
        }
    }

    /// Bundle ID (iOS) or package (Android) of the app in the foreground, or
    /// nil when the driver cannot report it.
    func foregroundAppID() async -> String? {
        switch platform {
        case .ios:
            let info = try? await executeMobile("mobile: activeAppInfo", arguments: [:]) as? [String: Any]
            return info?["bundleId"] as? String
        case .android:
            if let package = try? await executeMobile("mobile: getCurrentPackage", arguments: [:]) as? String {
                return package
            }
            return try? await legacyCurrentPackage()
        }
    }

    /// Older UiAutomator2 drivers only expose the current package here.
    private func legacyCurrentPackage() async throws -> String? {
        guard let sessionID else { throw AppiumError.noActiveSession }
        let url = baseURL
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("appium")
            .appendingPathComponent("device")
            .appendingPathComponent("current_package")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["value"] as? String
    }

    @discardableResult
    private func executeMobile(_ script: String, arguments: [String: Any]) async throws -> Any? {
        guard let sessionID else {
            throw AppiumError.noActiveSession
        }

        let url = baseURL
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("execute")
            .appendingPathComponent("sync")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["script": script, "args": [arguments]]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["value"]
    }

    // MARK: - Platform support

    /// Source parser matching the active session's platform.
    func makeParser() -> any AccessibilitySourceParser {
        switch platform {
        case .ios:
            return WDAElementParser()
        case .android:
            return AndroidElementParser(displayScale: displayScale)
        }
    }

    /// Simulator UDIDs are UUIDs (8-4-4-4-12); physical ones are not.
    static func isSimulatorUDID(_ udid: String) -> Bool {
        let parts = udid.split(separator: "-").map(\.count)
        return parts == [8, 4, 4, 4, 12]
    }

    /// A stable port in 8101–8199 for this device (FNV-1a of the UDID).
    /// Stays clear of 8200, UiAutomator2's default system port.
    static func wdaPort(forUDID udid: String) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in udid.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return 8101 + Int(hash % 99)
    }

    private func sessionBody(
        for configuration: ScannerConfiguration
    ) -> [String: Any] {

        var capabilities: [String: Any]

        switch configuration.platform {

        case .ios:
            capabilities = [
                "platformName": "iOS",
                "appium:automationName": "XCUITest",
                "appium:deviceName": configuration.deviceName,
                "appium:udid": configuration.udid,
                "appium:bundleId": configuration.bundleID,
                "appium:noReset": true,
                "appium:autoLaunch": configuration.autoLaunch,
                // Full and Limited scans start the app from its launch screen:
                // with noReset alone, an app that is already running would
                // resume on whatever page was open. Current Page mode
                // (autoLaunch false) attaches to the open page instead.
                "appium:forceAppLaunch": configuration.autoLaunch,
                "appium:newCommandTimeout": 300,
                "appium:showXcodeLog": showXcodeLog,
                "appium:settings": [
                    "includeHittableInPageSource": true,
                    // Custom accessibility actions are the VoiceOver
                    // alternative to swipe and multi-finger gestures.
                    "includeCustomActionsInPageSource": true
                ]
            ]

            // A physical iPhone's WebDriverAgent is forwarded to a port on
            // this Mac (8100 by default). Simulators also use 8100 directly,
            // so with both on 8100 a simulator scan reaches the phone. Give
            // each physical device its own forwarding port; simulators keep
            // 8100 (changing theirs would force a WebDriverAgent rebuild).
            if !Self.isSimulatorUDID(configuration.udid) {
                capabilities["appium:wdaLocalPort"] = Self.wdaPort(forUDID: configuration.udid)
            }

            // Only physical iPhones need WebDriverAgent signed. Sending an
            // empty team ID would override a WebDriverAgent already set up
            // in Xcode, so it is only sent once set in Settings.
            if !configuration.xcodeOrgID.isEmpty {
                capabilities["appium:xcodeOrgId"] = configuration.xcodeOrgID
                capabilities["appium:xcodeSigningId"] = configuration.xcodeSigningID
            }

        case .android:
            capabilities = [
                "platformName": "Android",
                "appium:automationName": "UiAutomator2",
                "appium:deviceName": configuration.deviceName,
                "appium:udid": configuration.udid,
                "appium:appPackage": configuration.bundleID,
                "appium:appWaitActivity": "*",
                "appium:noReset": true,
                "appium:newCommandTimeout": 300,
                // Launch control is configurable so Current Page mode can attach
                // without replacing the page the tester has already opened.
                "appium:autoLaunch": configuration.autoLaunch,
                // Launch the app as soon as the session starts, unless Current Page
                // mode intentionally attaches to the page already on screen.
                "appium:forceAppLaunch": configuration.autoLaunch,
                "appium:shouldTerminateApp": true,
                // Expose AccessibilityNodeInfo extras such as roleDescription
                // used by React Native and other cross-platform semantics.
                "appium:settings": [
                    "includeExtrasInPageSource": true,
                    "includeA11yActionsInPageSource": true
                ]
            ]

            if let activity = configuration.appActivity, !activity.isEmpty {
                capabilities["appium:appActivity"] = activity
            }
        }

        return [
            "capabilities": [
                "alwaysMatch": capabilities
            ]
        ]
    }

    /// Records the platform and, for Android, the pixel→dp scale.
    private func configureSession(
        capabilities: [String: Any]?,
        configuration: ScannerConfiguration
    ) {

        platform = configuration.platform
        displayScale = 1

        deviceOSVersion = capabilities?["platformVersion"] as? String
            ?? capabilities?["appium:platformVersion"] as? String
        automationName = capabilities?["automationName"] as? String
            ?? capabilities?["appium:automationName"] as? String
        if let manufacturer = capabilities?["deviceManufacturer"] as? String,
           let model = capabilities?["deviceModel"] as? String {
            deviceModel = "\(manufacturer) \(model)"
        } else {
            deviceModel = capabilities?["deviceModel"] as? String
        }

        guard platform == .android else { return }

        func number(_ any: Any?) -> Double? {
            if let value = any as? Double { return value }
            if let value = any as? Int { return Double(value) }
            if let value = any as? String { return Double(value) }
            return nil
        }

        if let ratio = number(capabilities?["pixelRatio"]), ratio > 0 {
            displayScale = CGFloat(ratio)
        } else if let dpi = number(capabilities?["deviceScreenDensity"]), dpi > 0 {
            displayScale = CGFloat(dpi / 160.0)
        } else if let dpi = configuration.displayDensity, dpi > 0 {
            displayScale = CGFloat(Double(dpi) / 160.0)
        } else {
            trace("Warning: Android display density unavailable; frames stay in pixels.", Log.appium)
        }

        trace("Android display scale: \(displayScale)", Log.appium)
    }

    private func windowRectPixels() async throws -> CGRect {

        guard let sessionID else {
            throw AppiumError.noActiveSession
        }

        let url = baseURL
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("window")
            .appendingPathComponent("rect")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        try validateResponse(response, data: data)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = json["value"] as? [String: Any],
            let width = value["width"] as? Double ?? (value["width"] as? Int).map(Double.init),
            let height = value["height"] as? Double ?? (value["height"] as? Int).map(Double.init)
        else {
            throw AppiumError.invalidResponse
        }

        return CGRect(x: 0, y: 0, width: width, height: height)
    }

    /// Android scrolling via `mobile: scrollGesture` (UiAutomator2).
    private func androidScroll(
        direction: String,
        percent: Double
    ) async throws {

        guard let sessionID else {
            throw AppiumError.noActiveSession
        }

        let rect = try await windowRectPixels()

        let url = baseURL
            .appendingPathComponent("session")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("execute")
            .appendingPathComponent("sync")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "script": "mobile: scrollGesture",
            "args": [
                [
                    "left": Int(rect.width * 0.1),
                    "top": Int(rect.height * 0.2),
                    "width": Int(rect.width * 0.8),
                    "height": Int(rect.height * 0.6),
                    "direction": direction,
                    "percent": percent
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        try validateResponse(response, data: data)
    }

    // MARK: - Extract Error Message
    private func extractErrorMessage(
        from data: Data
    ) -> String {

        guard let json =
                try? JSONSerialization
                    .jsonObject(
                        with: data
                    )
                as? [String: Any]
        else {

            return String(
                data: data,
                encoding: .utf8
            )
            ?? "Unknown Appium error."
        }

        if let value =
            json["value"]
            as? [String: Any] {

            if let message =
                value["message"]
                as? String {

                return message
            }

            if let error =
                value["error"]
                as? String {

                return error
            }
        }

        // Alternative format

        if let message =
            json["message"]
            as? String {

            return message
        }

        return String(
            data: data,
            encoding: .utf8
        )
        ?? "Unknown Appium error."
    }
}

// MARK: - Appium Errors

enum AppiumError:
    Error,
    LocalizedError {

    case noActiveSession

    case invalidResponse

    case serverUnreachable(String)

    case appiumError(
        statusCode: Int,
        message: String
    )

    var errorDescription: String? {

        switch self {

        case .noActiveSession:

            return "No active Appium session."

        case .invalidResponse:

            return "Appium returned an invalid response."

        case .serverUnreachable(let url):

            return "No Appium server is running at \(url). Start it in Terminal with `appium`, or change the server URL in Settings (⌘,)."

        case .appiumError(
            let statusCode,
            let message
        ):

            return """
            Appium returned HTTP \(statusCode).

            \(message)
            """
        }
    }
}

/// Session IDs this app created, per device, kept until the session is
/// deleted. A crash or force-quit leaves them here so the next scan of the
/// device can release them.
nonisolated enum RememberedSessions {
    private static let key = "appium.rememberedSessions"

    private static var all: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func remember(_ sessionID: String, udid: String) {
        var values = all
        values[sessionID] = udid
        all = values
    }

    static func forget(_ sessionID: String) {
        var values = all
        values.removeValue(forKey: sessionID)
        all = values
    }

    static func ids(forUDID udid: String) -> [String] {
        all.filter { $0.value == udid }.map(\.key)
    }
}
