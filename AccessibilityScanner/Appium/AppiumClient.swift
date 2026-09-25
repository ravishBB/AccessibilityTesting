//
//  AppiumClient.swift
//  AccessibilityScannerDemo
//
//  Created by Ravish Kumar on 22/09/26.
//

import Foundation

final class AppiumClient {

    private let baseURL: URL

    private(set) var sessionID: String?

    // ============================================================
    // WDA / Apple Signing Configuration
    // ============================================================
    
    private let xcodeOrgId = "EJ5R49N3EY"
    
    private let xcodeSigningId = "Apple Development"

    /*
     This is extremely useful while diagnosing
     xcodebuild failures such as exit code 65.
     */
    private let showXcodeLog = true

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    // MARK: - Create Session

    func createSession(
        configuration: ScannerConfiguration
    ) async throws -> String {

        let url =
            baseURL
                .appendingPathComponent("session")

        print("")
        print("======================================")
        print("CONNECTING TO APPIUM")
        print("======================================")
        print("URL: \(url)")
        print("Bundle ID: \(configuration.bundleID)")
        print("Device: \(configuration.deviceName)")
        print("UDID: \(configuration.udid)")
        print("")
        print("WDA Configuration")
        print("--------------------------------------")
        print("Xcode Team ID: \(xcodeOrgId)")
        print("Xcode Signing ID: \(xcodeSigningId)")
        print("Show Xcode Log: \(showXcodeLog)")
        print("--------------------------------------")
        print("")
        print("Sending POST /session...")

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

        // ========================================================
        // Appium / XCUITest Capabilities
        // ========================================================

        let body: [String: Any] = [

            "capabilities": [

                "alwaysMatch": [

                    // ------------------------------------------------
                    // Platform
                    // ------------------------------------------------

                    "platformName": "iOS",

                    "appium:automationName":
                        "XCUITest",

                    // ------------------------------------------------
                    // Target Device
                    // ------------------------------------------------

                    "appium:deviceName":
                        configuration.deviceName,

                    "appium:udid":
                        configuration.udid,

                    // ------------------------------------------------
                    // Target Application
                    // ------------------------------------------------

                    "appium:bundleId":
                        configuration.bundleID,

                    // ------------------------------------------------
                    // Session Behaviour
                    // ------------------------------------------------

                    "appium:noReset":
                        true,

                    "appium:newCommandTimeout":
                        300,

                    // ------------------------------------------------
                    // WebDriverAgent Signing
                    // ------------------------------------------------

                    "appium:xcodeOrgId":
                        xcodeOrgId,

                    "appium:xcodeSigningId":
                        xcodeSigningId,

                    // ------------------------------------------------
                    // Debugging
                    // ------------------------------------------------

                    "appium:showXcodeLog":
                        showXcodeLog
                ]
            ]
        ]

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

            // ====================================================
            // Successful response
            // ====================================================

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

                // ------------------------------------------------
                // Appium 2 / W3C response
                // ------------------------------------------------

                if let value =
                    json["value"]
                    as? [String: Any],

                   let sessionID =
                    value["sessionId"]
                    as? String {

                    self.sessionID =
                        sessionID

                    print("")
                    print(
                        "======================================"
                    )
                    print(
                        "APPIUM SESSION CREATED"
                    )
                    print(
                        "======================================"
                    )
                    print(
                        "Session ID: \(sessionID)"
                    )
                    print(
                        "======================================"
                    )

                    return sessionID
                }

                // ------------------------------------------------
                // Older Appium response format
                // ------------------------------------------------

                if let sessionID =
                    json["sessionId"]
                    as? String {

                    self.sessionID =
                        sessionID

                    print("")
                    print(
                        "======================================"
                    )
                    print(
                        "APPIUM SESSION CREATED"
                    )
                    print(
                        "======================================"
                    )
                    print(
                        "Session ID: \(sessionID)"
                    )
                    print(
                        "======================================"
                    )

                    return sessionID
                }

                print(
                    "Unexpected Appium response:"
                )

                print(
                    String(
                        data: data,
                        encoding: .utf8
                    ) ?? ""
                )

                throw AppiumError.invalidResponse
            }

            // ====================================================
            // Appium error response
            // ====================================================

            let errorText =
                String(
                    data: data,
                    encoding: .utf8
                ) ?? ""

            print("")
            print(
                "======================================"
            )
            print(
                "APPIUM ERROR RESPONSE"
            )
            print(
                "======================================"
            )
            print(
                "HTTP Status: \(statusCode)"
            )
            print(
                errorText
            )
            print(
                "======================================"
            )

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

            print("")
            print(
                "======================================"
            )
            print(
                "APPIUM SESSION CREATION FAILED"
            )
            print(
                "======================================"
            )
            print(
                error.localizedDescription
            )
            print(
                "======================================"
            )

            throw error

        } catch {

            print("")
            print(
                "======================================"
            )
            print(
                "APPIUM CONNECTION FAILED"
            )
            print(
                "======================================"
            )
            print(
                error.localizedDescription
            )
            print(
                "======================================"
            )

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

        print("")
        print(
            "======================================"
        )
        print(
            "GETTING UI SOURCE"
        )
        print(
            "======================================"
        )
        print(
            "URL: \(url)"
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

        // IMPORTANT:
        // Use self.sessionID because the
        // local sessionID above is a let constant.

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

            let responseText =
                String(
                    data: data,
                    encoding: .utf8
                ) ?? ""

            print("")
            print(
                "======================================"
            )
            print(
                "APPIUM HTTP ERROR"
            )
            print(
                "======================================"
            )
            print(
                "HTTP Status: \(statusCode)"
            )
            print(
                responseText
            )
            print(
                "======================================"
            )

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

        // Appium/W3C format:
        //
        // {
        //   "value": {
        //     "error": "...",
        //     "message": "..."
        //   }
        // }

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
