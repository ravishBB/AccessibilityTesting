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

    var isSimulator: Bool {
        type == .simulator
    }

    var isPhysical: Bool {
        type == .physical
    }

    var displayName: String {

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
