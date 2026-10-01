//
//  AccessibilityAppMapView.swift
//  AccessibilityScanner
//
//  Created by Ravish Kumar on 01/10/26.
//

import SwiftUI
import Foundation

struct AccessibilityAppMapView: View {

    let report: AccessibilityScanResult

    @State private var selectedScreenID: UUID?

    private let columns = 3
    private let nodeWidth: CGFloat = 220
    private let nodeHeight: CGFloat = 116
    private let horizontalSpacing: CGFloat = 90
    private let verticalSpacing: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            metrics

            if report.screens.isEmpty {
                emptyMap
            } else {
                graph
                selectedScreenPanel
            }
        }
        .onAppear {
            if selectedScreenID == nil {
                selectedScreenID = report.screens.first?.id
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Accessibility App Map")
                .font(.title2)
                .fontWeight(.bold)

            Text("A map of discovered screens and navigation paths. Select a screen to inspect its accessibility impact and outgoing actions.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            appMapMetric(
                title: "Screens",
                value: report.screens.count,
                symbol: "rectangle.on.rectangle"
            )

            appMapMetric(
                title: "Paths",
                value: transitionCount,
                symbol: "arrow.triangle.branch"
            )

            appMapMetric(
                title: "Affected screens",
                value: affectedScreenCount,
                symbol: "exclamationmark.triangle"
            )

            appMapMetric(
                title: "Unresolved targets",
                value: unresolvedTransitionCount,
                symbol: "questionmark.circle"
            )
        }
    }

    private func appMapMetric(
        title: String,
        value: Int,
        symbol: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.headline)
                    .monospacedDigit()

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.07))
        )
    }

    private var graph: some View {
        let mapSize = graphSize

        return ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawConnections(in: &context)
                }
                .frame(width: mapSize.width, height: mapSize.height)

                ForEach(Array(report.screens.enumerated()), id: \.offset) { index, screen in
                    screenNode(screen, index: index)
                        .position(nodeCenter(for: index))
                }
            }
            .frame(width: mapSize.width, height: mapSize.height)
            .padding(24)
        }
        .frame(minHeight: min(520, max(260, graphSize.height + 48)))
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.16))
        )
    }

    private func screenNode(
        _ screen: ScreenScanResult,
        index: Int
    ) -> some View {
        let isSelected = selectedScreenID == screen.id

        return Button {
            selectedScreenID = screen.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(statusColor(for: screen))
                        .clipShape(Circle())

                    Text(screen.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()
                }

                HStack(spacing: 12) {
                    mapStat("Elements", screen.elementCount)
                    mapStat("Issues", screen.failures + screen.warnings + screen.validations)
                    mapStat("Paths", screen.transitions.count)
                }

                Text(statusText(for: screen))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(14)
            .frame(width: nodeWidth, height: nodeHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected
                            ? Color.accentColor
                            : Color.secondary.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: Color.black.opacity(isSelected ? 0.10 : 0.04),
                radius: isSelected ? 8 : 3,
                y: 2
            )
        }
        .buttonStyle(.plain)
    }

    private func mapStat(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var selectedScreenPanel: some View {
        guard let selectedScreen = selectedScreen else {
            return AnyView(EmptyView())
        }

        let incoming = incomingTransitions(for: selectedScreen)
        let outgoing = selectedScreen.transitions.compactMap { transition in
            targetScreen(for: transition.targetSignature).map {
                (transition, $0)
            }
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedScreen.name)
                            .font(.headline)

                        Text("\(selectedScreen.elementCount) elements • \(selectedScreen.failures + selectedScreen.warnings + selectedScreen.validations) items needing attention")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    statusBadge(for: selectedScreen)
                }

                HStack(alignment: .top, spacing: 24) {
                    transitionColumn(
                        title: "Outgoing paths",
                        symbol: "arrow.right",
                        transitions: outgoing.map { $0.0 },
                        destination: { transition in
                            targetScreen(for: transition.targetSignature)?.name
                        }
                    )

                    transitionColumn(
                        title: "Incoming paths",
                        symbol: "arrow.left",
                        transitions: incoming,
                        destination: { transition in
                            sourceScreen(for: transition.sourceSignature)?.name
                        }
                    )
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.06))
            )
        )
    }

    private func transitionColumn(
        title: String,
        symbol: String,
        transitions: [NavigationTransition],
        destination: @escaping (NavigationTransition) -> String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .fontWeight(.semibold)

            if transitions.isEmpty {
                Text("None discovered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(transitions) { transition in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.right.circle")
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(transition.displayName)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .lineLimit(1)

                            if let destination = destination(transition) {
                                Text(destination)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Target not retained in scan")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyMap: some View {
        Text("No screens were discovered in this scan.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.07))
            )
    }

    private var selectedScreen: ScreenScanResult? {
        guard let selectedScreenID else {
            return report.screens.first
        }
        return report.screens.first { $0.id == selectedScreenID }
    }

    private var transitionCount: Int {
        report.screens.reduce(0) { $0 + $1.transitions.count }
    }

    private var affectedScreenCount: Int {
        report.screens.filter {
            $0.failures > 0 || $0.warnings > 0 || $0.validations > 0
        }.count
    }

    private var unresolvedTransitionCount: Int {
        report.screens.reduce(0) { count, screen in
            count + screen.transitions.filter {
                targetScreen(for: $0.targetSignature) == nil
            }.count
        }
    }

    private var graphSize: CGSize {
        let rows = max(1, Int(ceil(Double(report.screens.count) / Double(columns))))
        let width = CGFloat(columns) * nodeWidth + CGFloat(columns - 1) * horizontalSpacing
        let height = CGFloat(rows) * nodeHeight + CGFloat(rows - 1) * verticalSpacing
        return CGSize(width: width, height: height)
    }

    private func nodeCenter(for index: Int) -> CGPoint {
        let column = index % columns
        let row = index / columns

        return CGPoint(
            x: nodeWidth / 2 + CGFloat(column) * (nodeWidth + horizontalSpacing),
            y: nodeHeight / 2 + CGFloat(row) * (nodeHeight + verticalSpacing)
        )
    }

    private func drawConnections(in context: inout GraphicsContext) {
        for sourceIndex in report.screens.indices {
            let source = report.screens[sourceIndex]

            for transition in source.transitions {
                guard let targetIndex = report.screens.firstIndex(where: {
                    $0.signature == transition.targetSignature
                }) else {
                    continue
                }

                if sourceIndex == targetIndex {
                    continue
                }

                let start = nodeCenter(for: sourceIndex)
                let end = nodeCenter(for: targetIndex)
                let path = Path { path in
                    path.move(to: start)
                    path.addLine(to: end)
                }

                context.stroke(
                    path,
                    with: .color(Color.secondary.opacity(0.42)),
                    style: StrokeStyle(lineWidth: 1.5)
                )

                drawArrowHead(
                    in: &context,
                    from: start,
                    to: end
                )
            }
        }
    }

    private func drawArrowHead(
        in context: inout GraphicsContext,
        from start: CGPoint,
        to end: CGPoint
    ) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        let ux = dx / length
        let uy = dy / length

        let tip = CGPoint(
            x: end.x - ux * (nodeWidth / 2 + 4),
            y: end.y - uy * (nodeHeight / 2 + 4)
        )

        let size: CGFloat = 7
        let left = CGPoint(
            x: tip.x - ux * size + uy * size * 0.7,
            y: tip.y - uy * size - ux * size * 0.7
        )
        let right = CGPoint(
            x: tip.x - ux * size - uy * size * 0.7,
            y: tip.y - uy * size + ux * size * 0.7
        )

        let arrow = Path { path in
            path.move(to: tip)
            path.addLine(to: left)
            path.move(to: tip)
            path.addLine(to: right)
        }

        context.stroke(
            arrow,
            with: .color(Color.secondary.opacity(0.42)),
            style: StrokeStyle(lineWidth: 1.5)
        )
    }

    private func targetScreen(for signature: String) -> ScreenScanResult? {
        report.screens.first { $0.signature == signature }
    }

    private func sourceScreen(for signature: String) -> ScreenScanResult? {
        targetScreen(for: signature)
    }

    private func incomingTransitions(
        for screen: ScreenScanResult
    ) -> [NavigationTransition] {
        report.screens.flatMap { source in
            source.transitions.filter {
                $0.targetSignature == screen.signature
            }
        }
    }

    private func statusText(for screen: ScreenScanResult) -> String {
        if screen.failures > 0 {
            return "\(screen.failures) failure(s)"
        }
        if screen.warnings > 0 {
            return "\(screen.warnings) warning(s)"
        }
        if screen.validations > 0 {
            return "\(screen.validations) validation(s)"
        }
        return "No issues detected"
    }

    private func statusColor(for screen: ScreenScanResult) -> Color {
        if screen.failures > 0 { return .red }
        if screen.warnings > 0 { return .orange }
        if screen.validations > 0 { return .yellow }
        return .green
    }

    private func statusBadge(for screen: ScreenScanResult) -> some View {
        Text(statusText(for: screen))
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(statusColor(for: screen).opacity(0.12))
            .foregroundStyle(statusColor(for: screen))
            .clipShape(Capsule())
    }
}
