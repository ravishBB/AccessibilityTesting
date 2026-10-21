//
//  ScannerLogicTests.swift
//  AccessibilityScannerTests
//

import Testing
import AppKit
import Foundation
import CoreGraphics
@testable import AccessibilityScanner

@MainActor
@Suite("Text size estimate")
struct TextSizeEstimateTests {

    private func size(_ width: CGFloat, _ height: CGFloat, _ text: String) -> TextSizeClass {
        TextSizeEstimate.classify(frame: CGRect(x: 0, y: 0, width: width, height: height), text: text, role: .staticText)
    }

    private func points(_ width: CGFloat, _ height: CGFloat, _ text: String) -> CGFloat {
        TextSizeEstimate.fontSize(frame: CGRect(x: 0, y: 0, width: width, height: height), text: text) ?? 0
    }

    @Test func singleLineEstimate() {
        // iOS 17pt body text has a line height of about 20.3pt.
        #expect(abs(points(160, 20.3, "Sign in to continue") - 17) < 1)
        // A short label stretched across a full-width frame is still one line.
        #expect(abs(points(343, 20.3, "Sign in to continue") - 17) < 1)
    }

    @Test func wrappedParagraphEstimate() {
        let paragraph = String(repeating: "word ", count: 24)
        #expect(abs(points(343, 61, paragraph) - 17) < 1.5)
    }

    @Test func smallTextIsStandard() {
        // 13pt footnote.
        #expect(size(200, 15.5, "Terms apply") == .standard)
    }

    @Test func bodyTextIsLargeOnlyIfBold() {
        // 14 to 18pt: large only when bold, which the hierarchy cannot tell.
        #expect(size(160, 20.3, "Sign in to continue") == .possiblyLarge)
    }

    @Test func titleIsLarge() {
        #expect(size(200, 34, "Settings") == .large)
    }

    @Test func midSizeIsPossiblyLarge() {
        #expect(size(200, 19, "Subheading") == .possiblyLarge)
    }

    @Test func textFieldsAreAlwaysStandard() {
        let frame = CGRect(x: 0, y: 0, width: 300, height: 44)
        #expect(TextSizeEstimate.classify(frame: frame, text: "Email", role: .textField) == .standard)
    }
}

@MainActor
@Suite("Action safety")
struct ActionSafetyTests {

    private func explore(_ label: String, _ identifier: String = "") -> Bool {
        ActionSafety.isSafeToExplore(makeNode(label: label, identifier: identifier))
    }

    @Test func blocksIrreversibleActions() {
        #expect(!explore("Pay now"))
        #expect(!explore("Confirm transfer"))
        #expect(!explore("Sign Out"))
        #expect(!explore("", "btnTrash"))
        #expect(!explore("Send"))
    }

    @Test func matchesWholeWordsOnly() {
        #expect(explore("Display settings"))
        #expect(explore("Credit card"))
        #expect(explore("Saved items"))
        #expect(explore("Clearance sale"))
    }

    @Test func probesMaySignInButCrawlerMayNot() {
        let signIn = makeNode(label: "Sign in")
        #expect(ActionSafety.isSafeToActivate(signIn))
        #expect(!ActionSafety.isSafeToExplore(signIn))
    }

    @Test func dismissPrefersCancelAndNeverAccepts() {
        let buttons = [makeNode(label: "Submit anyway"), makeNode(label: "Cancel")]
        #expect(ActionSafety.dismissButton(in: buttons)?.label == "Cancel")

        let permission = [makeNode(label: "Allow"), makeNode(label: "Don't Allow")]
        #expect(ActionSafety.dismissButton(in: permission)?.label == "Don't Allow")

        #expect(ActionSafety.dismissButton(in: [makeNode(label: "Delete")]) == nil)
    }
}

@MainActor
@Suite("Scan notes and settings")
struct ScanNotesTests {

    @Test func groupsOccurrencesWithExamples() {
        let notes = ScanNotes()
        notes.record(.tapFailed, example: "Help")
        notes.record(.tapFailed, example: "Share")
        notes.record(.tapFailed, example: "Help")
        #expect(notes.summaries.count == 1)
        #expect(notes.summaries[0].hasPrefix("3 actions could not be tapped"))
        #expect(notes.summaries[0].contains("Help, Share"))
    }

