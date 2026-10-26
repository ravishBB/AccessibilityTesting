//
//  GuidedChecks.swift
//  AccessibilityScanner
//
//  Checks the scanner cannot drive alone: it asks the tester to do
//  something on the phone (shake it, press Tab on a keyboard), waits, and
//  watches the screen for the result. The scan pauses on the card; the
//  scanner closes it itself when it sees the phone react.

import SwiftUI
import Combine
import AppKit

@MainActor
final class GuidedChecks: ObservableObject {

    enum Reply: Hashable {
        case ready, done, nothingHappened, skip, skipAll
        /// The scanner saw the phone react and closed the card.
        case detected
    }

    struct Action: Hashable {
        let reply: Reply
        let title: String
    }

    struct Step: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var message: String
        var actions: [Action]
        /// Shown under the message while the scanner watches.
        var progress: String?
    }

    @Published private(set) var step: Step?
    private var reply: Reply?
    /// How the last card was closed.
    private(set) var lastReply: Reply?
    private var continuation: CheckedContinuation<Reply, Never>?

    /// Shows the card at once; the scanner watches the phone while it is
    /// open and collects the answer with `waitForReply()`.
    func present(_ step: Step) {
        if self.step != nil { finish(.skip) }
        reply = nil
        self.step = step
        NSSound.beep()
        NSApp.requestUserAttention(.criticalRequest)
    }

    /// The tester's reply, or `.detected` when the scanner closed the card.
    func waitForReply() async -> Reply {
        if let reply { return reply }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    /// Shows the card and waits for the tester.
    func ask(_ step: Step) async -> Reply {
        present(step)
        return await waitForReply()
    }

    /// Whether the card for `id` is still open.
    func isWaiting(_ id: UUID) -> Bool {
        step?.id == id
    }

    func update(progress: String?, message: String? = nil) {
        step?.progress = progress
        if let message { step?.message = message }
    }

    func finish(_ reply: Reply) {
        guard step != nil || continuation != nil else { return }
        step = nil
        self.reply = reply
        lastReply = reply
        let waiting = continuation
        continuation = nil
        waiting?.resume(returning: reply)
    }
}

/// The card over the scanner window while a guided check waits.
struct GuidedChecksOverlay: View {
    @ObservedObject var guided: GuidedChecks

    var body: some View {
        if let step = guided.step {
            ZStack {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    Label(step.title, systemImage: "iphone.radiowaves.left.and.right")
                        .font(.title2.weight(.semibold))
                    Text(step.message)
                        .fixedSize(horizontal: false, vertical: true)
                    if let progress = step.progress {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(progress)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Spacer()
                        ForEach(step.actions, id: \.self) { action in
                            if action == step.actions.last {
                                Button(action.title) { guided.finish(action.reply) }
                                    .keyboardShortcut(.defaultAction)
                                    .buttonStyle(.borderedProminent)
                            } else {
                                Button(action.title) { guided.finish(action.reply) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 520)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
                .shadow(radius: 20)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
            }
        }
    }
}
