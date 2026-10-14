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

    let platform: MobilePlatform
    let appActivity: String?
    let displayDensity: Int?
    let autoLaunch: Bool
    let xcodeOrgID: String
    let xcodeSigningID: String

    init(
        appiumURL: URL = ScannerSettings.appiumURL,
        bundleID: String,
        deviceName: String,
        udid: String,
        platform: MobilePlatform = .ios,
        appActivity: String? = nil,
        displayDensity: Int? = nil,
        autoLaunch: Bool = true,
        xcodeOrgID: String = ScannerSettings.teamID,
        xcodeSigningID: String = ScannerSettings.signingID
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
