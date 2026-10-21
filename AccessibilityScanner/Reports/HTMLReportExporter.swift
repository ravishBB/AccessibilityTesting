//
//  HTMLReportExporter.swift
//  AccessibilityScanner
//


import Foundation
import CoreGraphics

nonisolated struct HTMLReportExporter {

    enum ExportError: LocalizedError {
        case couldNotCreateFile

        var errorDescription: String? {
            switch self {
            case .couldNotCreateFile:
                return "The accessibility HTML report could not be created."
            }
        }
    }

    struct Options {
        var includeScreenshots = true
        var maxScreenshotPixelSize = 900
    }

    var options = Options()

    func makeHTML(
        from report: AccessibilityScanResult,
        generatedAt: Date = Date()
    ) -> String {
        HTMLReportRenderer(
            report: report,
            options: options,
            generatedAt: generatedAt
        ).render()
    }

    func suggestedFileName(for report: AccessibilityScanResult) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = report.applicationName
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        return (cleaned.isEmpty ? "AccessibilityScan" : cleaned)
            + "_AccessibilityReport_"
            + formatter.string(from: report.finishedAt)
            + ".html"
    }

    func writeHTMLFile(from report: AccessibilityScanResult) throws -> URL {
        let html = makeHTML(from: report)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccessibilityScanner", isDirectory: true)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let url = directory.appendingPathComponent(suggestedFileName(for: report))

        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            throw ExportError.couldNotCreateFile
        }
    }
}

// MARK: - Renderer

