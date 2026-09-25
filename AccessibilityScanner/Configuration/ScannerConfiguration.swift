//
//  ScannerConfiguration.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 22/09/26.
//

import Foundation

struct ScannerConfiguration {

    let appiumURL: URL
    let bundleID: String
    let deviceName: String
    let udid: String

    init(
        appiumURL: URL = URL(
            string: "http://127.0.0.1:4723"
        )!,
        bundleID: String,
        deviceName: String,
        udid: String
    ) {
        self.appiumURL = appiumURL
        self.bundleID = bundleID
        self.deviceName = deviceName
        self.udid = udid
    }
}
