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
