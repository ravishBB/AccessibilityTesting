//
//  SummaryCard.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 24/09/26.
//

import SwiftUI

// MARK: - Summary Card
struct SummaryCard: View {

    let title: String
    let value: Int
    let icon: String

    var body: some View {

        HStack(spacing: 12) {

            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(value)")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Spacer()
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            RoundedRectangle(
                cornerRadius: 10
            )
            .fill(
                Color.secondary.opacity(0.08)
            )
        )
    }
}
