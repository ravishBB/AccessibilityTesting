//  MotionHandlerInspector.swift
//  AccessibilityScanner

import Foundation

nonisolated enum MotionHandlerInspector {

    struct Findings {
        let buildPath: String
        let buildVersion: String?
        let shakeClasses: [String]
        let usesCoreMotion: Bool
        let unnamedShakeHandler: Bool

        var hasMotion: Bool { !shakeClasses.isEmpty || usesCoreMotion || unnamedShakeHandler }
    }

    // MARK: - Reading the build
    static func inspect(bundleID: String) -> Findings? {
        guard let app = newestBuild(of: bundleID) else { return nil }
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Info.plist")) as? [String: Any] ?? [:]
        guard let executable = info["CFBundleExecutable"] as? String else { return nil }

        // Debug builds keep the code in <name>.debug.dylib beside a stub.
        let binaries = [executable + ".debug.dylib", executable]
            .map { app.appendingPathComponent($0).path }
            .filter { FileManager.default.fileExists(atPath: $0) }

        var classes = Set<String>()
        var coreMotion = false
        var selectorPresent = false
        for binary in binaries {
            let defined = (try? ProcessRunner.run("/usr/bin/xcrun", ["nm", "-j", binary], timeout: 60))?.stdoutText ?? ""
            for line in defined.split(separator: "\n") {
                if let name = shakeClass(inSymbol: String(line)) { classes.insert(name) }
                if line.contains("_OBJC_CLASS_$_CMMotionManager") { coreMotion = true }
            }
            if let data = FileManager.default.contents(atPath: binary),
               data.range(of: Data("motionEnded:withEvent:".utf8)) != nil || data.range(of: Data("motionBegan:withEvent:".utf8)) != nil {
                selectorPresent = true
            }
        }

        let version = [info["CFBundleShortVersionString"] as? String, (info["CFBundleVersion"] as? String).map { "(\($0))" }]
            .compactMap { $0 }.joined(separator: " ")
        return Findings(
            buildPath: app.path,
            buildVersion: version.isEmpty ? nil : version,
            shakeClasses: classes.sorted(),
            usesCoreMotion: coreMotion,
            unnamedShakeHandler: classes.isEmpty && selectorPresent && !defined(in: binaries)
        )
    }

    private static func defined(in binaries: [String]) -> Bool {
        binaries.contains { binary in
            let output = (try? ProcessRunner.run("/usr/bin/xcrun", ["nm", "-j", "-U", binary], timeout: 60))?.stdoutText ?? ""
            return output.contains("$s") || output.contains("-[")
        }
    }

    static func shakeClass(inSymbol symbol: String) -> String? {
        if symbol.hasPrefix("-["), symbol.contains(" motionEnded:withEvent:]") || symbol.contains(" motionBegan:withEvent:]") {
            return symbol.dropFirst(2).split(separator: " ").first.map(String.init)
        }
        guard let marker = symbol.range(of: "C11motionEnded_4with") ?? symbol.range(of: "C11motionBegan_4with"),
              let start = symbol.range(of: "$s")
        else { return nil }
        // Length-prefixed identifiers between "$s" and the class marker:
        // module, then any enclosing types, then the class itself.
        var rest = symbol[start.upperBound..<marker.lowerBound]
        var names: [String] = []
        while let digitEnd = rest.firstIndex(where: { !$0.isNumber }), digitEnd > rest.startIndex,
              let length = Int(rest[rest.startIndex..<digitEnd]) {
            let nameEnd = rest.index(digitEnd, offsetBy: length, limitedBy: rest.endIndex) ?? rest.endIndex
            names.append(String(rest[digitEnd..<nameEnd]))
            rest = rest[nameEnd...]
            // Enclosing type kinds between identifiers (C, V, O).
            while let first = rest.first, first.isLetter, !first.isNumber { rest = rest.dropFirst() }
        }
        return names.count >= 2 ? names.last : nil
    }

    static func newestBuild(of bundleID: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
            home.appendingPathComponent("Library/Developer/Xcode/Archives")
        ]
        var builds: [(URL, Date)] = []
        for root in roots {
            guard let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in walker where url.pathExtension == "app" {
                // Device builds only (Debug-iphoneos, Release-iphoneos,
                // archives); skip indexing copies and test runners.
                let path = url.path
                guard !path.contains("Index.noindex"), !path.contains("-iphonesimulator"),
                      path.contains("-iphoneos") || path.contains("/Archives/"),
                      let info = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")),
                      info["CFBundleIdentifier"] as? String == bundleID
                else { continue }
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                builds.append((url, date))
            }
        }
        return builds.max { $0.1 < $1.1 }?.0
    }

    // MARK: - Report
    static func settle(
        _ screens: [ScreenScanResult],
        findings: Findings?,
        installedVersion: String?
    ) -> [ScreenScanResult] {
        guard !screens.isEmpty else { return screens }
        // A screen the tester shook during the scan has a verdict already.
        let shakenScreens = Set(screens.filter { screen in
            screen.evaluations.contains { $0.ruleID == "motion-alternative" && $0.status != .notTested }
        }.map(\.id))
        func shaken(_ screen: ScreenScanResult) -> Bool { shakenScreens.contains(screen.id) }

        guard let findings else {
            return screens.map { screen in
                screen.settlingMotion(as: .notTested, message: "No iOS device build of this app was found on this Mac (Xcode DerivedData or Archives), so its shake and motion handlers could not be read.")
            }
        }
        guard findings.hasMotion else {
            return screens.map { screen in
                screen.settlingMotion(as: .notTested, message: "The app's build (\(findings.buildVersion ?? "unknown version")) has no shake or device-motion handler, so there is no motion action to check.")
            }
        }

        var versionNote = ""
        if let installedVersion, let build = findings.buildVersion, !build.hasPrefix(installedVersion) {
            versionNote = " The build on this Mac is \(build); the device has \(installedVersion), so confirm the handler is still there."
        }

        var unmatched = findings.shakeClasses
        var settled = screens.map { screen -> ScreenScanResult in
            let handlers = findings.shakeClasses.filter { matches($0, screen: screen.name) }
            guard !handlers.isEmpty else { return screen }
            unmatched.removeAll { handlers.contains($0) }
            guard !shaken(screen) else { return screen }
            return screen.settlingMotion(as: .validate, message: "Shake is handled in \(handlers.joined(separator: ", ")) (read from the app's build). Check this screen has an on-screen control that does the same; if not, record it as a failure.\(versionNote)")
        }
        var appLevel: [String] = []
        if !unmatched.isEmpty { appLevel.append("Shake is also handled in \(unmatched.joined(separator: ", "))") }
        if findings.unnamedShakeHandler { appLevel.append("The app handles shake") }
        if findings.usesCoreMotion { appLevel.append("The app reads device motion (CMMotionManager), for example tilt or movement") }
        if !appLevel.isEmpty, !shaken(settled[0]) {
            let alreadyValidate = settled[0].evaluations.contains { $0.ruleID == "motion-alternative" && $0.status == .validate }
            let text = appLevel.joined(separator: ". ") + " (read from the app's build). Check each motion action has an on-screen control that does the same; if not, record it as a failure.\(versionNote)"
            settled[0] = alreadyValidate
                ? settled[0].appendingToMotion(text)
                : settled[0].settlingMotion(as: .validate, message: text)
        }
        return settled
    }

    static func matches(_ className: String, screen: String) -> Bool {
        var base = className
        for suffix in ["ViewController", "Controller", "VC", "Screen", "View", "Page"] where base.hasSuffix(suffix) && base.count > suffix.count {
            base.removeLast(suffix.count)
            break
        }
        func key(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
        // "Home 2": the second screen named Home in this scan.
        let screenKey = key(screen.replacingOccurrences(of: #"\s\d+$"#, with: "", options: .regularExpression))
        return !key(base).isEmpty && key(base) == screenKey
    }
}

nonisolated extension ScreenScanResult {
    /// The screen with its motion result given a verdict.
    func settlingMotion(as status: RuleResultStatus, message: String) -> ScreenScanResult {
        var copy = self
        copy.evaluations = evaluations.map {
            $0.ruleID == "motion-alternative" && $0.status == .notTested ? $0.settled(as: status, message: message) : $0
        }
        return copy
    }

    /// Adds a sentence to a motion result that is already Validate.
    func appendingToMotion(_ text: String) -> ScreenScanResult {
        var copy = self
        copy.evaluations = evaluations.map {
            $0.ruleID == "motion-alternative" ? $0.settled(as: $0.status, message: $0.message + " " + text) : $0
        }
        return copy
    }
}
