//
//  ShareJSONButton.swift
//  AccessibilityScanner
//
//  Phase 5 - Native JSON sharing
//

import SwiftUI
import AppKit

struct ShareJSONButton: View {

    let report: AccessibilityScanResult

    @State private var exportError: String?

    var body: some View {
        Button {
            shareJSON()
        } label: {
            Label("Share JSON", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)
        .help("Export the accessibility report as JSON and share it")
        .alert(
            "JSON Export Failed",
            isPresented: Binding(
                get: { exportError != nil },
                set: { isPresented in
                    if !isPresented {
                        exportError = nil
                    }
                }
            )
        ) {
            Button("OK") {
                exportError = nil
            }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func shareJSON() {
        do {
            let url = try JSONReportExporter()
                .writeJSONFile(from: report)

            presentSharingPicker(for: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func presentSharingPicker(for url: URL) {
        guard let window = NSApp.keyWindow,
              let contentView = window.contentView else {
            exportError = "The report window is not available for sharing."
            return
        }

        let picker = NSSharingServicePicker(items: [url])

        let anchor = NSRect(
            x: contentView.bounds.midX - 1,
            y: contentView.bounds.midY - 1,
            width: 2,
            height: 2
        )

        picker.show(
            relativeTo: anchor,
            of: contentView,
            preferredEdge: .minY
        )
    }
}
