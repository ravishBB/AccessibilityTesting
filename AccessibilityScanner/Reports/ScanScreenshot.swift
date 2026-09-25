//
//  ScanScreenshot.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 25/09/26.
//

import Foundation

struct ScanScreenshot: Codable {
    let imageData: Data
    let width: Double
    let height: Double

    init(
        imageData: Data,
        width: Double,
        height: Double
    ) {
        self.imageData = imageData
        self.width = width
        self.height = height
    }
}
