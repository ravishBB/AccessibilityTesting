//
//  AppLanguageInspector.swift
//  AccessibilityScanner

import Foundation
import NaturalLanguage

nonisolated enum AppLanguageInspector {

    struct Findings {

        let declared: String?
        let appLanguage: String
        let localizations: [String]
        let buildVersion: String?
    }

    static func inspect(bundleID: String) -> Findings? {
        guard let app = MotionHandlerInspector.newestBuild(of: bundleID) else { return nil }
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Info.plist")) as? [String: Any] ?? [:]
        let declared = (info["CFBundleDevelopmentRegion"] as? String)?.trimmingCharacters(in: .whitespaces)
        let folders = ((try? FileManager.default.contentsOfDirectory(atPath: app.path)) ?? [])
            .filter { $0.hasSuffix(".lproj") }
            .map { String($0.dropLast(".lproj".count)) }
            .filter { $0 != "Base" }
        let listed = info["CFBundleLocalizations"] as? [String] ?? []
        let appLanguage = declared.flatMap { $0.isEmpty ? nil : $0 } ?? "en"
        let version = [info["CFBundleShortVersionString"] as? String, (info["CFBundleVersion"] as? String).map { "(\($0))" }]
            .compactMap { $0 }.joined(separator: " ")
        return Findings(
            declared: declared,
            appLanguage: appLanguage,
            localizations: Array(Set([appLanguage] + folders + listed)).sorted(),
            buildVersion: version.isEmpty ? nil : version
        )
    }

    // MARK: - Report
    static func settle(_ screens: [ScreenScanResult], findings: Findings?) -> [ScreenScanResult] {
        guard let findings else {
            let reason = "No iOS device build of this app was found on this Mac (Xcode DerivedData or Archives), so its language could not be read."
            return screens.map {
                $0.settling("language", as: .notTested, message: reason)
                    .settling("content-language", as: .notTested, message: reason)
            }
        }

        let appName = displayName(findings.appLanguage)
        let languageResult: (RuleResultStatus, String)
        switch findings.declared {
        case .some(let code) where !code.isEmpty && !isLanguage(code):
            languageResult = (.fail, "The app's build declares \"\(code)\" as its language (CFBundleDevelopmentRegion), which is not a language code, so assistive technology cannot tell which language the app is in.")
        case .some(let code) where !code.isEmpty:
            languageResult = (.pass, "The app's language is \(appName) (\(code)), declared as CFBundleDevelopmentRegion in its build.")
        default:
            languageResult = (.pass, "The app's build does not declare a language (CFBundleDevelopmentRegion), so iOS runs it in English (en), the default.")
        }

        return screens.map { screen in
            var settled = screen.settling("language", as: languageResult.0, message: languageResult.1)
            guard let spoken = screenLanguage(screen) else {
                return settled.settling("content-language", as: .notTested, message: "This screen has too little text to tell its language.")
            }
            let covered = findings.localizations.contains { sameLanguage($0, spoken.rawValue) }
            let screenName = displayName(spoken.rawValue)
            settled = covered
                ? settled.settling("content-language", as: .pass,
                                   message: "Most text on this screen is \(screenName), which the app is in (\(findings.localizations.joined(separator: ", "))).")
                : settled.settling("content-language", as: .fail,
                                   message: "Most text on this screen is \(screenName), but the app's language is \(appName) and it has no \(screenName) localization, so VoiceOver reads this screen with the \(appName) voice.")
            return settled
        }
    }

    static func screenLanguage(_ screen: ScreenScanResult) -> NLLanguage? {
        var seen = Set<String>()
        let texts = screen.evaluations
            .filter { $0.elementRole == .staticText || $0.elementRole == .button || $0.elementRole == .link }
            .map { $0.elementLabel.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        let joined = texts.joined(separator: ". ")
        guard texts.count >= 3, joined.unicodeScalars.filter({ $0.properties.isAlphabetic }).count >= 40 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(joined)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= 0.5, language != .undetermined else { return nil }
        return language
    }

    static func sameLanguage(_ a: String, _ b: String) -> Bool {
        func base(_ code: String) -> String {
            code.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init) ?? code
        }
        return base(a) == base(b)
    }

    private static func isLanguage(_ code: String) -> Bool {
        Locale(identifier: "en").localizedString(forLanguageCode: code) != nil
    }

    private static func displayName(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }
}

nonisolated extension ScreenScanResult {
    func settling(_ ruleID: String, as status: RuleResultStatus, message: String) -> ScreenScanResult {
        var copy = self
        copy.evaluations = evaluations.map {
            $0.ruleID == ruleID && $0.status == .notTested ? $0.settled(as: status, message: message) : $0
        }
        return copy
    }
}