private nonisolated struct HTMLReportRenderer {

    let report: AccessibilityScanResult
    let options: HTMLReportExporter.Options
    let generatedAt: Date

    private let grouping: FindingGrouping
    private let coverage: ReportCoverage
    private let intelligence: AccessibilityIntelligence

    init(
        report: AccessibilityScanResult,
        options: HTMLReportExporter.Options,
        generatedAt: Date
    ) {
        self.report = report
        self.options = options
        self.generatedAt = generatedAt
        let grouping = FindingGrouping(report: report)
        self.grouping = grouping
        self.coverage = ReportCoverage(report: report, grouping: grouping)
        self.intelligence = report.resolvedIntelligence
    }

    func render() -> String {
        var out = ""
        out += head()
        out += "<body>\n<div class=\"page\">\n"
        out += cover()
        out += navigation()
        out += executiveSummary()
        out += findingsSection()
        out += manualReviewSection()
        out += coverageSection()
        out += bbCoverageSection()
        out += screensSection()
        out += runtimeSection()
        out += scopeSection()
        out += appendixSection()
        out += footer()
        out += "</div>\n</body>\n</html>\n"
        return out
    }

    // MARK: Head

    private func head() -> String {
        let title = esc("Accessibility Quality Report – \(report.applicationName)")
        let generator = esc("\(ScannerBuildInfo.productName) \(ScannerBuildInfo.displayVersion); rule set \(ScannerBuildInfo.ruleSetVersion)")
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="generator" content="\(generator)">
        <title>\(title)</title>
        <style>
        \(Self.css)
        </style>
        </head>

        """
    }

    // MARK: Cover

    private func cover() -> String {
        let started = report.startedAt.formatted(date: .long, time: .shortened)
        let iso = ISO8601DateFormatter().string(from: report.startedAt)
        let verdict = verdictInfo()

        var out = """
        <header class="cover">
        <p class="eyebrow">Accessibility Quality Report</p>
        <h1>\(esc(report.applicationName))</h1>
        <p class="verdict \(verdict.cssClass)"><strong>\(esc(verdict.title))</strong> \(esc(verdict.detail))</p>
        <dl class="meta">

        """
        out += metaItem("Bundle ID", report.bundleID)
        out += metaItem("Device", report.deviceName)
        if let environment = report.environment {
            var platform = environment.osDescription
            if let model = environment.deviceModel { platform += " · \(model)" }
            if environment.isSimulator { platform += " · simulator" }
            out += metaItem("Platform", platform)
            out += metaItem("App version", environment.appVersionDescription ?? "")
        }
        out += "<div><dt>Scanned</dt><dd><time datetime=\"\(esc(iso))\">\(esc(started))</time></dd></div>\n"
        out += metaItem("Duration", formattedDuration)
        out += metaItem("Report ID", report.id.uuidString)
        var scanner = "\(ScannerBuildInfo.productName) \(ScannerBuildInfo.displayVersion)"
        if let environment = report.environment {
            let driver = [environment.automationName, environment.appiumVersion.map { "Appium \($0)" }]
                .compactMap { $0 }.joined(separator: ", ")
            if !driver.isEmpty { scanner += " · \(driver)" }
        }
        out += metaItem("Scanner", scanner)
        out += metaItem("BB mapping", report.environment?.bbMappingVersion ?? BBIssueCatalog.version)

        let platform = BBCoverage.platform(of: report)
        let cannotRun = AccessibilityRuleCatalog.cannotRun(on: platform).count
        out += metaItem("Rule set", "\(ScannerBuildInfo.ruleSetVersion) · \(report.automatedVerdictRuleCount) of \(report.verdictCapableRuleCount) \(report.platformName) rules gave results (\(cannotRun) cannot run on \(report.platformName) through Appium; \(AccessibilityRuleCatalog.reviewOnly.count) give manual-review items only)")
        out += metaItem("Standard", "\(ScannerBuildInfo.wcagVersion), automated subset")
        out += "</dl>\n</header>\n"
        return out
    }

    private func metaItem(_ name: String, _ value: String) -> String {
        "<div><dt>\(esc(name))</dt><dd>\(esc(value.isEmpty ? "—" : value))</dd></div>\n"
    }

    private struct Verdict {
        let title: String
        let detail: String
        let cssClass: String
    }

    private func verdictInfo() -> Verdict {
        if grouping.failureCount > 0 {
            let rules = grouping.groups.filter { $0.status == .fail }.count
            return Verdict(
                title: "Fail.",
                detail: "\(grouping.failureCount) confirmed failure\(plural(grouping.failureCount)) across \(rules) rule\(plural(rules)) must be fixed before sign-off.",
                cssClass: "fail"
            )
        }
        if grouping.warningCount > 0 {
            return Verdict(
                title: "Warnings.",
                detail: "\(grouping.warningCount) warning\(plural(grouping.warningCount)) should be reviewed before sign-off.",
                cssClass: "warning"
            )
        }
        if grouping.manualReviewCount > 0 {
            return Verdict(
                title: "Validate items to confirm.",
                detail: "No failures, but \(grouping.manualReviewCount) result\(plural(grouping.manualReviewCount)) need a tester to confirm.",
                cssClass: "validate"
            )
        }
        let unchecked = coverage.rulesNotTested + coverage.criteriaWithoutRule
        if unchecked > 0 {
            return Verdict(
                title: "No findings in the checks that ran.",
                detail: "This is not a pass: \(coverage.rulesNotTested) rule\(plural(coverage.rulesNotTested)) could not be tested and \(coverage.criteriaWithoutRule) of \(coverage.criteriaTotalAAndAA) WCAG A/AA criteria have no automated rule. See Coverage.",
                cssClass: "validate"
            )
        }
        return Verdict(
            title: "No findings.",
            detail: "The automated checks recorded no failures, warnings or manual-review items on the scanned screens.",
            cssClass: "pass"
        )
    }

    private var formattedDuration: String {
        let seconds = max(0, report.finishedAt.timeIntervalSince(report.startedAt))
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        return "\(Int(seconds) / 60)m \(Int(seconds) % 60)s"
    }

    // MARK: Navigation

    private func navigation() -> String {
        """
        <nav aria-label="Report sections">
        <a href="#summary">Summary</a>
        <a href="#findings">Findings</a>
        <a href="#manual-review">Validate</a>
        <a href="#coverage">Coverage</a>
        <a href="#bb-coverage">BB ruleset</a>
        <a href="#screens">Screens</a>
        <a href="#runtime">Runtime results</a>
        <a href="#scope">Scope &amp; limitations</a>
        <a href="#appendix">Rule results</a>
        </nav>

        """
    }

    // MARK: Executive summary

    private func executiveSummary() -> String {
        var out = "<section id=\"summary\">\n<h2>Executive summary</h2>\n"

        out += "<div class=\"kpis\">\n"
        out += kpi("Fail", grouping.failureCount, "fail")
        out += kpi("Validate", grouping.manualReviewCount, "validate")
        out += kpi("Pass", grouping.passCount, "pass")
        out += kpi("Rules not tested", coverage.rulesNotTested, "nottested")
        out += kpi("Screens", report.screens.count, "neutral")
        out += kpi("Elements tested", report.totalElementsTested, "neutral")
        out += "</div>\n"

        out += "<p class=\"note\">Failed, warning, manual-review and passed counts use one unit: a rule result for one element on one screen, with duplicates merged. Rules not tested counts rules, not elements.</p>\n"

        // Top priorities
        let top = Array(grouping.issueGroups.prefix(5))
        if !top.isEmpty {
            out += "<h3>Fix first</h3>\n"
            out += "<table class=\"data\">\n<thead><tr><th scope=\"col\">Issue</th><th scope=\"col\">Impact</th><th scope=\"col\">Standard</th><th scope=\"col\" class=\"num\">Elements</th><th scope=\"col\">Result</th></tr></thead>\n<tbody>\n"
            for group in top {
                let anchor = anchorID(for: group)
                out += "<tr><td><a href=\"#\(anchor)\">\(esc(group.ruleName))</a></td>"
                out += "<td>\(chip(group.metadata.impact.displayName, group.metadata.impact.rawValue))</td>"
                out += "<td>\(esc(group.metadata.wcagLabel ?? "—"))</td>"
                out += "<td class=\"num\">\(group.count)</td>"
                out += "<td>\(statusChip(group.status))</td></tr>\n"
            }
            out += "</tbody>\n</table>\n"
        }

        out += coverageSummaryHTML()

        out += "</section>\n"
        return out
    }

    private func kpi(_ title: String, _ value: Int, _ cssClass: String) -> String {
        "<div class=\"kpi \(cssClass)\"><span class=\"kpi-value\">\(value)</span><span class=\"kpi-label\">\(esc(title))</span></div>\n"
    }

    private func coverageSummaryHTML() -> String {
        let c = coverage
        var out = "<h3>How much was actually checked</h3>\n"
        out += "<table class=\"data\">\n<thead><tr><th scope=\"col\">Measure</th><th scope=\"col\" class=\"num\">Count</th></tr></thead>\n<tbody>\n"
        let rows: [(String, Int)] = [
            ("Rules in the rule set", c.rulesInRuleSet),
            ("Rules that produced pass or fail results", c.rulesWithAutomatedVerdict),
            ("Rules that only produced manual-review items", c.rulesManualReviewOnly),
            ("Rules that could not be tested (need assistive technology or a runtime probe)", c.rulesNotTested),
            ("Rules with no applicable content on the scanned screens", c.rulesNoApplicableContent),
            ("WCAG 2.2 A/AA criteria in total", c.criteriaTotalAAndAA),
            ("A/AA criteria with an automated verdict", c.criteriaWithAutomatedVerdict),
            ("A/AA criteria needing manual review only", c.criteriaManualReviewOnly),
            ("A/AA criteria not tested", c.criteriaNotTested),
            ("A/AA criteria with no applicable content", c.criteriaNoApplicableContent),
            ("A/AA criteria with no rule yet", c.criteriaWithoutRule)
        ]
        for (label, value) in rows {
            out += "<tr><td>\(esc(label))</td><td class=\"num\">\(value)</td></tr>\n"
        }
        out += "</tbody>\n</table>\n"
        out += "<p class=\"note\">A clean result only covers the criteria with an automated verdict. See <a href=\"#coverage\">Coverage</a> for every criterion.</p>\n"
        return out
    }

    // MARK: Findings

    private func findingsSection() -> String {
        var out = "<section id=\"findings\">\n<h2>Findings</h2>\n"
        let groups = grouping.issueGroups

        if groups.isEmpty {
            out += "<p class=\"empty\">No automated failures or warnings were recorded on the scanned screens.</p>\n</section>\n"
            return out
        }

        out += "<p class=\"note\">One entry per rule, most important first. Each lists every affected element with its fingerprint, a stable ID you can use to track the issue across scans.</p>\n"

        for group in groups {
            out += findingArticle(group, checklist: false)
        }

        out += "</section>\n"
        return out
    }

    private func manualReviewSection() -> String {
        var out = "<section id=\"manual-review\">\n<h2>Validate</h2>\n"
        let groups = grouping.manualReviewGroups

        if groups.isEmpty {
            out += "<p class=\"empty\">No manual verification is required.</p>\n</section>\n"
            return out
        }

        out += "<p class=\"note\">The scanner could not prove these checks pass or fail from black-box evidence. A tester must verify each item and record the result before sign-off.</p>\n"

        for group in groups {
            out += findingArticle(group, checklist: true)
        }

        out += "</section>\n"
        return out
    }

    private func findingArticle(_ group: GroupedFinding, checklist: Bool) -> String {
        var out = "<article class=\"finding \(group.status.rawValue)\" id=\"\(anchorID(for: group))\">\n"

        out += "<div class=\"finding-head\">\n<h3>\(esc(group.ruleName))</h3>\n<div class=\"chips\">"
        out += statusChip(group.status)
        if let bb = group.bbIssue {
            out += chip(bb.id, "neutral")
        }
        out += chip("\(group.metadata.impact.displayName) impact", group.metadata.impact.rawValue)
        if let wcag = group.metadata.wcagLabel {
            out += chip(wcag, "neutral")
        }
        out += chip("\(group.count) element\(plural(group.count)) · \(group.screenCount) screen\(plural(group.screenCount))", "neutral")
        out += "</div>\n</div>\n"

        out += "<p class=\"rule-id\"><code>\(esc(group.ruleID))</code>"
        if !group.ruleDescription.isEmpty {
            out += " · \(esc(group.ruleDescription))"
        }
        out += "</p>\n"

        out += "<dl class=\"facts\">\n"
        if let title = group.metadata.wcagTitle, let criterion = group.metadata.wcagCriterion {
            out += "<dt>Standard</dt><dd>\(esc(ScannerBuildInfo.wcagVersion)) \(esc(criterion)) \(esc(title))</dd>\n"
        }
        if let bb = group.bbIssue {
            let criterion = bb.wcag.map { " · WCAG \($0)" } ?? ""
            out += "<dt>BB issue</dt><dd>\(esc(bb.id)) · \(esc(bb.title))\(esc(criterion))</dd>\n"
        }
        if let bb = group.bbIfConfirmed {
            out += "<dt>If confirmed</dt><dd>Log as \(esc(bb.id)) · \(esc(bb.title))</dd>\n"
        }
        out += "<dt>Who is affected</dt><dd>\(esc(group.metadata.affectedUsers))</dd>\n"
        if !group.sampleMessage.isEmpty {
            out += "<dt>What was detected</dt><dd>\(esc(group.sampleMessage))</dd>\n"
        }
        if !group.remediation.isEmpty {
            out += "<dt>How to fix</dt><dd>\(esc(group.remediation))</dd>\n"
        }
        out += "<dt>How to verify</dt><dd>\(esc(group.metadata.howToTest))</dd>\n"
        out += "</dl>\n"

        out += "<table class=\"data elements\">\n<thead><tr>"
        if checklist { out += "<th scope=\"col\" class=\"check\"><span class=\"sr-only\">Verified</span></th>" }
        out += "<th scope=\"col\">Screen</th><th scope=\"col\">Element</th><th scope=\"col\">Detail</th><th scope=\"col\">Fingerprint</th>"
        if checklist { out += "<th scope=\"col\">Result / notes</th>" }
        out += "</tr></thead>\n<tbody>\n"

        for occurrence in group.occurrences {
            let evaluation = occurrence.evaluation
            out += "<tr>"
            if checklist { out += "<td class=\"check\"><span class=\"box\" aria-hidden=\"true\"></span></td>" }
            out += "<td>\(esc(occurrence.screenName))</td>"
            out += "<td>\(elementCell(evaluation))</td>"
            out += "<td>\(esc(evaluation.message))</td>"
            out += "<td><code>\(esc(occurrence.fingerprint))</code></td>"
            if checklist { out += "<td class=\"notes\"></td>" }
            out += "</tr>\n"
        }

        out += "</tbody>\n</table>\n</article>\n"
        return out
    }

    private func elementCell(_ evaluation: AccessibilityRuleEvaluation) -> String {
        let type = evaluation.elementType.replacingOccurrences(of: "XCUIElementType", with: "")
        var out = "<strong>\(esc(evaluation.targetDescription))</strong><br><span class=\"muted\">\(esc(type))"
        let identifier = evaluation.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !identifier.isEmpty, identifier != evaluation.targetDescription {
            out += " · id: \(esc(identifier))"
        }
        out += "</span>"
        return out
    }

    // MARK: Screens

    /// Fail / Validate / Pass switch for the screenshot markers. CSS only
    /// (radio buttons and :has), so it works where scripts are blocked.
    private func checkFilterHTML() -> String {
        let hasChecks = report.screens.contains { screen in
            screen.viewportScreenshots.contains { $0.checks != nil }
        }
        guard hasChecks else {
            return "<p class=\"note\">Numbered markers on screenshots highlight confirmed failures only.</p>\n"
        }
        let all = report.screens.flatMap { $0.viewportScreenshots.flatMap { $0.checks ?? [] } }
        func count(_ filter: ScreenshotCheckFilter) -> Int {
            all.filter { ScreenshotCheckFilter($0.displayStatus) == filter }.count
        }
        var out = "<fieldset class=\"check-filter\">\n<legend>Show components on screenshots</legend>\n"
        for filter in ScreenshotCheckFilter.allCases {
            let checked = filter == .fail ? " checked" : ""
            out += "<input type=\"radio\" name=\"check-filter\" id=\"cf-\(filter.rawValue)\" value=\"\(filter.rawValue)\"\(checked)>"
            out += "<label for=\"cf-\(filter.rawValue)\" class=\"\(filter.rawValue)\">\(esc(filter.title)) (\(count(filter)))</label>\n"
        }
        out += "</fieldset>\n"
        out += "<p class=\"note\">Markers are numbered within each filter.</p>\n"
        return out
    }

    private func screensSection() -> String {
        var out = "<section id=\"screens\">\n<h2>Screens &amp; evidence</h2>\n"

        if report.screens.isEmpty {
            out += "<p class=\"empty\">No screens were captured.</p>\n</section>\n"
            return out
        }

        if options.includeScreenshots {
            out += checkFilterHTML()
        }

        for screen in report.screens {
            out += "<article class=\"screen\">\n"
            out += "<h3>\(esc(screen.name))</h3>\n"
            out += "<p class=\"muted\">\(screen.elementCount) elements · "
            out += "\(screen.failures) fail · \(screen.validations) validate · \(screen.passes) pass</p>\n"

            if options.includeScreenshots {
                out += screenshotsHTML(for: screen)
            }
            out += "</article>\n"
        }

        out += "</section>\n"
        return out
    }

    private func screenshotsHTML(for screen: ScreenScanResult) -> String {
        struct Shot {
            let screenshot: ScanScreenshot
            let annotations: [ScreenshotAnnotation]
            var checks: [ScreenshotAnnotation]? = nil
            let caption: String
        }

        var shots: [Shot] = []
        if !screen.viewportScreenshots.isEmpty {
            let total = screen.viewportScreenshots.count
            for viewport in screen.viewportScreenshots.sorted(by: { $0.index < $1.index }) {
                shots.append(
                    Shot(
                        screenshot: viewport.screenshot,
                        annotations: viewport.annotations,
                        checks: viewport.checks,
                        caption: total > 1 ? "Viewport \(viewport.index) of \(total)" : "Screenshot"
                    )
                )
            }
        } else if let screenshot = screen.screenshot {
            shots.append(Shot(screenshot: screenshot, annotations: screen.annotations, caption: "Screenshot"))
        }

        guard !shots.isEmpty else { return "" }

        var out = "<div class=\"shots\">\n"
        for shot in shots {
            if let checks = shot.checks {
                out += filterableShotHTML(screen: screen, screenshot: shot.screenshot, checks: checks, caption: shot.caption)
                continue
            }
            let bytes = shot.screenshot.annotatedImageData ?? shot.screenshot.imageData
            out += "<figure>\n"
            if let encoded = ReportImageEncoder.encode(bytes, maxPixelSize: options.maxScreenshotPixelSize) {
                let alt = "\(screen.name), \(shot.caption), \(shot.annotations.count) marked failure\(plural(shot.annotations.count))"
                out += "<img src=\"\(encoded.dataURI)\" alt=\"\(esc(alt))\">\n"
            }
            out += "<figcaption>\(esc(shot.caption))</figcaption>\n"

            if !shot.annotations.isEmpty {
                out += "<ol class=\"markers\">\n"
                for annotation in shot.annotations.sorted(by: { $0.number < $1.number }) {
                    let name = annotation.elementLabel.isEmpty
                        ? annotation.elementType.replacingOccurrences(of: "XCUIElementType", with: "")
                        : annotation.elementLabel
                    out += "<li value=\"\(annotation.number)\"><strong>\(esc(annotation.ruleName))</strong> – \(esc(name))</li>\n"
                }
                out += "</ol>\n"
            }
            out += "</figure>\n"
        }
        out += "</div>\n"
        return out
    }

    private func filterableShotHTML(
        screen: ScreenScanResult,
        screenshot: ScanScreenshot,
        checks: [ScreenshotAnnotation],
        caption: String
    ) -> String {
        let width = max(screenshot.hierarchyWidth, 1)
        let height = max(screenshot.hierarchyHeight, 1)
        func percent(_ value: Double) -> String { String(format: "%.2f%%", value * 100) }
        func statusClass(_ check: ScreenshotAnnotation) -> String {
            "chk f-\(ScreenshotCheckFilter(check.displayStatus).rawValue)"
        }
        let ordered = checks.sorted {
            let lhs = ScreenshotCheckFilter($0.displayStatus).rawValue, rhs = ScreenshotCheckFilter($1.displayStatus).rawValue
            return lhs == rhs ? $0.number < $1.number : lhs < rhs
        }

        var out = "<figure>\n<div class=\"shot\">\n"
        if let encoded = ReportImageEncoder.encode(screenshot.imageData, maxPixelSize: options.maxScreenshotPixelSize) {
            out += "<img src=\"\(encoded.dataURI)\" alt=\"\(esc("\(screen.name), \(caption)"))\">\n"
        }
        for check in ordered {
            let frame = check.frame.intersection(CGRect(x: 0, y: 0, width: width, height: height))
            guard !frame.isNull, frame.width > 0, frame.height > 0 else { continue }
            out += "<span class=\"mark \(statusClass(check))\" style=\"left:\(percent(frame.minX / width));top:\(percent(frame.minY / height));width:\(percent(frame.width / width));height:\(percent(frame.height / height))\" aria-hidden=\"true\"><i>\(check.number)</i></span>\n"
        }
        out += "</div>\n<figcaption>\(esc(caption))</figcaption>\n"

        if !ordered.isEmpty {
            out += "<ol class=\"markers\">\n"
            for check in ordered {
                let name = check.elementLabel.isEmpty
                    ? check.elementType.replacingOccurrences(of: "XCUIElementType", with: "")
                    : check.elementLabel
                let code = check.bbIssueID.map { " <code>\(esc($0))</code>" } ?? ""
                out += "<li class=\"\(statusClass(check))\" value=\"\(check.number)\"><strong>\(esc(check.ruleName))</strong>\(code) – \(esc(name))<br><span class=\"muted\">\(esc(check.message))</span></li>\n"
            }
            out += "</ol>\n"
        }
        out += "</figure>\n"
        return out
    }

    // MARK: Runtime and screen-level results

    /// Whole-screen results (larger text, orientation, keyboard traversal):
    /// nothing to mark on a screenshot, so they are listed with their codes.
    private func runtimeSection() -> String {
        var out = "<section id=\"runtime\">\n<h2>Runtime and screen-level results</h2>\n"
        out += "<p>Checks of a whole screen, such as larger text, orientation and keyboard traversal. They cannot be marked on the screenshot.</p>\n"
        let screens = report.screens.filter { !$0.screenLevelResults.isEmpty }
        guard !screens.isEmpty else {
            return out + "<p class=\"empty\">No screen-level results in this scan.</p>\n</section>\n\n"
        }
        out += "<table class=\"data\">\n<thead><tr><th scope=\"col\">Screen</th><th scope=\"col\">Result</th><th scope=\"col\">Check</th><th scope=\"col\">BB code</th><th scope=\"col\">Detail</th></tr></thead>\n<tbody>\n"
        for screen in screens {
            for evaluation in screen.screenLevelResults {
                let code: String
                if let issue = BBIssueCatalog.issue(for: evaluation) {
                    code = "<code>\(esc(issue.id))</code> \(esc(issue.title))"
                } else if let pending = BBIssueCatalog.ifConfirmed(for: evaluation) {
                    code = "If confirmed: <code>\(esc(pending.id))</code> \(esc(pending.title))"
                } else {
                    code = "—"
                }
                var detail = esc(evaluation.message)
                if evaluation.status != .pass, !evaluation.remediation.isEmpty {
                    detail += "<br><span class=\"muted\">\(esc(evaluation.remediation))</span>"
                }
                out += "<tr><td>\(esc(screen.name))</td><td>\(statusChip(evaluation.status))</td><td>\(esc(evaluation.ruleName))</td><td>\(code)</td><td>\(detail)</td></tr>\n"
            }
        }
        out += "</tbody>\n</table>\n</section>\n\n"
        return out
    }

    // MARK: Coverage

    private func coverageSection() -> String {
        var out = "<section id=\"coverage\">\n<h2>Coverage: what was and was not checked</h2>\n"
        out += "<p>Every \(esc(ScannerBuildInfo.wcagVersion)) Level A and AA success criterion is listed, including those no rule covers yet, followed by any AAA criteria a rule maps to. Counts use the same unit as the summary.</p>\n"
        out += "<table class=\"data\">\n<thead><tr><th scope=\"col\">Criterion</th><th scope=\"col\">Level</th><th scope=\"col\">Coverage</th><th scope=\"col\" class=\"num\">Rules</th><th scope=\"col\" class=\"num\">Fail</th><th scope=\"col\" class=\"num\">Warn</th><th scope=\"col\" class=\"num\">Manual</th><th scope=\"col\" class=\"num\">Pass</th></tr></thead>\n<tbody>\n"
        for criterion in coverage.criteria {
            let rules = criterion.ruleIDs.isEmpty ? "—" : "\(criterion.ruleIDs.count)"
            out += "<tr><td>\(esc(criterion.number)) \(esc(criterion.title))</td>"
            out += "<td>\(esc(criterion.level))</td>"
            out += "<td>\(chip(criterion.state.title, criterion.state.cssClass))</td>"
            out += "<td class=\"num\">\(rules)</td>"
            out += "<td class=\"num\">\(criterion.failures)</td><td class=\"num\">\(criterion.warnings)</td><td class=\"num\">\(criterion.validations)</td><td class=\"num\">\(criterion.passes)</td></tr>\n"
        }
        out += "</tbody>\n</table>\n"
        out += "<p class=\"note\">Partly verified means some mapped rules passed while others still need manual review or could not be tested. Not a conformance statement.</p>\n"
        out += "</section>\n\n"
        return out
    }

    // MARK: BB ruleset coverage

    /// Every BB ID in the ruleset and what this scan did with it.
    private func bbCoverageSection() -> String {
        let entries = BBCoverage.entries(for: report)
        let platform = BBCoverage.platform(of: report) == .android ? "Android" : "iOS"
        func count(_ outcomes: Set<BBCoverageEntry.Outcome>) -> Int { entries.filter { outcomes.contains($0.outcome) }.count }

        var out = "<section id=\"bb-coverage\">\n<h2>BB ruleset coverage</h2>\n"
        out += "<p>All \(entries.count) rows of the BB ruleset for this \(esc(platform)) scan: "
        out += "\(count([.found, .passed, .review, .coveredBySibling])) produced results, \(count([.nothingApplicable])) were checked with nothing applicable, "
        out += "\(count([.manual])) need a manual check, \(count([.unavailable])) cannot be tested on \(esc(platform)) through Appium, \(count([.onHold])) are on hold and \(count([.outOfScope])) are Level AAA, which is out of scope.</p>\n"
        out += "<table class=\"data\">\n<thead><tr><th scope=\"col\">BB ID</th><th scope=\"col\">Issue</th><th scope=\"col\">Type</th><th scope=\"col\">WCAG</th><th scope=\"col\">Result</th><th scope=\"col\">Detail</th></tr></thead>\n<tbody>\n"
        for entry in entries {
            out += "<tr><td><code>\(esc(entry.id))</code></td><td>\(esc(entry.issue))</td><td>\(esc(entry.type))</td><td>\(esc(entry.wcag))</td>"
            out += "<td>\(chip(entry.outcome.title, entry.outcome.cssClass))</td><td>\(esc(entry.detail))</td></tr>\n"
        }
        out += "</tbody>\n</table>\n</section>\n\n"
        return out
    }

    // MARK: Scope

    private func scopeSection() -> String {
        """
        <section id="scope">
        <h2>Scope &amp; limitations</h2>
        <h3>What this scan covered</h3>
        <ul>
        <li>\(report.screens.count) screen\(plural(report.screens.count)) and \(report.totalElementsTested) elements on <strong>\(esc(report.deviceName))</strong>, captured through Appium on \(esc(report.startedAt.formatted(date: .abbreviated, time: .omitted))).</li>
        <li>Rule set \(esc(ScannerBuildInfo.ruleSetVersion)) has \(coverage.rulesInRuleSet) rules, mapped to \(esc(ScannerBuildInfo.wcagVersion)). On this scan \(coverage.rulesWithAutomatedVerdict) produced pass or fail results, \(coverage.rulesManualReviewOnly) produced manual-review items only, \(coverage.rulesNotTested) could not be tested and \(coverage.rulesNoApplicableContent) found nothing applicable.</li>
        </ul>
        <h3>What it does not tell you</h3>
        <ul>
        <li><strong>Not a conformance claim.</strong> Automated rules exercise only a subset of \(esc(ScannerBuildInfo.wcagVersion)). A clean report does not mean the app conforms.</li>
        <li><strong>Black-box evidence.</strong> Checks use the accessibility hierarchy and screenshots. Anything that needs real assistive-technology behaviour is reported as <em>manual review</em> rather than guessed.</li>
        <li><strong>Reachability.</strong> Only screens the crawler reached are covered. Content behind sign-in, rare states and unexplored flows may be untested.</li>
        <li><strong>One configuration.</strong> Results apply to the device, OS version, text size, orientation and language in effect during the scan.</li>
        <li><strong>Interpretation.</strong> Rule-to-criterion mapping, impact ratings and test steps are the scanner's guidance and should be confirmed by an accessibility specialist for formal audits.</li>
        </ul>
        <h3>How to read the numbers</h3>
        <ul>
        <li>All result counts are unique rule results: one rule applied to one element on one screen. Identical results recorded twice are merged.</li>
        <li>A <em>fingerprint</em> identifies a rule failing on a specific element of a specific screen. It is stable across scans of the same build, so you can track fixes and regressions with it.</li>
        </ul>
        </section>

        """
    }


    // MARK: Appendix

    private func appendixSection() -> String {
        var out = "<section id=\"appendix\">\n<h2>Appendix: rule results</h2>\n"
        out += "<p>Every rule in the rule set, including rules that produced no result on this scan.</p>\n"
        out += "<table class=\"data\">\n<thead><tr><th scope=\"col\">Rule</th><th scope=\"col\">Standard</th><th scope=\"col\">Impact</th><th scope=\"col\">Outcome</th><th scope=\"col\" class=\"num\">Fail</th><th scope=\"col\" class=\"num\">Warn</th><th scope=\"col\" class=\"num\">Manual</th><th scope=\"col\" class=\"num\">Pass</th></tr></thead>\n<tbody>\n"
        let ordered = coverage.rules.sorted {
            if $0.failures != $1.failures { return $0.failures > $1.failures }
            if $0.warnings != $1.warnings { return $0.warnings > $1.warnings }
            if $0.outcome.rank != $1.outcome.rank { return $0.outcome.rank < $1.outcome.rank }
            return $0.ruleName.localizedCaseInsensitiveCompare($1.ruleName) == .orderedAscending
        }
        for entry in ordered {
            let metadata = AccessibilityRuleCatalog.metadata(for: entry.ruleID)
            out += "<tr><td>\(esc(entry.ruleName))<br><code>\(esc(entry.ruleID))</code></td>"
            out += "<td>\(esc(metadata.wcagLabel ?? "—"))</td>"
            out += "<td>\(esc(metadata.impact.displayName))</td>"
            out += "<td>\(chip(entry.outcome.title, entry.outcome.cssClass))</td>"
            out += "<td class=\"num\">\(entry.failures)</td><td class=\"num\">\(entry.warnings)</td><td class=\"num\">\(entry.validations)</td><td class=\"num\">\(entry.passes)</td></tr>\n"
        }
        out += "</tbody>\n</table>\n</section>\n"
        return out
    }

    private func footer() -> String {
        let stamp = generatedAt.formatted(date: .long, time: .shortened)
        return """
        <footer>
        Generated \(esc(stamp)) by \(esc(ScannerBuildInfo.productName)) \(esc(ScannerBuildInfo.displayVersion)) · rule set \(esc(ScannerBuildInfo.ruleSetVersion)) · report \(esc(report.id.uuidString))
        </footer>

        """
    }

    // MARK: Helpers

    private func anchorID(for group: GroupedFinding) -> String {
        let safe = group.id.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        return "finding-\(safe)"
    }

    private func statusChip(_ status: RuleResultStatus) -> String {
        chip(status.displayName, status.rawValue)
    }

    private func intelligenceChip(_ status: IntelligenceStatus) -> String {
        chip(status.title, status.rawValue)
    }

    private func chip(_ text: String, _ cssClass: String) -> String {
        "<span class=\"chip \(esc(cssClass))\">\(esc(text))</span>"
    }

    private func plural(_ count: Int) -> String {
        count == 1 ? "" : "s"
    }

    private func esc(_ value: String) -> String {
        var result = value
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&#39;")
        return result
    }

    // MARK: CSS

    private static let css = """
    :root { --fg:#1d2433; --muted:#5b6475; --line:#d9dee7; --bg:#f5f7fa; --card:#fff;
      --fail:#b42318; --fail-bg:#fef3f2; --warning:#93370d; --warning-bg:#fffaeb;
      --validate:#175cd3; --validate-bg:#eff8ff; --pass:#067647; --pass-bg:#ecfdf3; }
    * { box-sizing:border-box; }
    body { margin:0; background:var(--bg); color:var(--fg);
      font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif; }
    .page { max-width:1040px; margin:0 auto; padding:32px 24px 56px; }
    h1 { font-size:2rem; margin:.2em 0 .4em; line-height:1.2; }
    h2 { font-size:1.4rem; margin:0 0 .6em; padding-bottom:.3em; border-bottom:2px solid var(--line); }
    h3 { font-size:1.05rem; margin:1.4em 0 .5em; }
    section { margin-top:40px; }
    code { font:12px ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; background:#eef1f6; padding:1px 5px; border-radius:4px; }
    a { color:#175cd3; }
    .muted { color:var(--muted); }
    .note { color:var(--muted); font-size:.9rem; }
    .empty { padding:16px; background:var(--card); border:1px solid var(--line); border-radius:8px; }
    .eyebrow { margin:0; text-transform:uppercase; letter-spacing:.08em; font-size:.75rem; color:var(--muted); font-weight:600; }
    .cover { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:28px; }
    .verdict { padding:12px 14px; border-radius:8px; border-left:5px solid; margin:0 0 20px; }
    .verdict.fail { background:var(--fail-bg); border-color:var(--fail); }
    .verdict.warning { background:var(--warning-bg); border-color:var(--warning); }
    .verdict.validate { background:var(--validate-bg); border-color:var(--validate); }
    .verdict.pass { background:var(--pass-bg); border-color:var(--pass); }
    .meta { display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:12px 24px; margin:0; }
    .meta dt { font-size:.72rem; text-transform:uppercase; letter-spacing:.06em; color:var(--muted); }
    .meta dd { margin:0; word-break:break-word; }
    nav { display:flex; flex-wrap:wrap; gap:6px 18px; margin:18px 2px 0; font-size:.9rem; }
    .kpis { display:grid; grid-template-columns:repeat(auto-fit,minmax(130px,1fr)); gap:12px; margin:8px 0 6px; }
    .kpi { background:var(--card); border:1px solid var(--line); border-top:4px solid var(--line); border-radius:8px; padding:12px 14px; }
    .kpi.fail { border-top-color:var(--fail); } .kpi.warning { border-top-color:var(--warning); }
    .kpi.validate { border-top-color:var(--validate); } .kpi.pass { border-top-color:var(--pass); }
    .kpi.nottested { border-top-color:#98a2b3; }
    .kpi-value { display:block; font-size:1.9rem; font-weight:700; line-height:1.1; }
    .kpi-label { color:var(--muted); font-size:.85rem; }
    table.data { width:100%; border-collapse:collapse; background:var(--card); border:1px solid var(--line); font-size:.88rem; margin:8px 0 14px; }
    table.data th { text-align:left; background:#eef1f6; font-weight:600; }
    table.data th, table.data td { padding:7px 10px; border-bottom:1px solid var(--line); vertical-align:top; }
    table.data .num, .num { text-align:right; font-variant-numeric:tabular-nums; }
    .chip { display:inline-block; padding:2px 9px; margin:0 4px 4px 0; border-radius:999px; font-size:.75rem; font-weight:600; border:1px solid var(--line); background:#eef1f6; color:var(--fg); white-space:nowrap; }
    .chip.fail,.chip.critical { background:var(--fail-bg); color:var(--fail); border-color:#fda29b; }
    .chip.warning,.chip.serious { background:var(--warning-bg); color:var(--warning); border-color:#fec84b; }
    .chip.validate,.chip.moderate { background:var(--validate-bg); color:var(--validate); border-color:#84caff; }
    .chip.pass { background:var(--pass-bg); color:var(--pass); border-color:#75e0a7; }
    .chip.nottested { background:#f2f4f7; color:#475467; border-color:#98a2b3; }
    .chip.norule { background:transparent; color:var(--muted); border-style:dashed; }
    .finding { background:var(--card); border:1px solid var(--line); border-left:5px solid var(--line); border-radius:8px; padding:16px 18px; margin:16px 0; }
    .finding.fail { border-left-color:var(--fail); } .finding.warning { border-left-color:var(--warning); }
    .finding.validate { border-left-color:var(--validate); }
    .finding-head { display:flex; flex-wrap:wrap; justify-content:space-between; gap:6px 16px; align-items:flex-start; }
    .finding-head h3 { margin:0; }
    .rule-id { margin:.3em 0 .8em; color:var(--muted); font-size:.85rem; }
    .facts { display:grid; grid-template-columns:140px 1fr; gap:6px 14px; margin:0 0 10px; font-size:.9rem; }
    .facts dt { color:var(--muted); font-weight:600; } .facts dd { margin:0; }
    .check { width:28px; } .box { display:inline-block; width:14px; height:14px; border:1.5px solid var(--fg); border-radius:3px; }
    td.notes { min-width:140px; }
    .shots { display:flex; flex-wrap:wrap; gap:18px; margin-top:10px; }
    figure { margin:0; width:260px; } figure img { width:100%; height:auto; border:1px solid var(--line); border-radius:6px; display:block; }
    figcaption { font-size:.8rem; color:var(--muted); margin:4px 0; }
    .markers { padding-left:22px; margin:4px 0; font-size:.8rem; }
    .markers li { margin-bottom:4px; }
    .check-filter { border:1px solid var(--line); border-radius:8px; background:var(--card); padding:8px 12px; margin:8px 0; display:flex; flex-wrap:wrap; gap:8px; align-items:center; }
    .check-filter legend { font-size:.8rem; color:var(--muted); padding:0 4px; }
    .check-filter input { position:absolute; opacity:0; }
    .check-filter label { cursor:pointer; padding:4px 12px; border-radius:999px; border:1px solid var(--line); font-weight:600; font-size:.85rem; }
    .check-filter input:focus-visible + label { outline:2px solid #175cd3; outline-offset:2px; }
    .check-filter input:checked + label.fail { background:var(--fail-bg); color:var(--fail); border-color:var(--fail); }
    .check-filter input:checked + label.validate { background:var(--validate-bg); color:var(--validate); border-color:var(--validate); }
    .check-filter input:checked + label.pass { background:var(--pass-bg); color:var(--pass); border-color:var(--pass); }
    .shot { position:relative; }
    .mark { position:absolute; border:2px solid var(--fail); background:rgba(217,45,32,.08); border-radius:3px; box-sizing:border-box; }
    .mark i { position:absolute; top:-9px; left:-9px; min-width:16px; height:16px; padding:0 3px; border-radius:8px; font:700 10px/16px system-ui,sans-serif; font-style:normal; text-align:center; color:#fff; background:var(--fail); }
    .mark.f-warning { border-color:var(--warning); background:rgba(220,104,3,.08); } .mark.f-warning i { background:var(--warning); }
    .check-filter input:checked + label.warning { background:var(--warning-bg); color:var(--warning); border-color:var(--warning); }
    .mark.f-validate { border-color:var(--validate); background:rgba(21,112,239,.08); } .mark.f-validate i { background:var(--validate); }
    .mark.f-pass { border-color:var(--pass); background:rgba(7,148,85,.08); } .mark.f-pass i { background:var(--pass); }
    #screens:has(#cf-fail:checked) .chk:not(.f-fail),
    #screens:has(#cf-validate:checked) .chk:not(.f-validate),
    #screens:has(#cf-pass:checked) .chk:not(.f-pass) { display:none; }
    .screen { background:var(--card); border:1px solid var(--line); border-radius:8px; padding:16px 18px; margin:14px 0; }
    .screen h3 { margin-top:0; }
    ul { padding-left:20px; }
    footer { margin-top:40px; padding-top:14px; border-top:1px solid var(--line); color:var(--muted); font-size:.8rem; }
    .sr-only { position:absolute; width:1px; height:1px; overflow:hidden; clip:rect(0 0 0 0); white-space:nowrap; }
    @page { size:A4; margin:14mm; }
    @media print {
      body { background:#fff; font-size:10pt; }
      .page { max-width:none; padding:0; }
      nav { display:none; }
      section { margin-top:22px; }
      a { color:inherit; text-decoration:none; }
      * { -webkit-print-color-adjust:exact; print-color-adjust:exact; }
      .cover,.kpi,.finding-head,.facts,.screen,figure,tr { break-inside:avoid; }
      h2,h3 { break-after:avoid; }
      thead { display:table-header-group; }
      #findings,#manual-review,#screens { break-before:page; }
    }
    @media (max-width:640px) { .facts { grid-template-columns:1fr; } }
    """
}
