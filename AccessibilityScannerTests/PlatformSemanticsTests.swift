//
//  PlatformSemanticsTests.swift
//  AccessibilityScannerTests
//
//  Parser and rule behaviour for data only some platforms expose.
//

import Testing
import Foundation
import CoreGraphics
import AppKit
@testable import AccessibilityScanner

@MainActor
@Suite("Platform semantics")
struct PlatformSemanticsTests {

    /// A UiAutomator2 dump as a React Native / Flutter app produces it.
    private let androidXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <hierarchy index="0" class="hierarchy" rotation="0" width="1080" height="2400">
      <android.widget.FrameLayout index="0" package="com.example" class="android.widget.FrameLayout" text="" resource-id="" checkable="false" checked="false" clickable="false" enabled="true" focusable="false" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[0,0][1080,2400]" displayed="true" a11y-important="false" pane-title="Checkout">
        <android.widget.TextView index="0" package="com.example" class="android.widget.TextView" text="Payment details" resource-id="title" checkable="false" checked="false" clickable="false" enabled="true" focusable="false" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[40,100][1040,180]" displayed="true" a11y-important="true" heading="true" text-size="66.0" />
        <android.view.ViewGroup index="1" package="com.example" class="android.view.ViewGroup" text="" content-desc="" hint="Add card" resource-id="add" checkable="false" checked="false" clickable="true" enabled="true" focusable="true" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[40,200][240,320]" displayed="true" a11y-important="true" />
        <android.widget.Button index="2" package="com.example" class="android.widget.Button" text="Pay now" content-desc="Submit order" resource-id="pay" checkable="false" checked="false" clickable="true" enabled="true" focusable="true" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[40,400][1040,520]" displayed="true" a11y-important="true" />
        <android.widget.Button index="3" package="com.example" class="android.widget.Button" text="Help" content-desc="" resource-id="help" checkable="false" checked="false" clickable="true" enabled="true" focusable="true" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[40,560][1040,680]" displayed="true" a11y-important="false" />
        <android.widget.EditText index="4" package="com.example" class="android.widget.EditText" text="" hint="Email" resource-id="email" checkable="false" checked="false" clickable="true" enabled="true" focusable="true" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[40,720][1040,840]" displayed="true" a11y-important="true" input-type="1" />
      </android.widget.FrameLayout>
    </hierarchy>
    """

    private func parseAndroid() throws -> AccessibilityNode {
        try AndroidElementParser(displayScale: 3).parse(androidXML)
    }

    private func evaluations(_ rule: AccessibilityRule, _ root: AccessibilityNode) -> [AccessibilityRuleEvaluation] {
        if let screen = rule as? ScreenAccessibilityRule { return screen.evaluate(rootNode: root) }
        return ProbeNodes.all(in: root).compactMap { rule.evaluate(node: $0) }
    }

    @Test func androidAttributesAreRead() throws {
        let root = try parseAndroid()
        let nodes = ProbeNodes.all(in: root)
        let title = try #require(nodes.first { $0.identifier == "title" })
        #expect(title.semantics.isHeading == true)
        #expect(title.traits.contains("heading"))
        #expect(title.semantics.textSizePoints == 22)
        #expect(nodes.contains { $0.semantics.paneTitle == "Checkout" })

        let pay = try #require(nodes.first { $0.identifier == "pay" })
        #expect(pay.label == "Submit order")
        #expect(pay.semantics.visibleText == "Pay now")

        let add = try #require(nodes.first { $0.identifier == "add" })
        #expect(add.semantics.roleInferred)
        #expect(add.semantics.hint == "Add card")

        let help = try #require(nodes.first { $0.identifier == "help" })
        #expect(!help.accessible, "a11y-important=false must hide the view from TalkBack")
    }

    @Test func androidRulesUseTheNewAttributes() throws {
        let root = try parseAndroid()
        func statuses(_ rule: AccessibilityRule, id: String) -> [RuleResultStatus] {
            evaluations(rule, root).filter { $0.identifier == id }.map(\.status)
        }
        #expect(statuses(MissingRoleRule(), id: "add") == [.fail])
        #expect(statuses(NameViaHintRule(), id: "add") == [.fail])
        #expect(statuses(LabelInNameRule(), id: "pay") == [.fail])
        #expect(statuses(ScreenReaderHiddenInteractiveRule(), id: "help") == [.fail])
        #expect(statuses(InputPurposeRule(), id: "email") == [.validate])
        // No duplicate missing-name result for the hint-only control.
        #expect(statuses(CommonAccessibleNameRule(), id: "add").isEmpty)
        #expect(statuses(DescriptiveButtonNameRule(), id: "add").isEmpty)
    }

    @Test func realTextSizeDrivesLargeTextCodes() throws {
        let title = try #require(ProbeNodes.all(in: try parseAndroid()).first { $0.identifier == "title" })
        #expect(TextSizeEstimate.classify(title) == .large)
        let evaluation = makeEvaluation(ruleID: "contrast-text-over-image", status: .fail, node: title)
        #expect(BBIssueCatalog.issue(for: evaluation)?.id == "BB40020")
    }

    @Test func iOSCustomActionsAreRead() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <AppiumAUT>
          <XCUIElementTypeApplication type="XCUIElementTypeApplication" name="App" label="App" enabled="true" visible="true" accessible="false" x="0" y="0" width="390" height="844" index="0">
            <XCUIElementTypeCell type="XCUIElementTypeCell" name="row" label="Inbox item" enabled="true" visible="true" accessible="true" x="0" y="100" width="390" height="60" index="0" customActions="Delete,Archive"/>
          </XCUIElementTypeApplication>
        </AppiumAUT>
        """
        let root = try WDAElementParser().parse(xml)
        let row = try #require(ProbeNodes.all(in: root).first { $0.identifier == "row" })
        #expect(row.semantics.customActions == ["Delete", "Archive"])
        let result = ComplexGestureRule().evaluate(node: row)
        #expect(result?.status == .pass)
        #expect(result.flatMap { BBIssueCatalog.issue(for: $0)?.id } == "BB40191")
    }

    @Test func labelInNameAcceptsMatchingNames() {
        var node = makeNode(type: "android.widget.Button", label: "Pay now with card")
        node.semantics.visibleText = "Pay now"
        #expect(LabelInNameRule().evaluate(node: node)?.status == .pass)
    }

    @Test func bbCoverageAccountsForEveryRow() {
        let node = makeNode(label: "")
        let screen = ScreenScanResult(
            name: "Screen 1", elementCount: 1,
            evaluations: [makeEvaluation(ruleID: "button-name-descriptive", status: .fail, node: node)]
        )
        let report = AccessibilityScanResult(
            applicationName: "App", bundleID: "a.b", deviceName: "Phone", deviceUDID: "x",
            startedAt: Date(), finishedAt: Date(), screens: [screen], rulesExecuted: 1
        )
        let entries = BBCoverage.entries(for: report)
        #expect(entries.count == BBRuleset.rules.count)
        #expect(entries.first { $0.id == "BB40003" }?.outcome == .found)
        #expect(entries.first { $0.id == "BB40105" }?.outcome == .unavailable)
        #expect(entries.first { $0.id == "BB40001" }?.outcome == .manual)
    }

    @Test func carouselTextOffScreenIsNotClipped() {
        let offScreenChip = makeNode(type: "XCUIElementTypeStaticText", label: "#Fitness", frame: CGRect(x: 443, y: 217, width: 80, height: 44))
        let halfVisibleChip = makeNode(type: "XCUIElementTypeStaticText", label: "#Mindset", frame: CGRect(x: 349, y: 217, width: 87, height: 44))
        let carousel = makeNode(type: "XCUIElementTypeScrollView", frame: CGRect(x: 0, y: 200, width: 393, height: 80), children: [offScreenChip, halfVisibleChip])
        let cutOff = makeNode(type: "XCUIElementTypeStaticText", label: "Cut off text", frame: CGRect(x: 300, y: 400, width: 200, height: 20))
        let root = makeNode(type: "XCUIElementTypeApplication", frame: CGRect(x: 0, y: 0, width: 393, height: 852), children: [carousel, cutOff])

        let failures = TextClippingRule().evaluate(rootNode: root).filter { $0.status == .fail }.map(\.elementLabel)
        #expect(failures == ["Cut off text"])
    }

    @Test func navigationBarTitleFromInnerText() {
        let title = makeNode(type: "XCUIElementTypeStaticText", label: "Explore")
        let bar = makeNode(type: "XCUIElementTypeNavigationBar", label: "", frame: CGRect(x: 0, y: 59, width: 393, height: 106), children: [title])
        #expect(ScreenTitleRule().evaluate(node: bar)?.status == .pass)

        let emptyBar = makeNode(type: "XCUIElementTypeNavigationBar", label: "", frame: CGRect(x: 0, y: 59, width: 393, height: 44))
        #expect(ScreenTitleRule().evaluate(node: emptyBar)?.status == .fail)
    }

    @Test func iOSScrollIndicatorsAreIgnored() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <AppiumAUT>
          <XCUIElementTypeApplication type="XCUIElementTypeApplication" name="App" label="App" enabled="true" visible="true" accessible="false" x="0" y="0" width="393" height="852" index="0">
            <XCUIElementTypeScrollView type="XCUIElementTypeScrollView" enabled="true" visible="true" accessible="false" x="0" y="100" width="393" height="600" index="0">
              <XCUIElementTypeStaticText type="XCUIElementTypeStaticText" name="Title" label="Title" enabled="true" visible="true" accessible="true" x="16" y="120" width="200" height="20" index="0"/>
              <XCUIElementTypeOther type="XCUIElementTypeOther" label="Vertical scroll bar, 3 pages" enabled="true" visible="true" accessible="true" x="360" y="165" width="30" height="604" index="1"/>
              <XCUIElementTypeOther type="XCUIElementTypeOther" label="Horizontal scroll bar, 1 page" enabled="true" visible="true" accessible="true" x="55" y="736" width="283" height="30" index="2"/>
            </XCUIElementTypeScrollView>
          </XCUIElementTypeApplication>
        </AppiumAUT>
        """
        let labels = ProbeNodes.all(in: try WDAElementParser().parse(xml)).map(\.label)
        #expect(labels.contains("Title"))
        #expect(!labels.contains { $0.contains("scroll bar") })
    }

    /// Jetpack Compose as UiAutomator2 dumps it: names live in child Text
    /// nodes, toggleable Rows wrap a non-focusable Checkbox, and items cut off
    /// by the scroll edge have clipped bounds.
    private let composeXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <hierarchy index="0" class="hierarchy" rotation="0" width="1152" height="2496">
      <android.widget.ScrollView index="0" package="com.example" class="android.widget.ScrollView" text="" resource-id="" checkable="false" checked="false" clickable="false" enabled="true" focusable="false" focused="false" long-clickable="false" password="false" scrollable="true" selected="false" bounds="[0,108][1152,2352]" displayed="true">
        <android.view.View index="0" package="com.example" class="android.view.View" text="" resource-id="radioRow" checkable="false" checked="false" clickable="true" enabled="true" focusable="true" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[48,108][222,189]" displayed="true">
          <android.widget.RadioButton index="0" package="com.example" class="android.widget.RadioButton" text="" resource-id="radio" checkable="true" checked="false" clickable="false" enabled="true" focusable="false" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[48,108][222,153]" displayed="true">
            <android.widget.TextView index="0" package="com.example" class="android.widget.TextView" text="Male" resource-id="" checkable="false" checked="false" clickable="false" enabled="true" focusable="false" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[132,108][222,141]" displayed="true" />
          </android.widget.RadioButton>
        </android.view.View>
        <android.widget.TextView index="1" package="com.example" class="android.widget.TextView" text="1. Button — PASS" resource-id="caption" checkable="false" checked="false" clickable="false" enabled="true" focusable="false" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[48,300][330,342]" displayed="true" />
        <android.widget.Button index="2" package="com.example" class="android.widget.Button" text="" resource-id="submit" checkable="false" checked="false" clickable="true" enabled="true" focusable="true" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[48,411][330,531]" displayed="true">
          <android.widget.TextView index="0" package="com.example" class="android.widget.TextView" text="Submit" resource-id="submitText" checkable="false" checked="false" clickable="false" enabled="true" focusable="false" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[120,441][258,501]" displayed="true" />
        </android.widget.Button>
        <android.view.View index="3" package="com.example" class="android.view.View" text="" resource-id="termsRow" checkable="true" checked="false" clickable="true" enabled="true" focusable="true" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[48,663][507,807]" displayed="true">
          <android.widget.CheckBox index="0" package="com.example" class="android.widget.CheckBox" text="" resource-id="terms" checkable="true" checked="false" clickable="false" enabled="true" focusable="false" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[48,699][507,771]" displayed="true">
            <android.widget.TextView index="0" package="com.example" class="android.widget.TextView" text="I agree to the terms" resource-id="" checkable="false" checked="false" clickable="false" enabled="true" focusable="false" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[144,711][507,762]" displayed="true" />
          </android.widget.CheckBox>
        </android.view.View>
        <android.widget.EditText index="4" package="com.example" class="android.widget.EditText" text="" resource-id="name" checkable="false" checked="false" clickable="true" enabled="true" focusable="true" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[48,1140][1104,1332]" displayed="true">
          <android.widget.TextView index="0" package="com.example" class="android.widget.TextView" text="Full name" resource-id="" checkable="false" checked="false" clickable="false" enabled="true" focusable="false" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[84,1170][1068,1220]" displayed="true" />
        </android.widget.EditText>
        <android.widget.Button index="5" package="com.example" class="android.widget.Button" text="" resource-id="unnamed" checkable="false" checked="false" clickable="true" enabled="true" focusable="true" focused="false" long-clickable="false" password="false" scrollable="false" selected="false" bounds="[48,1500][192,1644]" displayed="true" />
      </android.widget.ScrollView>
    </hierarchy>
    """

    @Test func composeChildTextNamesControls() throws {
        let root = try AndroidElementParser(displayScale: 3).parse(composeXML)
        let nodes = ProbeNodes.all(in: root)
        func node(_ id: String) throws -> AccessibilityNode { try #require(nodes.first { $0.identifier == id }) }
        func statuses(_ rule: AccessibilityRule, _ id: String) -> [RuleResultStatus] {
            evaluations(rule, root).filter { $0.identifier == id }.map(\.status)
        }

        #expect(try node("submit").label == "Submit")
        #expect(try node("termsRow").label == "I agree to the terms")
        #expect(try node("name").label == "Full name")
        #expect(try node("terms").semantics.mergedIntoAncestor)
        #expect(try node("radioRow").semantics.partiallyVisible)
        #expect(try node("submitText").semantics.insideActionable)

        #expect(statuses(DescriptiveButtonNameRule(), "submit") == [.pass])
        #expect(statuses(DescriptiveButtonNameRule(), "unnamed") == [.fail], "a Button with no text anywhere is still unnamed")
        #expect(statuses(CommonAccessibleNameRule(), "termsRow") == [.pass])
        #expect(statuses(CommonAccessibleNameRule(), "name") == [.pass])
        #expect(statuses(CommonAccessibleNameRule(), "terms").isEmpty, "merged into the row")
        #expect(statuses(MissingRoleRule(), "termsRow") == [.pass], "the Checkbox child carries the role")
        #expect(statuses(CommonMinimumTargetSizeRule(), "radioRow").isEmpty, "cut off by the scroll edge")
        #expect(statuses(CommonMinimumTargetSizeRule(), "terms").isEmpty)
        #expect(statuses(ButtonRoleRule(), "submitText").isEmpty, "text inside a button")
        #expect(statuses(ButtonRoleRule(), "caption").isEmpty, "a descriptive caption is not button text")
        #expect(evaluations(TextSpacingRule(), root).count == 1, "one text-spacing check per screen")
    }

    @Test func htmlReportFiltersScreenshotChecks() throws {
        let context = try #require(CGContext(data: nil, width: 120, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 240))
        let image = try #require(context.makeImage())
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))

        let failing = makeNode(type: "XCUIElementTypeButton", label: "", frame: CGRect(x: 10, y: 20, width: 40, height: 40))
        let named = makeNode(type: "XCUIElementTypeButton", label: "Save", frame: CGRect(x: 10, y: 80, width: 100, height: 44))
        let evaluations = [
            makeEvaluation(ruleID: "button-name-descriptive", status: .fail, node: failing),
            makeEvaluation(ruleID: "button-name-descriptive", status: .pass, node: named),
            makeEvaluation(ruleID: "interactive-name-descriptive", status: .validate, node: named)
        ]
        let checks = ScreenshotAnnotation.makeAnnotations(from: evaluations, statuses: ScreenResultBuilder.checkStatuses)
        let viewport = ScreenshotViewport(
            index: 1,
            screenshot: ScanScreenshot(imageData: png, width: 120, height: 240, hierarchyWidth: 120, hierarchyHeight: 240),
            annotations: ScreenshotAnnotation.makeAnnotations(from: evaluations),
            checks: checks
        )
        let screen = ScreenScanResult(name: "Screen 1", elementCount: 2, evaluations: evaluations, viewportScreenshots: [viewport])
        let report = AccessibilityScanResult(
            applicationName: "App", bundleID: "a.b", deviceName: "Phone", deviceUDID: "x",
            startedAt: Date(), finishedAt: Date(), screens: [screen], rulesExecuted: 3
        )
        let html = HTMLReportExporter().makeHTML(from: report)

        #expect(html.contains("id=\"cf-fail\" value=\"fail\" checked"))
        #expect(html.contains("Validate (1)"))
        #expect(html.contains("Pass (1)"))
        #expect(html.contains("class=\"mark chk f-fail\""))
        #expect(html.contains("class=\"mark chk f-validate\""))
        #expect(html.contains("class=\"mark chk f-pass\""))
        #expect(html.contains("<code>BB40003</code>"))

        if let path = ProcessInfo.processInfo.environment["SCANNER_HTML_PREVIEW"] {
            try html.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    @Test func textFieldBoxIsNotMeasuredAsText() throws {
        let root = try AndroidElementParser(displayScale: 3).parse(composeXML)
        let field = try #require(ProbeNodes.all(in: root).first { $0.identifier == "name" })
        #expect(field.label == "Full name")
        // The child "Full name" text is measured on its own; the field box is not.
        #expect(ContrastStandardTextRule().evaluate(node: field, context: AccessibilityRuleContext()) == nil)
    }

    @Test func runtimeResultsHaveTheirOwnSection() {
        let root = makeNode(type: "XCUIElementTypeApplication", label: "App", frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let locked = makeEvaluation(ruleID: "orientation-support", status: .fail, node: root,
                                    message: "The screen stayed in portrait when the device was rotated to landscape. The screen is locked in one orientation.")
        let screen = ScreenScanResult(name: "Screen 1", elementCount: 1, evaluations: [locked])
        #expect(screen.screenLevelResults.count == 1)
        let report = AccessibilityScanResult(
            applicationName: "App", bundleID: "a.b", deviceName: "Phone", deviceUDID: "x",
            startedAt: Date(), finishedAt: Date(), screens: [screen], rulesExecuted: 1
        )
        let html = HTMLReportExporter().makeHTML(from: report)
        #expect(html.contains("<section id=\"runtime\">"))
        #expect(html.contains("<code>BB40056</code>"))
    }
}
