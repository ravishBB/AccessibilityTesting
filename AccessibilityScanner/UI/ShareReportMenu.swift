//
//  ShareReportMenu.swift
//  AccessibilityScanner
//
//  Export menu for the quality report: HTML (opens in a browser, prints to
//  PDF) and JSON (for CI and tooling).
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ShareReportMenu: View {

    let report: AccessibilityScanResult

    @State private var exportError: String?

    var body: some View {
        Menu {
            Button("Open HTML Report", systemImage: "safari") {
                openHTML()
            }

            Button("Save HTML Report…", systemImage: "square.and.arrow.down") {
                saveHTML()
            }

            Divider()

            Button("Share HTML Report…", systemImage: "square.and.arrow.up") {
                share { try HTMLReportExporter().writeHTMLFile(from: report) }
            }

            Button("Share JSON…", systemImage: "curlybraces") {
                share { try JSONReportExporter().writeJSONFile(from: report) }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Export the report as HTML (print to PDF from the browser) or JSON")
        .alert(
            "Export Failed",
            isPresented: Binding(
                get: { exportError != nil },
                set: { isPresented in
                    if !isPresented { exportError = nil }
                }
            )
        ) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: - Actions

    private func openHTML() {
        do {
            let url = try HTMLReportExporter().writeHTMLFile(from: report)
            NSWorkspace.shared.open(url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func saveHTML() {
        let exporter = HTMLReportExporter()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = exporter.suggestedFileName(for: report)
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            let html = exporter.makeHTML(from: report)
            try html.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func share(_ makeFile: () throws -> URL) {
        do {
            presentSharingPicker(for: try makeFile())
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