    @Test func emptyWhenNothingWentWrong() {
        #expect(ScanNotes().isEmpty)
        #expect(ScanNotes().summaries.isEmpty)
    }

    @Test func appiumURLValidation() {
        #expect(ScannerSettings.validAppiumURL("http://127.0.0.1:4723") != nil)
        #expect(ScannerSettings.validAppiumURL("https://grid.example.com/wd/hub") != nil)
        #expect(ScannerSettings.validAppiumURL("127.0.0.1:4723") == nil)
        #expect(ScannerSettings.validAppiumURL("") == nil)
    }
}

@Suite("Process runner")
struct ProcessRunnerTests {

    @Test func largeOutputDoesNotDeadlock() throws {
        let output = try ProcessRunner.run(
            "/bin/sh",
            ["-c", "head -c 300000 /dev/zero | tr '\\0' a; head -c 200000 /dev/zero | tr '\\0' b 1>&2"],
            timeout: 20
        )
        #expect(output.status == 0)
        #expect(output.stdout.count == 300_000)
        #expect(output.stderr.count == 200_000)
    }

    @Test func hungCommandIsStopped() {
        let started = Date()
        #expect(throws: ProcessRunner.RunnerError.self) {
            _ = try ProcessRunner.run("/bin/sleep", ["30"], timeout: 1)
        }
        #expect(Date().timeIntervalSince(started) < 10)
    }
}

@MainActor
@Suite("Report building")
struct ReportBuildingTests {

    @Test func mergeReplacesSameElementAndAppendsNew() {
        let button = makeNode(label: "Save")
        let other = makeNode(label: "Help", frame: CGRect(x: 0, y: 100, width: 100, height: 44))
        let base = [makeEvaluation(ruleID: "r", status: .validate, node: button)]
        let additions = [
            makeEvaluation(ruleID: "r", status: .fail, node: button),
            makeEvaluation(ruleID: "r", status: .pass, node: other)
        ]
        let merged = ScreenResultBuilder.mergeEvaluations(base, additions)
        #expect(merged.map(\.status) == [.fail, .pass])
    }

    @Test func consistencyNotesFlagContradictions() {
        let node = makeNode(label: "Save")
        let screen = ScreenScanResult(
            name: "Screen 1",
            signature: "s",
            elementCount: 1,
            evaluations: [
                makeEvaluation(ruleID: "touch-target-size-24", status: .pass, node: node),
                makeEvaluation(ruleID: "touch-target-size-24", status: .fail, node: node)
            ],
            transitions: [],
            screenshot: nil,
            annotations: [],
            viewportScreenshots: []
        )
        let report = AccessibilityScanResult(
            applicationName: "App", bundleID: "a.b", deviceName: "Phone", deviceUDID: "x",
            startedAt: Date(), finishedAt: Date(), screens: [screen], rulesExecuted: 1
        )
        let notes = AccessibilityReportIntegrity.consistencyNotes(report)
        #expect(notes.contains { $0.contains("touch-target-size-24 both passed and failed") })
        #expect(notes.contains { $0.contains("no screenshot") })
    }
}

@Suite("Device discovery")
struct DeviceDiscoveryTests {

    /// Runs against this Mac's simulators; passes trivially where none exist.
    @Test func simulatorsParseFromJSON() throws {
        let devices = try DeviceDiscoveryService().discoverDevices()
        for simulator in devices where simulator.isSimulator {
            #expect(simulator.udid.count == 36, "\(simulator.name) has UDID \(simulator.udid)")
            #expect(!simulator.name.isEmpty)
        }
    }
}

@MainActor
@Suite("Rule availability")
struct RuleAvailabilityTests {

    @Test func platformRuleSetsNameRealRules() {
        let catalogued = Set(AccessibilityRuleCatalog.allMetadata.map(\.ruleID))
        let named = AccessibilityRuleCatalog.notAutomatable
            .union(AccessibilityRuleCatalog.notAutomatableOnIOS)
            .union(AccessibilityRuleCatalog.reviewOnly)
        #expect(named.subtracting(catalogued).isEmpty, "Unknown rule IDs: \(named.subtracting(catalogued).sorted())")
    }

