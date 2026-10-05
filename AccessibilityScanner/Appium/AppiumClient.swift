//
//  AppiumClient.swift
//  AccessibilityScannerDemo
//  Created by Ravish Kumar on 22/09/26.

import Foundation
import CoreGraphics

final class AppiumClient {

    private let baseURL: URL
    private(set) var sessionID: String?
    private let showXcodeLog = true

    /// Platform of the active session. Set by `createSession`.
    private(set) var platform: MobilePlatform = .ios

    /// Pixels per dp on Android (1 on iOS, where WDA already reports points).
    private(set) var displayScale: CGFloat = 1

    init(baseURL: URL) {
        self.baseURL = baseURL
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

        request.timeoutInterval =
            120

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

            print(
                "Appium response received."
            )

            let statusCode =
                (
                    response
                    as? HTTPURLResponse
                )?.statusCode ?? 0

            print(
                "HTTP Status: \(statusCode)"
            )

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

                print(
                    "Appium JSON response received."
                )

                if let value =
                    json["value"]
                    as? [String: Any],

                   let sessionID =
                    value["sessionId"]
                    as? String {

                    self.sessionID =
                        sessionID

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

                    configureSession(
                        capabilities: json["capabilities"] as? [String: Any],
                        configuration: configuration
                    )

                    return sessionID
                }
                print(
                    String(
                        data: data,
                        encoding: .utf8
                    ) ?? ""
                )

                throw AppiumError.invalidResponse
            }

            throw AppiumError.appiumError(
                statusCode:
                    statusCode,
                message:
                    extractErrorMessage(
                        from: data
                    )
            )

        } catch let error
            as AppiumError {
            
            throw error

        } catch {

            throw error
        }
    }
    
    func getScreenshot() async throws -> Data {

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

        print(
            "UI source received."
        )

        print(
            "Source length: \(source.count)"
        )

        return source
    }

    // MARK: - Device Orientation

    func getOrientation() async throws -> String {
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

        print("")
        print(
            "Deleting Appium session..."
        )

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
        
        self.sessionID =
            nil

        print(
            "Appium session deleted."
        )
    }

    // MARK: - Validate Response
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
            print("Warning: could not activate app \(bundleID): \(error.localizedDescription)")
        }
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
                "appium:newCommandTimeout": 300,
                "appium:xcodeOrgId": configuration.xcodeOrgID,
                "appium:xcodeSigningId": configuration.xcodeSigningID,
                "appium:showXcodeLog": showXcodeLog
            ]

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
                // Launch the app as soon as the session starts, even when it
                // is already running in the background (noReset alone can
                // leave it untouched).
                "appium:autoLaunch": true,
                "appium:forceAppLaunch": true,
                "appium:shouldTerminateApp": true
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
            print("Warning: Android display density unavailable; frames stay in pixels.")
        }

        print("Android display scale: \(displayScale)")
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
