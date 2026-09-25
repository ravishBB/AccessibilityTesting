//
//  FindingCard.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 24/09/26.
//

import SwiftUI

// MARK: - Finding Card
struct FindingCard: View {

    let finding: AccessibilityFinding

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            // =============================================
            // Header
            // =============================================

            HStack(
                alignment: .top
            ) {

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {

                    Text(finding.message)
                        .font(.headline)

                    Text(finding.ruleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                severityBadge
            }

            // =============================================
            // Element Information
            // =============================================

            VStack(
                alignment: .leading,
                spacing: 6
            ) {

                if !finding.elementType.isEmpty {

                    detailRow(
                        title: "Element",
                        value: finding.elementType
                    )
                }

                if !finding.elementLabel.isEmpty {

                    detailRow(
                        title: "Label",
                        value: finding.elementLabel
                    )
                }

                if !finding.identifier.isEmpty {

                    detailRow(
                        title: "Identifier",
                        value: finding.identifier
                    )
                }

                if let value = finding.value,
                   !value.isEmpty {

                    detailRow(
                        title: "Value",
                        value: value
                    )
                }

                detailRow(
                    title: "Frame",
                    value: String(
                        format:
                            "%.0f, %.0f — %.0f × %.0f",
                        finding.frame.origin.x,
                        finding.frame.origin.y,
                        finding.frame.width,
                        finding.frame.height
                    )
                )
            }

            // =============================================
            // Remediation
            // =============================================

            if !finding.remediation.isEmpty {

                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {

                    Text("Remediation")
                        .font(.caption)
                        .fontWeight(.semibold)

                    Text(
                        finding.remediation
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(
                cornerRadius: 10
            )
            .fill(
                Color.secondary.opacity(0.07)
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: 10
            )
            .stroke(
                Color.secondary.opacity(0.15),
                lineWidth: 1
            )
        )
    }

    // MARK: - Severity Badge

    private var severityBadge: some View {

        Text(
            finding.severity.displayName
                .uppercased()
        )
        .font(.caption)
        .fontWeight(.bold)
        .padding(
            .horizontal,
            10
        )
        .padding(
            .vertical,
            5
        )
        .background(
            Capsule()
                .fill(
                    severityBackground
                )
        )
    }

    private var severityBackground: Color {

        switch finding.severity {

        case .error:
            return Color.red.opacity(0.15)

        case .warning:
            return Color.orange.opacity(0.15)

        case .info:
            return Color.blue.opacity(0.15)
        }
    }

    // MARK: - Detail Row

    private func detailRow(
        title: String,
        value: String
    ) -> some View {

        HStack(
            alignment: .top,
            spacing: 8
        ) {

            Text("\(title):")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(
                    width: 80,
                    alignment: .leading
                )

            Text(value)
                .font(.caption)
                .textSelection(.enabled)

            Spacer()
        }
    }
}