    @Test func iOSCountsExcludeRulesThatCannotRun() {
        let total = AccessibilityRuleCatalog.ruleCount
        let iOS = AccessibilityRuleCatalog.verdictCapableRuleCount(on: .ios)
        let android = AccessibilityRuleCatalog.verdictCapableRuleCount(on: .android)
        #expect(iOS == total - AccessibilityRuleCatalog.cannotRun(on: .ios).count - AccessibilityRuleCatalog.reviewOnly.count)
        #expect(android > iOS)
    }

    @Test func layoutContainerResizeKeepsSignature() {
        let text = makeNode(type: "XCUIElementTypeStaticText", label: "Title", frame: CGRect(x: 16, y: 120, width: 200, height: 20))
        func screen(containerHeight: CGFloat) -> AccessibilityNode {
            let container = makeNode(type: "XCUIElementTypeOther", label: "", frame: CGRect(x: 0, y: -384, width: 393, height: containerHeight),
                                     accessible: false, children: [text])
            return makeNode(type: "XCUIElementTypeApplication", frame: CGRect(x: 0, y: 0, width: 393, height: 852), children: [container])
        }
        #expect(ScreenSignature(rootNode: screen(containerHeight: 1154)) == ScreenSignature(rootNode: screen(containerHeight: 1186)))

        let moved = makeNode(type: "XCUIElementTypeStaticText", label: "Title", frame: CGRect(x: 16, y: 60, width: 200, height: 20))
        let scrolled = makeNode(type: "XCUIElementTypeApplication", frame: CGRect(x: 0, y: 0, width: 393, height: 852), children: [moved])
        #expect(ScreenSignature(rootNode: screen(containerHeight: 1154)) != ScreenSignature(rootNode: scrolled))
    }

    @Test func swiftUIToggleInnerSwitchIsNotCheckedAlone() {
        let inner = makeNode(type: "XCUIElementTypeSwitch", label: "", frame: CGRect(x: 300, y: 218, width: 63, height: 29), accessible: false)
        let toggle = makeNode(type: "XCUIElementTypeSwitch", label: "Low Contrast Text", frame: CGRect(x: 32, y: 218, width: 329, height: 29), children: [inner])
        let app = makeNode(type: "XCUIElementTypeApplication", frame: CGRect(x: 0, y: 0, width: 393, height: 852), accessible: false, children: [toggle])
        let root = app.annotatingLayout()
        let nodes = ProbeNodes.all(in: root)
        let innerNode = nodes.first { $0.label.isEmpty && $0.type == "XCUIElementTypeSwitch" }!
        #expect(innerNode.semantics.mergedIntoAncestor)
        #expect(CommonAccessibleNameRule().evaluate(node: innerNode) == nil)
        #expect(ScreenReaderHiddenInteractiveRule().evaluate(node: innerNode) == nil)
    }

    @Test func spacingExceptionForSmallIsolatedTargets() {
        let bookmark = makeNode(type: "XCUIElementTypeButton", label: "Bookmark article", frame: CGRect(x: 346, y: 183, width: 18, height: 22))
        let card = makeNode(type: "XCUIElementTypeButton", label: "Read story", frame: CGRect(x: 16, y: 300, width: 200, height: 44))
        let heart = makeNode(type: "XCUIElementTypeButton", label: "Favourite", frame: CGRect(x: 152, y: 581, width: 21, height: 19))
        let cart = makeNode(type: "XCUIElementTypeButton", label: "Add to cart", frame: CGRect(x: 175, y: 581, width: 20, height: 20))
        let root = makeNode(type: "XCUIElementTypeApplication", frame: CGRect(x: 0, y: 0, width: 393, height: 852), accessible: false,
                            children: [bookmark, card, heart, cart])
        let results = CommonMinimumTargetSizeRule().evaluate(rootNode: root)
        func status(_ label: String) -> RuleResultStatus? { results.first { $0.elementLabel == label }?.status }
        #expect(status("Bookmark article") == .pass, "isolated: spacing exception")
        #expect(status("Favourite") == .fail, "another small target is within 24 pt")
        #expect(status("Read story") == .pass)
    }

