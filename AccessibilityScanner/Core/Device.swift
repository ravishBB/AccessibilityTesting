//
//  Device.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 22/09/26.
//

import Foundation

struct Device: Identifiable, Hashable {

    enum DeviceType: String {
        case simulator
        case physical
    }

    let id: String
    let name: String
    let udid: String
    let state: String
    let type: DeviceType

    /// Platform of the device. Defaults to iOS so existing call sites keep working.
    var platform: MobilePlatform = .ios

    /// Android display density in dpi (from `adb shell wm density`), used to
    /// convert pixel bounds to dp when Appium does not report it.
    var displayDensity: Int? = nil

    var isSimulator: Bool {
        type == .simulator
    }

    var isPhysical: Bool {
        type == .physical
    }

    var displayName: String {

        if platform == .android {

            switch type {

            case .simulator:
                return "\(name) — Android Emulator"

            case .physical:
                return "\(name) — Android (Connected)"
            }
        }

        switch type {

        case .simulator:

            if state == "Booted" {
                return "\(name) — Booted"
            }

            return "\(name) — Simulator"

        case .physical:

            return "\(name) — Connected"
        }
    }
}
