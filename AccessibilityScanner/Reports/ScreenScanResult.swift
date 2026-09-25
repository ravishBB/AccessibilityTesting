//
//  ScreenScanResult.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 24/09/26.
//

import Foundation

struct ScreenScanResult: Identifiable, Codable {
    let id: UUID
    let name: String
    let elementCount: Int
    let evaluations: [AccessibilityRuleEvaluation]

    // Screenshot information
    let screenshot: ScanScreenshot?

    // Elements highlighted on the screenshot
    let annotations: [ScreenshotAnnotation]

    init(
        name: String,
        elementCount: Int,
        evaluations: [AccessibilityRuleEvaluation],
        screenshot: ScanScreenshot? = nil,
        annotations: [ScreenshotAnnotation] = []
    ) {
        self.id = UUID()
        self.name = name
        self.elementCount = elementCount
        self.evaluations = evaluations
        self.screenshot = screenshot
        self.annotations = annotations
    }

    var failures: Int {
        evaluations.filter {
            $0.status == .fail
        }.count
    }

    var warnings: Int {
        evaluations.filter {
            $0.status == .warning
        }.count
    }

    var validations: Int {
        evaluations.filter {
            $0.status == .validate
        }.count
    }

    var passes: Int {
        evaluations.filter {
            $0.status == .pass
        }.count
    }

    var affectedElements: Int {
        Set(
            evaluations
                .filter {
                    $0.status != .pass
                }
                .map {
                    $0.identifier +
                    "|" +
                    $0.elementType +
                    "|" +
                    $0.elementLabel
                }
        ).count
    }
}
