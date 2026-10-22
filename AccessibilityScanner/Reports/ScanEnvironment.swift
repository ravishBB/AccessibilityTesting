//
//  ScanEnvironment.swift
//  AccessibilityScanner

import Foundation

nonisolated struct ScanEnvironment: Codable, Hashable {
    let platform: String
    let osVersion: String?
    let deviceModel: String?
    let isSimulator: Bool
    let appVersion: String?
    let appBuild: String?
    let automationName: String?
    let appiumVersion: String?
    let scannerVersion: String
    let ruleSetVersion: String
    let bbMappingVersion: String
    let wcagVersion: String

    var osDescription: String {
        let name = platform == MobilePlatform.android.rawValue ? "Android" : "iOS"
        return [name, osVersion].compactMap { $0 }.joined(separator: " ")
    }

    var appVersionDescription: String? {
        switch (appVersion, appBuild) {
        case let (version?, build?) where version != build: return "\(version) (\(build))"
        case let (version?, _): return version
        case let (nil, build?): return build
        default: return nil
        }
    }
}

/// Collects what went wrong during a scan, grouped so a report shows
/// "4 actions could not be tapped (for example: Help, Share)" rather than
/// one line per occurrence.
nonisolated final class ScanNotes {

    enum Kind: String, CaseIterable {
        case tapFailed
        case leftApp
        case lostNavigation
        case unstableScreen
        case snapshotFailed
        case launchFailed

        func summary(count: Int) -> String {
            let s = count == 1 ? "" : "s"
            switch self {
            case .tapFailed: return "\(count) action\(s) could not be tapped, so the screens behind them were not scanned"
            case .leftApp: return "\(count) action\(s) opened another app and \(count == 1 ? "was" : "were") skipped"
            case .lostNavigation: return "Back navigation failed \(count) time\(s), so the remaining actions on \(count == 1 ? "that screen were" : "those screens were") not explored"
            case .unstableScreen: return "\(count) screen\(s) kept changing (animation or live content) and \(count == 1 ? "was" : "were") captured while moving; element positions may be slightly off"
            case .snapshotFailed: return "\(count) screen\(s) could not be read after navigating to \(count == 1 ? "it" : "them")"
            case .launchFailed: return "The app could not be brought to the foreground at the start of the scan; the scan covered whatever was on screen"
            }
        }
    }

    private var counts: [Kind: Int] = [:]
    private var examples: [Kind: [String]] = [:]

    func record(_ kind: Kind, example: String? = nil) {
        counts[kind, default: 0] += 1
        if let example, !example.isEmpty,
           examples[kind, default: []].count < 3,
           !examples[kind, default: []].contains(example) {
            examples[kind, default: []].append(example)
        }
    }

    var isEmpty: Bool { counts.isEmpty }

    var summaries: [String] {
        Kind.allCases.compactMap { kind in
            guard let count = counts[kind] else { return nil }
            var line = kind.summary(count: count)
            if let sample = examples[kind], !sample.isEmpty {
                line += " (for example: \(sample.joined(separator: ", ")))"
            }
            return line + "."
        }
    }
}
