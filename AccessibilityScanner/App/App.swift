//
//  App.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 23/09/26.
//

import Foundation

struct InstalledApp: Identifiable, Hashable {

    let id: String
    let name: String
    let bundleID: String

    var displayName: String {
        return "\(name) — \(bundleID)"
    }
}
