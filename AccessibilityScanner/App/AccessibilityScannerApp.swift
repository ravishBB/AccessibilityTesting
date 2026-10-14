//
//  AccessibilityScannerApp.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 22/09/26.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillTerminate(_ notification: Notification) {
        // Quitting mid-scan must not leave the device held by Appium.
        AppiumClient.deleteOpenSessionsBeforeQuit()
    }
}

@main
struct AccessibilityScannerApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Put back any Android font scale a crashed scan left changed.
                    await Task.detached {
                        AndroidFontScaleRecovery.restoreOutstanding()
                    }.value
                }
        }

        Settings {
            ScannerSettingsView()
        }
    }
}
