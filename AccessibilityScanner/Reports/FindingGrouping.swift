//
//  FindingGrouping.swift
//  AccessibilityScanner
//
//  Groups per-element evaluations into one entry per rule (and status), and
//  assigns every non-pass evaluation a stable fingerprint so the same issue
//  can be tracked across scans, builds and report formats.
//

import Foundation

// MARK: - Fingerprint

enum FindingFingerprint {

    /// Stable 12-hex-character identifier for "this rule failing on this element
    /// on this screen". It deliberately ignores layout position, scan time and
    /// device so it survives re-scans of the same build. When a screen contains
    /// several elements with the same identity (for example repeated "Add"
    /// buttons without identifiers) the later ones, ordered top-to-bottom then
    /// left-to-right, receive a "-2", "-3"... suffix.
    static func baseFingerprint(
        ruleID: String,
        screen: ScreenScanResult,
        evaluation: AccessibilityRuleEvaluation
    ) -> String {
        let screenKey = screen.signature.isEmpty ? screen.name : screen.signature
        let source = "\(ruleID)|\(screenKey)|\(elementKey(evaluation))"
        return String(format: "%016llx", fnv1a64(source)).prefix(12).description
    }

    private static func elementKey(_ evaluation: AccessibilityRuleEvaluation) -> String {
        let identifier = evaluation.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = evaluation.elementLabel.trimmingCharacters(in: .whitespacesAndNewlines)

        if !identifier.isEmpty {
            return "id|\(evaluation.elementType)|\(identifier)"
        }
        if !label.isEmpty {
            return "label|\(evaluation.elementType)|\(label)"
        }
        // No name or identifier: fall back to coarse position (rounded to 8pt)
        // so tiny layout shifts do not change the fingerprint.
        let x = Int((evaluation.frameX / 8).rounded()) * 8
        let y = Int((evaluation.frameY / 8).rounded()) * 8
        return "frame|\(evaluation.elementType)|\(x),\(y)"
    }

    /// FNV-1a 64-bit. `Hasher` is randomly seeded per process, so it cannot be
    /// used for identifiers that must be stable across launches.
    private static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

// MARK: - Models

struct FindingOccurrence: Identifiable {
    var id: UUID { evaluation.id }
    let fingerprint: String
    let screenID: UUID
    let screenName: String
    let evaluation: AccessibilityRuleEvaluation
}

struct GroupedFinding: Identifiable {
    let id: String
    let ruleID: String
    let ruleName: String
    let ruleDescription: String
    let status: RuleResultStatus
    let severity: AccessibilityFinding.Severity
    let metadata: AccessibilityRuleMetadata
    let occurrences: [FindingOccurrence]

    var count: Int { occurrences.count }

    var screenCount: Int {
        Set(occurrences.map(\.screenID)).count
    }

