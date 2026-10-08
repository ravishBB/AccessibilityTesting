//
//  ScanScreenshot.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 24/09/26.
//


import Foundation

struct ScanScreenshot: Codable {
    let imageData: Data
    let annotatedImageData: Data?
    let width: Double
    let height: Double
    let hierarchyWidth: Double
    let hierarchyHeight: Double

    init(
        imageData: Data,
        annotatedImageData: Data? = nil,
        width: Double,
        height: Double,
        hierarchyWidth: Double,
        hierarchyHeight: Double
    ) {
        self.imageData = imageData
        self.annotatedImageData = annotatedImageData
        self.width = width
        self.height = height
        self.hierarchyWidth = hierarchyWidth
        self.hierarchyHeight = hierarchyHeight
    }
}


struct ScreenshotViewport: Identifiable, Codable {
    let id: UUID
    let index: Int
    let screenshot: ScanScreenshot
    let annotations: [ScreenshotAnnotation]

    init(
        index: Int,
        screenshot: ScanScreenshot,
        annotations: [ScreenshotAnnotation] = []
    ) {
        self.id = UUID()
        self.index = index
        self.screenshot = screenshot
        self.annotations = annotations
    }
}
