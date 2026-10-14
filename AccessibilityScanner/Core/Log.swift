//
//  Log.swift
//  AccessibilityScanner
//
//  Unified logging. Debug-level messages are not persisted and cost almost
//  nothing in release builds; view them in Console.app or Xcode by filtering
//  on the subsystem.
//

import Foundation
import os

nonisolated enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.barrierbreak.AccessibilityScanner"

    static let appium = Logger(subsystem: subsystem, category: "appium")
    static let crawler = Logger(subsystem: subsystem, category: "crawler")
    static let probes = Logger(subsystem: subsystem, category: "probes")
    static let scan = Logger(subsystem: subsystem, category: "scan")
    static let devices = Logger(subsystem: subsystem, category: "devices")
    static let reports = Logger(subsystem: subsystem, category: "reports")
}

nonisolated func trace(_ message: String, _ logger: Logger = Log.scan) {
    logger.debug("\(message, privacy: .private)")
}