    var remediation: String {
        occurrences
            .map { $0.evaluation.remediation.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    var sampleMessage: String {
        occurrences.first?.evaluation.message ?? ""
    }
}

// MARK: - Grouping

struct FindingGrouping {

    /// Every non-pass group, most important first.
    let groups: [GroupedFinding]

    /// Fingerprint for every non-pass evaluation (including exact duplicates
    /// that were merged), keyed by evaluation id.
    let fingerprintByEvaluationID: [UUID: String]

    var issueGroups: [GroupedFinding] {
        groups.filter { $0.status == .fail || $0.status == .warning }
    }

    var manualReviewGroups: [GroupedFinding] {
        groups.filter { $0.status == .validate }
    }

    /// Unique affected elements. Evaluations with the same rule, status,
    /// element identity and geometry on one screen are counted once.
    var failureCount: Int { count(for: .fail) }
    var warningCount: Int { count(for: .warning) }
    var manualReviewCount: Int { count(for: .validate) }
    var issueCount: Int { failureCount + warningCount }

    private func count(for status: RuleResultStatus) -> Int {
        groups
            .filter { $0.status == status }
            .reduce(0) { $0 + $1.count }
    }

    init(report: AccessibilityScanResult) {

        var fingerprintByID: [UUID: String] = [:]
        var occurrencesByKey: [String: [FindingOccurrence]] = [:]
        var seen = Set<String>()

        for screen in report.screens {

            let actionable = screen.evaluations.filter { $0.status != .pass }

            // Base fingerprint and a frame key per evaluation.
            let bases = actionable.map {
                FindingFingerprint.baseFingerprint(
                    ruleID: $0.ruleID,
                    screen: screen,
                    evaluation: $0
                )
            }

            // Disambiguate identical identities on the same screen.
            var framesByBase: [String: [(key: String, x: Double, y: Double)]] = [:]
            for (index, evaluation) in actionable.enumerated() {
                let frame = FindingGrouping.frameKey(evaluation)
                var list = framesByBase[bases[index], default: []]
                if !list.contains(where: { $0.key == frame }) {
                    list.append((frame, evaluation.frameX, evaluation.frameY))
                    framesByBase[bases[index]] = list
                }
            }
            for (base, list) in framesByBase {
                framesByBase[base] = list.sorted {
                    if $0.y != $1.y { return $0.y < $1.y }
                    return $0.x < $1.x
                }
            }

            for (index, evaluation) in actionable.enumerated() {
                let base = bases[index]
                let frame = FindingGrouping.frameKey(evaluation)
                let position = framesByBase[base]?.firstIndex(where: { $0.key == frame }) ?? 0
                let fingerprint = position == 0 ? base : "\(base)-\(position + 1)"

                fingerprintByID[evaluation.id] = fingerprint

                let dedupeKey = "\(evaluation.ruleID)|\(evaluation.status.rawValue)|\(fingerprint)"
                guard seen.insert(dedupeKey).inserted else { continue }

                let groupKey = "\(evaluation.ruleID)|\(evaluation.status.rawValue)"
                occurrencesByKey[groupKey, default: []].append(
                    FindingOccurrence(
                        fingerprint: fingerprint,
                        screenID: screen.id,
                        screenName: screen.name,
                        evaluation: evaluation
                    )
                )
            }
        }

        let severityRank: [AccessibilityFinding.Severity: Int] = [.error: 0, .warning: 1, .info: 2]
        let statusRank: [RuleResultStatus: Int] = [.fail: 0, .warning: 1, .validate: 2, .pass: 3]

        let built: [GroupedFinding] = occurrencesByKey.compactMap { key, occurrences in
            guard let first = occurrences.first?.evaluation else { return nil }

            let worstSeverity = occurrences
                .map(\.evaluation.severity)
                .min { (severityRank[$0] ?? 9) < (severityRank[$1] ?? 9) } ?? first.severity

            return GroupedFinding(
                id: key,
                ruleID: first.ruleID,
                ruleName: first.ruleName,
                ruleDescription: first.ruleDescription,
                status: first.status,
                severity: worstSeverity,
                metadata: AccessibilityRuleCatalog.metadata(for: first.ruleID),
                occurrences: occurrences
            )
        }

        self.groups = built.sorted {
            let lhsStatus = statusRank[$0.status] ?? 9
            let rhsStatus = statusRank[$1.status] ?? 9
            if lhsStatus != rhsStatus { return lhsStatus < rhsStatus }
            if $0.metadata.impact.rank != $1.metadata.impact.rank {
                return $0.metadata.impact.rank < $1.metadata.impact.rank
            }
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.ruleName.localizedCaseInsensitiveCompare($1.ruleName) == .orderedAscending
        }
        self.fingerprintByEvaluationID = fingerprintByID
    }

    private static func frameKey(_ evaluation: AccessibilityRuleEvaluation) -> String {
        "\(Int(evaluation.frameX.rounded())),\(Int(evaluation.frameY.rounded())),\(Int(evaluation.frameWidth.rounded())),\(Int(evaluation.frameHeight.rounded()))"
    }
}