    @Test func slideThatScrollsIsDetectedAsScroll() {
        func screen(offset: CGFloat) -> AccessibilityNode {
            let texts = ["One", "Two", "Three", "Four", "Five"].enumerated().map { index, label in
                makeNode(type: "XCUIElementTypeStaticText", label: label, frame: CGRect(x: 16, y: 100 + CGFloat(index) * 60 + offset, width: 200, height: 20))
            }
            return makeNode(type: "XCUIElementTypeApplication", frame: CGRect(x: 0, y: 0, width: 393, height: 852), children: texts)
        }
        #expect(ProbeNodes.contentScrolled(from: screen(offset: 0), to: screen(offset: -160)))
        #expect(!ProbeNodes.contentScrolled(from: screen(offset: 0), to: screen(offset: 0)))
    }

    @Test func cardLabelInNameUsesTheTitle() {
        let texts = ["● LIVE", "WELLNESS", "Morning Routines That Actually Work", "By Sarah Chen  ·  5 min read"].map {
            makeNode(type: "XCUIElementTypeStaticText", label: $0,
                     frame: CGRect(x: 32, y: 400, width: 300, height: $0.hasPrefix("Morning") ? 28 : 16))
        }
        let card = makeNode(type: "XCUIElementTypeButton", label: "Wellness article: Morning Routines That Actually Work, by Sarah Chen, 5 minute read",
                            frame: CGRect(x: 16, y: 304, width: 361, height: 241), children: texts)
        #expect(LabelInNameRule().evaluate(node: card)?.status == .pass)
    }

    @Test func shortenedTextNeedsLabelPrefixAndEllipsis() {
        #expect(ProbeNodes.shortenedText(drawn: "Morning Routines That…", label: "Morning Routines That Actually Work") != nil)
        #expect(ProbeNodes.shortenedText(drawn: "Morning Routines That...", label: "Morning Routines That Actually Work") != nil)
        #expect(ProbeNodes.shortenedText(drawn: "Morning Routines That Actually Work", label: "Morning Routines That Actually Work") == nil)
        #expect(ProbeNodes.shortenedText(drawn: "Loading…", label: "Morning Routines") == nil, "not the label's start")
    }

    @Test func overlapCausedByScalingFails() {
        func screen(_ frames: [(String, CGRect)]) -> AccessibilityNode {
            makeNode(type: "XCUIElementTypeApplication", frame: CGRect(x: 0, y: 0, width: 393, height: 852),
                     children: frames.map { makeNode(type: "XCUIElementTypeStaticText", label: $0.0, frame: $0.1) })
        }
        let normal = screen([("Title", CGRect(x: 16, y: 100, width: 200, height: 20)), ("Subtitle", CGRect(x: 16, y: 124, width: 200, height: 18))])
        let large = screen([("Title", CGRect(x: 16, y: 100, width: 200, height: 40)), ("Subtitle", CGRect(x: 16, y: 124, width: 200, height: 36))])
        #expect(TextSizeProbe.overlap(normal: normal, large: large).first?.status == .fail)
        #expect(TextSizeProbe.overlap(normal: normal, large: normal).first?.status == .pass)
        // Overlapping already at normal size: a design choice, not scaling.
        #expect(TextSizeProbe.overlap(normal: large, large: large).first?.status == .pass)
    }

    @Test func focusCueSeparatesOutlineFromColourOnly() throws {
        func png(_ draw: (CGContext) -> Void) throws -> Data {
            let context = try #require(CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            draw(context)
            let image = try #require(context.makeImage())
            return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        }
        let control = makeNode(frame: CGRect(x: 50, y: 50, width: 100, height: 100))
        let size = CGSize(width: 200, height: 200)
        let unfocused = try png { $0.setFillColor(CGColor(red: 0.85, green: 0.2, blue: 0.2, alpha: 1)); $0.fill(CGRect(x: 50, y: 50, width: 100, height: 100)) }
        let ring = try png {
            $0.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); $0.fill(CGRect(x: 45, y: 45, width: 110, height: 110))
            $0.setFillColor(CGColor(red: 0.85, green: 0.2, blue: 0.2, alpha: 1)); $0.fill(CGRect(x: 50, y: 50, width: 100, height: 100))
        }
        let hueOnly = try png { $0.setFillColor(CGColor(red: 0.2, green: 0.55, blue: 0.2, alpha: 1)); $0.fill(CGRect(x: 50, y: 50, width: 100, height: 100)) }

