//
//  AppiumClient.swift
//  AccessibilityScannerDemo
//  Created by Ravish Kumar on 22/09/26.

import Foundation

final class AppiumClient {

    private let baseURL: URL
    private(set) var sessionID: String?
    private let xcodeOrgId = "EJ5R49N3EY"
    private let xcodeSigningId = "Apple Development"
    private let showXcodeLog = true

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

        let body: [String: Any] = [

            "capabilities": [

                "alwaysMatch": [
                    "platformName": "iOS",
                    "appium:automationName":
                        "XCUITest",
                    "appium:deviceName":
                        configuration.deviceName,
                    "appium:udid":
                        configuration.udid,
                    "appium:bundleId":
                        configuration.bundleID,
                    "appium:noReset":
                        true,

                    "appium:newCommandTimeout":
                        300,
                    "appium:xcodeOrgId":
                        xcodeOrgId,

                    "appium:xcodeSigningId":
                        xcodeSigningId,
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

                    return sessionID
                }

                if let sessionID =
                    json["sessionId"]
                    as? String {

                    self.sessionID =
                        sessionID

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

            let errorText =
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
                            "x": Int(point.x),
                            "y": Int(point.y)
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
                    "direction": "down"
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
