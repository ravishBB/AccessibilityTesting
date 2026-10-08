//
//  ScannerConfiguration.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 22/09/26.
//

import Foundation

struct ScannerConfiguration {

    let appiumURL: URL

    /// iOS bundle identifier or Android application package name.
    let bundleID: String
    let deviceName: String
    let udid: String

    let platform: MobilePlatform

    /// Android launcher activity. Optional: Appium resolves it when omitted.
    let appActivity: String?

    /// Android display density in dpi. Fallback when Appium does not report it.
    let displayDensity: Int?
    /// Whether Appium should launch the application when creating the session.
    /// False is used for Current Page mode so the scanner can attach to the page
    /// the tester has already opened.
    let autoLaunch: Bool

    /// iOS physical-device signing for WebDriverAgent.
    let xcodeOrgID: String
    let xcodeSigningID: String

    init(
        appiumURL: URL = URL(
            string: "http://127.0.0.1:4723"
        )!,
        bundleID: String,
        deviceName: String,
        udid: String,
        platform: MobilePlatform = .ios,
        appActivity: String? = nil,
        displayDensity: Int? = nil,
        autoLaunch: Bool = true,
        xcodeOrgID: String = "EJ5R49N3EY",
        xcodeSigningID: String = "Apple Development"
    ) {
        self.appiumURL = appiumURL
        self.bundleID = bundleID
        self.deviceName = deviceName
        self.udid = udid
        self.platform = platform
        self.appActivity = appActivity
        self.displayDensity = displayDensity
        self.autoLaunch = autoLaunch
        self.xcodeOrgID = xcodeOrgID
        self.xcodeSigningID = xcodeSigningID
    }
}