        let outline = try #require(KeyboardFocusTester.focusCue(before: unfocused, after: ring, node: control, hierarchySize: size))
        #expect(outline.hasOutline)
        let colour = try #require(KeyboardFocusTester.focusCue(before: unfocused, after: hueOnly, node: control, hierarchySize: size))
        #expect(!colour.hasOutline)
        #expect(colour.stateRatio < 3, "red to green of similar lightness")
    }

    @Test func combinedListIsReportedButCardIsNot() {
        func row(_ title: String, _ y: CGFloat) -> AccessibilityNode {
            makeNode(type: "XCUIElementTypeOther", label: "", frame: CGRect(x: 16, y: y, width: 361, height: 60), accessible: false, children: [
                makeNode(type: "XCUIElementTypeStaticText", label: title, frame: CGRect(x: 24, y: y + 8, width: 300, height: 20), accessible: false),
                makeNode(type: "XCUIElementTypeStaticText", label: "5 min read", frame: CGRect(x: 24, y: y + 32, width: 100, height: 16), accessible: false)
            ])
        }
        let list = makeNode(type: "XCUIElementTypeOther", label: "Morning, Evening, Weekend", frame: CGRect(x: 16, y: 100, width: 361, height: 200),
                            children: [row("Morning", 100), row("Evening", 160), row("Weekend", 220)]).annotatingLayout()
        #expect(ListItemsNavigableRule().evaluate(node: list)?.status == .validate)

        let card = makeNode(type: "XCUIElementTypeButton", label: "Wellness article: Morning Routines",
                            frame: CGRect(x: 16, y: 300, width: 361, height: 240), children: [
                                makeNode(type: "XCUIElementTypeStaticText", label: "WELLNESS", accessible: false),
                                makeNode(type: "XCUIElementTypeStaticText", label: "Morning Routines", accessible: false),
                                makeNode(type: "XCUIElementTypeStaticText", label: "By Sarah Chen", accessible: false)
                            ]).annotatingLayout()
        #expect(ListItemsNavigableRule().evaluate(node: card) == nil)
    }

    @Test func androidPictureWithoutImageRole() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <hierarchy index="0" class="hierarchy" rotation="0" width="1080" height="2400">
          <android.view.View index="0" package="com.example" class="android.view.View" text="" content-desc="Mountain sunrise" resource-id="hero" checkable="false" checked="false" clickable="false" enabled="true" focusable="false" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[0,200][1080,800]" displayed="true" />
          <android.widget.TextView index="1" package="com.example" class="android.widget.TextView" text="Welcome" resource-id="title" checkable="false" checked="false" clickable="false" enabled="true" focusable="false" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[0,900][1080,1000]" displayed="true" />
        </hierarchy>
        """
        let root = try AndroidElementParser(displayScale: 3).parse(xml)
        let results = ProbeNodes.all(in: root).compactMap { ImageRoleRule().evaluate(node: $0) }
        #expect(results.map(\.identifier) == ["hero"])
    }

    @Test func contentUnderTabBarIsNotATargetOverlap() {
        let row = makeNode(type: "XCUIElementTypeButton", label: "Food illustration, FOOD", frame: CGRect(x: 0, y: 705, width: 393, height: 112))
        let scroll = makeNode(type: "XCUIElementTypeScrollView", frame: CGRect(x: 0, y: 0, width: 393, height: 852), accessible: false, children: [row])
        let home = makeNode(type: "XCUIElementTypeButton", label: "Home", frame: CGRect(x: 25, y: 773, width: 85, height: 54))
        let bar = makeNode(type: "XCUIElementTypeTabBar", frame: CGRect(x: 0, y: 769, width: 393, height: 83), accessible: false, children: [home])
        let root = makeNode(type: "XCUIElementTypeApplication", frame: CGRect(x: 0, y: 0, width: 393, height: 852), accessible: false,
                            children: [scroll, bar]).annotatingLayout()
        let nodes = ProbeNodes.all(in: root)
        #expect(nodes.first { $0.label.hasPrefix("Food") }?.semantics.partiallyVisible == true)
        #expect(nodes.first { $0.label == "Home" }?.semantics.partiallyVisible == false)
        #expect(InteractiveTargetOverlapRule().evaluate(rootNode: root).isEmpty)
    }

    @Test func backButtonIsNeverTappedByProbes() {
        let back = makeNode(type: "XCUIElementTypeButton", label: "Bloom", identifier: "BackButton", frame: CGRect(x: 16, y: 59, width: 44, height: 44))
        let readMore = makeNode(type: "XCUIElementTypeButton", label: "Read more", frame: CGRect(x: 300, y: 59, width: 44, height: 44))
        #expect(!ActionSafety.isSafeToExplore(back))
        #expect(!ActionSafety.isSafeToActivate(back))
        #expect(ActionSafety.isSafeToExplore(readMore))
    }

    @Test func tappableIconWithoutButtonTrait() {
        let add = makeNode(type: "XCUIElementTypeImage", label: "Add", identifier: "plus.circle.fill", frame: CGRect(x: 150, y: 120, width: 24, height: 24))
        let photo = makeNode(type: "XCUIElementTypeImage", label: "Mountain sunrise", identifier: "hero", frame: CGRect(x: 0, y: 100, width: 393, height: 200))
        let inButton = makeNode(type: "XCUIElementTypeButton", label: "Share article", frame: CGRect(x: 300, y: 60, width: 44, height: 44), children: [
            makeNode(type: "XCUIElementTypeImage", label: "Share", identifier: "square.and.arrow.up", frame: CGRect(x: 310, y: 70, width: 20, height: 24), accessible: false)
        ])
        let root = makeNode(type: "XCUIElementTypeApplication", frame: CGRect(x: 0, y: 0, width: 393, height: 852), accessible: false,
                            children: [add, photo, inButton]).annotatingLayout()
        let results = ProbeNodes.all(in: root).compactMap { IconControlRoleRule().evaluate(node: $0) }
        #expect(results.map(\.elementLabel) == ["Add"])
        #expect(BBIssueCatalog.ifConfirmed(for: results[0])?.id == "BB40282")
    }

    @Test func silentVoiceOverStopFails() {
        // Text inside is still listed in the hierarchy but VoiceOver does not read it.
        let silent = makeNode(type: "XCUIElementTypeOther", label: "", frame: CGRect(x: 15, y: 107, width: 179, height: 146), children: [
            makeNode(type: "XCUIElementTypeStaticText", label: "Morning Rituals", frame: CGRect(x: 25, y: 200, width: 120, height: 20), accessible: false)
        ])
        let named = makeNode(type: "XCUIElementTypeOther", label: "Morning Rituals collection, 8 articles", frame: CGRect(x: 200, y: 107, width: 178, height: 146))
        let root = makeNode(type: "XCUIElementTypeApplication", frame: CGRect(x: 0, y: 0, width: 393, height: 852), accessible: false,
                            children: [silent, named]).annotatingLayout()
        let nodes = ProbeNodes.all(in: root)
        let silentResult = ScreenReaderContentRule().evaluate(node: nodes.first { $0.frame.minX == 15 }!)
        #expect(silentResult?.status == .fail)
        #expect(BBIssueCatalog.issue(for: silentResult!)?.id == "BB40057")
        #expect(ScreenReaderContentRule().evaluate(node: nodes.first { $0.frame.minX == 200 }!)?.status == .pass)
    }

    @Test func seeAllTextLooksLikeAButton() {
        let seeAll = makeNode(type: "XCUIElementTypeStaticText", label: "See all", frame: CGRect(x: 328, y: 177, width: 49, height: 20))
        let result = ButtonRoleRule().evaluate(node: seeAll.annotatingLayout())
        #expect(result?.status == .validate)
        #expect(BBIssueCatalog.ifConfirmed(for: result!)?.id == "BB40043")
    }

    @Test func uikitTableCellIsAContainerNotASilentStop() {
        let bookmark = makeNode(type: "XCUIElementTypeButton", label: "", frame: CGRect(x: 333, y: 555, width: 44, height: 45))
        let title = makeNode(type: "XCUIElementTypeStaticText", label: "The Art of Slow Travel", frame: CGRect(x: 104, y: 558, width: 221, height: 38))
        let cell = makeNode(type: "XCUIElementTypeCell", label: "", frame: CGRect(x: 0, y: 525, width: 393, height: 105), children: [title, bookmark])
        let root = makeNode(type: "XCUIElementTypeApplication", frame: CGRect(x: 0, y: 0, width: 393, height: 852), accessible: false,
                            children: [cell]).annotatingLayout()
        let nodes = ProbeNodes.all(in: root)
        // A container: neither a silent stop (fail) nor content of its own (no result).
        #expect(ScreenReaderContentRule().evaluate(node: nodes.first { $0.type == "XCUIElementTypeCell" }!) == nil)
        // Its button is checked on its own: an unnamed one fails.
        let button = nodes.first { $0.type == "XCUIElementTypeButton" }!
        #expect(!button.semantics.mergedIntoAncestor)
        #expect(DescriptiveButtonNameRule().evaluate(node: button)?.status == .fail)
    }

    @Test func uikitArticleRowWithoutRoleIsValidate() {
        let row = makeNode(type: "XCUIElementTypeCell", label: "", frame: CGRect(x: 0, y: 525, width: 393, height: 105), children: [
            makeNode(type: "XCUIElementTypeImage", label: "Travel illustration", frame: CGRect(x: 16, y: 542, width: 72, height: 71)),
            makeNode(type: "XCUIElementTypeStaticText", label: "TRAVEL", frame: CGRect(x: 104, y: 541, width: 221, height: 14)),
            makeNode(type: "XCUIElementTypeStaticText", label: "The Art of Slow Travel", frame: CGRect(x: 104, y: 558, width: 221, height: 38)),
            makeNode(type: "XCUIElementTypeStaticText", label: "Marco Rivera · 7 min", frame: CGRect(x: 104, y: 599, width: 221, height: 15)),
            makeNode(type: "XCUIElementTypeButton", label: "Bookmark article", frame: CGRect(x: 333, y: 555, width: 44, height: 45))
        ])
        let chips = makeNode(type: "XCUIElementTypeCell", label: "", frame: CGRect(x: 0, y: 229, width: 393, height: 57), children: [
            makeNode(type: "XCUIElementTypeButton", label: "All", frame: CGRect(x: 16, y: 237, width: 50, height: 41)),
            makeNode(type: "XCUIElementTypeButton", label: "Wellness", frame: CGRect(x: 74, y: 237, width: 97, height: 41)),
            makeNode(type: "XCUIElementTypeStaticText", label: "A", frame: CGRect(x: 0, y: 0, width: 10, height: 10)),
            makeNode(type: "XCUIElementTypeStaticText", label: "B", frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        ])
        let root = makeNode(type: "XCUIElementTypeApplication", frame: CGRect(x: 0, y: 0, width: 393, height: 852), accessible: false,
                            children: [row, chips]).annotatingLayout()
        let results = ProbeNodes.all(in: root).compactMap { TableRowRoleRule().evaluate(node: $0) }
        #expect(results.count == 1, "the article row only, not the chip bar")
        #expect(BBIssueCatalog.ifConfirmed(for: results[0])?.id == "BB40282")
    }

    @Test func screensAreNamedByTheirTitle() {
        let frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let bar = makeNode(type: "XCUIElementTypeNavigationBar", label: "Settings", frame: CGRect(x: 0, y: 59, width: 393, height: 44), accessible: false)
        #expect(ScreenNaming.name(for: makeNode(type: "XCUIElementTypeApplication", frame: frame, children: [bar]), number: 1) == "Settings")

        // Large-title SwiftUI bar: the title is a text inside the bar.
        let largeBar = makeNode(type: "XCUIElementTypeNavigationBar", label: "", frame: CGRect(x: 0, y: 59, width: 393, height: 96), accessible: false,
                                children: [makeNode(type: "XCUIElementTypeStaticText", label: "Home", frame: CGRect(x: 16, y: 100, width: 120, height: 41))])
        #expect(ScreenNaming.name(for: makeNode(type: "XCUIElementTypeApplication", frame: frame, children: [largeBar]), number: 2) == "Home")

        // Nothing to go on: keep the number.
        #expect(ScreenNaming.name(for: makeNode(type: "XCUIElementTypeApplication", frame: frame), number: 3) == "Screen 3")

        let screens = ["Article", "Home", "Article"].map { ScreenScanResult(name: $0, elementCount: 0, evaluations: []) }
        #expect(ScreenNaming.uniquified(screens).map(\.name) == ["Article", "Home", "Article 2"])
    }
}
