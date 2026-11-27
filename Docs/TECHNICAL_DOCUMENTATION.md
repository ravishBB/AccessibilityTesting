# AccessibilityScanner — Technical Documentation

As of 2026-11-27. Editable copy: [AccessibilityScanner — Technical Documentation](https://claude.ai/artifact/AE4We3bTR2Bm3sxMPRGrYn)

## Overview

AccessibilityScanner is a macOS SwiftUI app. It drives an iOS or Android app on a real device or simulator through Appium, reads the app's accessibility tree screen by screen, and checks it against the BarrierBreak (BB) ruleset sheets. Every result is reported under a BB ID from the iOS or Android sheet as Pass, Fail, Validate (needs a tester's judgement) or Not tested. AAA rules are out of scope.

The code is 74 Swift files (about 26,000 lines) in nine folders, plus a test target.

| Folder | Files | What lives there |
| --- | --- | --- |
| `App/` | 2 | App entry point and the installed-app model |
| `Configuration/` | 2 | Appium URL, signing team, Android SDK path and the settings screen |
| `Services/` | 4 | Finding devices and installed apps through `xcrun`, `devicectl` and `adb` |
| `Appium/` | 4 | The Appium HTTP client and the XML parsers for iOS (WDA) and Android (UiAutomator2) hierarchies |
| `Core/` | 24 | The element model, roles, rule protocols, BB ruleset and catalog, pixel analysis and the runtime probes |
| `Core/Crawling/` | 4 | The crawler that walks the app screen by screen |
| `Core/Rules/` | 1 | Every static accessibility rule |
| `Reports/` | 19 | Building per-screen results, BB coverage, screenshot annotation, and the JSON and HTML exports |
| `UI/` | 9 | The scanner window, the scan view model and the report views |
| `AccessibilityScannerTests/` | 5 | Swift Testing suites built from real scan hierarchies |

The sections below follow a scan's path through the code: UI, then Appium, the core model, crawling, rules and probes, reports, and tests. Each file has one row: what it does and the main types in it.

## App, configuration and UI

This is the macOS app the tester uses. `ScannerViewModel` owns the whole scan; the views only show its state and the finished report.

| File | Lines | What it does | Main types |
| --- | --- | --- | --- |
| `App/AccessibilityScannerApp.swift` | 37 | `@main` entry point. Opens the main window and the Settings scene. At launch it restores any Android font scale left changed by an interrupted scan; on quit it deletes open Appium sessions. | `AccessibilityScannerApp`, `AppDelegate` |
| `App/App.swift` | 21 | Model for one installed app shown in the app picker. The file holds only this struct. | `InstalledApp` (name, bundle ID or Android package, version, build) |
| `Configuration/ScannerConfiguration.swift` | 47 | Settings for one scan, used to create the Appium session: server URL, bundle ID, device, platform, Android activity and density, auto-launch, iPhone signing team. | `ScannerConfiguration` |
| `Configuration/ScannerSettings.swift` | 105 | Saved preferences (UserDefaults) and the Settings (⌘,) form: Appium URL (default `http://127.0.0.1:4723`), signing team and ID for physical iPhones, Android SDK folder. | `ScannerSettings`, `ScannerSettingsView` |
| `UI/ContentView.swift` | 824 | The main window: device and app pickers, scan scope (Full App, Current Page, Stop After N Pages), the relaunch and shake toggles, Start and Stop buttons, live status, summary tiles and the findings list. Opens the full report as a sheet. | `ContentView` |
| `UI/ScannerViewModel.swift` | 1004 | Runs device and app discovery and the whole scan (see the scan steps below). Builds the report or a partial report on Stop, and always releases the Appium session. | `ScannerViewModel`, `ScanMode`, `StableScanSnapshot` |
| `UI/GuidedChecks.swift` | 132 | Checks the scanner cannot do alone (shake, Tab, VoiceOver). Shows a card asking the tester to act, pauses the scan until they answer, and closes the card itself if it sees the phone react. | `GuidedChecks`, `GuidedChecksOverlay` |
| `UI/ScanReportView.swift` | 1316 | The full report sheet: summary and environment, BB report, Developer Fix Center, screen results, app map, and the Issue Explorer (screenshot with highlighted elements, failure navigation, scrolled viewports). | `ScanReportView`, `InteractiveScreenshotView` |
| `UI/BBReportView.swift` | 348 | Results grouped by BB issue and category, in Overview and Issues tabs with a status filter. Clicking an item highlights the element on the screenshot. | `BBReportView`, `ReportFilter`, `SegmentButtons` |
| `UI/AccessibilityAppMapView.swift` | 493 | The App Map: each screen as a box in a 3-column grid, arrows for the navigation between them, and each screen's metrics and transitions. | `AccessibilityAppMapView` |
| `UI/FindingCard.swift` | 204 | One card in the main window's findings list: message, rule ID, severity, element details and fix. | `FindingCard` |
| `UI/SummaryCard.swift` | 55 | A small tile with an icon, title and count (Issues, Errors, Warnings, Info). | `SummaryCard` |
| `UI/ShareReportMenu.swift` | 115 | The Export menu: open the HTML report in the browser, save it, or share the HTML or JSON file. | `ShareReportMenu` |

### What happens in one scan

`ScannerViewModel.performScan` runs these steps in order:

1. **Prepare.** Warm up text recognition, check a device and app are selected, and on Android look up the app's launch activity.
2. **Connect.** Build a `ScannerConfiguration`, then `AppiumClient.checkServer()` and `createSession`.
3. **Launch.** Full App and Limited modes launch the app and check it is in front. Current Page mode stops if another app is in front.
4. **Environment.** `makeEnvironment` records OS, device model, automation and Appium version (and the app version on Android).
5. **First snapshot.** `captureStableSnapshot` reads the hierarchy twice around a screenshot and retries until the two match. If the tree has fewer than 3 meaningful elements, it waits and retries up to 4 times, because Flutter builds its tree late.
6. **Read the build (iOS).** `MotionHandlerInspector` and `AppLanguageInspector` read the app's build on the Mac for shake handlers and languages.
7. **Crawl.** `AppCrawler.crawl` visits up to 1 (Current Page), N (Limited) or 100 (Full App) screens. On each screen it runs the rules while scrolling, the keyboard focus test, the runtime probes, the shake check, the screen reader order test and the row taps.
8. **Per-screen results.** `ScreenResultBuilder.build` turns each crawled screen into rule evaluations and annotated screenshots.
9. **Settle.** `ScreenNaming` gives screens unique names; on iOS the build findings are added to screens that were not shaken.
10. **Check and publish.** `AccessibilityReportIntegrity.validate` checks the result. If it finds a problem, no report is saved; otherwise the report is shown.
11. **Clean up.** The Appium session is always deleted, and device changes are restored, even after Stop or an error. On Stop, the screens already finished become a partial report.

## Device services and Appium

Services find devices and apps by calling command-line tools on the Mac. Every action on the phone during a scan goes through `AppiumClient`, and the two parsers turn each platform's XML into the same `AccessibilityNode` tree.

| File | Lines | What it does | Main types |
| --- | --- | --- | --- |
| `Services/DeviceDiscoveryService.swift` | 485 | Builds the device list: iOS simulators (`xcrun simctl`), physical iPhones (`xcrun devicectl`) and Android devices. If one source fails, the others still show. | `DeviceDiscoveryService`, `DeviceDiscoveryError` |
| `Services/AppDiscoveryService.swift` | 327 | Lists installed apps on the selected device: `simctl listapps` for simulators, `devicectl device info apps` for iPhones, `AndroidDeviceService` for Android. Hides `com.apple.*` apps. | `AppDiscoveryService`, `AppDiscoveryError` |
| `Services/AndroidDeviceService.swift` | 299 | Every Android operation through `adb`: find `adb`, list devices and explain blocked ones (unauthorised, offline), list apps, read the app version and launch activity, read display density, and read or set `font_scale` for the 200% text check. | `AndroidDeviceService` |
| `Services/ProcessRunner.swift` | 101 | Runs an external command with a timeout (default 60 s) and captures its output. A non-zero exit is returned, not thrown, so callers word their own errors. Also moves blocking work off the main thread. | `ProcessRunner` |
| `Appium/AppiumClient.swift` | 1788 | The WebDriver/Appium HTTP client. Creates and deletes sessions, reads the hierarchy, screenshot and orientation, taps, scrolls, drags, goes back, sends Tab and arrow keys, drives VoiceOver, toggles Full Keyboard Access, and launches or stops the app. Retries temporary failures. | `AppiumClient`, `AppiumError`, `RememberedSessions` |
| `Appium/AccessibilitySourceParser.swift` | 14 | One protocol so either platform's XML parses into an `AccessibilityNode` tree. | `AccessibilitySourceParser` |
| `Appium/WDAElementParser.swift` | 347 | Parses iOS (WebDriverAgent) XML: type, name, label, value, traits, frame, enabled, visible, hittable and custom actions. Drops the Appium wrapper and scroll bars; gives a generic "Other" element a role from its traits. | `WDAElementParser` |
| `Appium/AndroidElementParser.swift` | 526 | Parses Android (UiAutomator2) XML. Skips system UI and the keyboard, converts pixels to dp, builds labels from `content-desc`, text or child text, and infers a role for clickable plain views (React Native, Flutter, Compose). | `AndroidElementParser` |

**iOS vs Android in this layer.**

- **iOS** uses XCUITest. A physical iPhone needs a signing team so WebDriverAgent can be built. Each iPhone gets its own WebDriverAgent port.
- **Android** uses UiAutomator2 with the app's package and activity. Font size and density are read and set through `adb`.

## Core model, engine and BB mapping

The core turns either platform's elements into one tree, runs the rules over it, and maps each result to a BB ID. The rules themselves and the on-device probes are in the next section.

### How a result becomes a BB ID

1. A parser builds an `AccessibilityNode` tree, and `annotatingLayout()` adds layout facts that depend on parent elements.
2. `AccessibilityScanner.evaluateForReport` runs every rule in `AccessibilityRules.all`. Node rules run on each element; screen rules run once on the root.
3. Each rule returns nothing (not applicable) or an `AccessibilityRuleEvaluation` with status pass, fail, validate or notTested. A warning is stored as validate.
4. Checks that need the device add their own results, or replace a notTested placeholder through `settled(as:message:)`. These are the probes, the testers and the iOS build inspectors.
5. `BBIssueCatalog.issue(for:)` picks the BB ID for the platform. It uses the rule ID, the outcome, and sometimes the role, Android widget kind, text size or message. `BBRuleset` supplies the title and WCAG. A notTested result never gets an ID.

### Element model

| File | Lines | What it does | Main types |
| --- | --- | --- | --- |
| `Core/AccessibilityNode.swift` | 206 | The shared element tree both parsers build: type, label, value, traits, frame, visibility flags, children and role. `annotatingLayout()` adds layout facts and drops the scanner's own `A11YScannerIgnore` elements. | `AccessibilityNode`, `PlatformSemantics` (hint, live region, error text, input type, real text size, pane title, custom actions, inferred role) |
| `Core/AccessibilityRole.swift` | 109 | Turns a platform class name into one role, so rules are written once. iOS matches exact `XCUIElementType*` names; Android matches class-name endings (EditText → text field, RecyclerView → table). | `AccessibilityRole` (22 roles), role groups |
| `Core/MobilePlatform.swift` | 32 | The iOS/Android enum, its size unit (pt or dp), and detection from an element type. | `MobilePlatform` |
| `Core/Device.swift` | 60 | A device or simulator in the device picker. | `Device` |

### Rule engine and results

| File | Lines | What it does | Main types |
| --- | --- | --- | --- |
| `Core/AccessibilityRule.swift` | 37 | The rule protocols: node rules, screen rules, and screen rules that also get the screenshot. | `AccessibilityRule`, `ScreenAccessibilityRule`, `ContextualScreenAccessibilityRule` |
| `Core/AccessibilityScanner.swift` | 181 | The rule engine. Walks the tree, runs node rules on every element and screen rules on the root, using screenshot-aware variants when a screenshot is given. | `AccessibilityScanner` |
| `Core/AccessibilityRuleEvaluation.swift` | 92 | One rule result for one element, with the element's details copied in. The main record behind every report. | `AccessibilityRuleEvaluation` |
| `Core/AccessibilityFinding.swift` | 80 | A simpler record of fail and warning results, used for the main window's findings list. Also defines the error, warning and info severity used everywhere. | `AccessibilityFinding` |
| `Core/AccessibilityRuleCatalog.swift` | 232 | Metadata per rule: WCAG criterion, level, impact, affected users and manual test steps. Also lists rules that cannot run automatically or only ask for review. | `AccessibilityRuleCatalog`, `AccessibilityRuleMetadata` |
| `Core/AccessibilityFixCenter.swift` | 408 | The Developer Fix Center: groups failing rules, ranks them by priority, and attaches fix guidance with SwiftUI/UIKit or Compose/Android View code samples. Includes its view. | `AccessibilityFixCenter`, `AccessibilityFixGuidance`, `AccessibilityFixCenterView` |

### BB sheet mapping

| File | Lines | What it does | Main types |
| --- | --- | --- | --- |
| `Core/BBRuleset.swift` | 471 | The iOS and Android BB sheets as data (about 410 rows). Each row has ID, element, issue, type, WCAG, level, severity, what the scanner can do per platform, and a note. Regenerate it from the sheet CSVs rather than editing by hand. | `BBRuleset`, `BBRule`, `BBCapability`, `BBRuleType` |
| `Core/BBIssueCatalog.swift` | 524 | Maps each result to a BB ID, with separate tables for iOS and Android, because the same ID means different issues on each sheet. Also gives the "Fail if confirmed" code for Validate results. | `BBIssueCatalog`, `BBIssue` |

### Helpers and iOS build inspectors

| File | Lines | What it does | Main types |
| --- | --- | --- | --- |
| `Core/ActionSafety.swift` | 159 | Decides which controls the crawler and probes may tap, using word lists for irreversible actions (delete, buy, sign out) and safe dismiss buttons. Also restores device changes when a scan stops, and recovers the Android font scale after a crash. | `ActionSafety`, `DeviceRestore`, `AndroidFontScaleRecovery` |
| `Core/TextSizeEstimate.swift` | 66 | Classes text as standard, possibly large or large (18 pt, or 14 pt bold) for contrast thresholds. Uses the real size on Android, an estimate from the frame on iOS. | `TextSizeEstimate`, `TextSizeClass` |
| `Core/VisualOrder.swift` | 72 | Checks whether a list of frames follows reading order (top to bottom, left to right). At least 90% in order passes. | `VisualOrder` |
| `Core/MotionHandlerInspector.swift` | 194 | iOS only. Finds the app's newest build on the Mac and reads its symbols with `xcrun nm` for shake handlers and motion APIs. Settles the motion-alternative result per screen. | `MotionHandlerInspector` |
| `Core/AppLanguageInspector.swift` | 114 | iOS only. Reads the build's declared language and localisations, detects each screen's language, and settles the language results. | `AppLanguageInspector` |
| `Core/ScannerBuildInfo.swift` | 32 | Scanner version, ruleset version and WCAG version, stamped on reports. | `ScannerBuildInfo` |
| `Core/Log.swift` | 26 | System logging with categories (appium, crawler, probes, scan, devices, reports). View in Console.app. | `Log`, `trace` |

## Crawling

The crawler explores the app depth-first. It scans each screen at every scroll position, runs the runtime and guided checks, then taps safe controls to reach new screens and comes back.

| File | Lines | What it does | Main types |
| --- | --- | --- | --- |
| `Core/Crawling/AppCrawler.swift` | 2186 | The crawl engine. Visits screens, scans every viewport and carousel, runs keyboard, runtime, shake, screen reader and row-tap checks, picks safe actions, and navigates back. Returns one `CrawledScreen` per unique screen. | `AppCrawler`, `AppCrawlerConfiguration`, `CrawledScreen`, `ScrollableViewportCapture`, `RowTaps` |
| `Core/Crawling/NavigationAction.swift` | 144 | One tappable candidate built from a node, and the XPath used to tap it. iOS uses `@name`, then `@label`; Android uses `@resource-id`, then `@content-desc` or `@text`. Quotes are escaped with `concat()`. | `NavigationAction` |
| `Core/Crawling/NavigationTransition.swift` | 61 | One edge of the app map: source screen, target screen and the action tapped. Saved in the report and drawn in the App Map. | `NavigationTransition` |
| `Core/Crawling/ScreenSignature.swift` | 115 | A structural hash of a hierarchy. Used to tell when a screen has settled and when scrolling has reached the bottom. Not used to tell screens apart. | `ScreenSignature` |

### How the crawl works

1. **Limits.** Stop at 100 screens or depth 20, and skip a screen already visited. A screen counts as visited if its content fingerprint matches, or at least 60% of its labels overlap a known screen.
2. **Scan every viewport.** Scroll to the top, then up to 20 times: run the rules, keep the capture if the screenshot is new, swipe up to 3 carousels sideways, and scroll down. Stop when the hierarchy or screenshot stops changing, then scroll back to the top.
3. **Stable snapshots.** Read the hierarchy, take a screenshot, read again, and compare signatures. Try up to 3 times; an unsettled screen is noted in the report.
4. **Per-screen checks.** Keyboard focus, then the runtime probes, the shake check and the screen reader order test. The 200% text check runs only on the first screen and screens up to 2 taps deep. In Current Page mode the probes are marked Not tested.
5. **Row taps (BB40282).** For up to 3 kinds of row with no role, tap one safe row. If it opened something, the row needs a role (Fail). If nothing changed, the Validate is dropped.
6. **Pick actions.** Visible, enabled buttons, links and cells with a label or identifier that `ActionSafety` allows. Back buttons are excluded, duplicates dropped, at most 30 per screen.
7. **Explore.** Tap each action and wait. If another app came to the front, switch back. If a new screen appeared, record the transition and recurse. Tab bars and bottom navigation are explored once per crawl.
8. **Go back.** After a tab, return through the tab bar. Otherwise try in order: Back, a Close/Done/Cancel button near the top, swiping a sheet down (iOS), then the tab bar. If none works, the crawl notes it is lost and the parent level recovers.

## Rules, probes and testers

There are 79 rules. Most judge the hierarchy or the screenshot. The rest only reserve a place for a result that a probe, a tester or a build inspector supplies on the device.

| File | Lines | What it does | Main types |
| --- | --- | --- | --- |
| `Core/Rules/AccessibilityRules.swift` | 2694 | Every rule, the list `AccessibilityRules.all`, the screenshot context passed to screenshot-aware rules, and `RuleHelper` for building pass, fail, validate and not-tested results. | one struct per rule, `AccessibilityRuleContext`, `RuleHelper` |
| `Core/PixelAnalysis.swift` | 518 | Reads colours and contrast from screenshots, and text with Vision OCR. Used by the contrast, link-colour, label-in-name and truncation checks. | `PixelAnalyzer`, `PixelSampler`, `PixelColor`, `TextRecognizer` |
| `Core/RuntimeProbes.swift` | 1004 | Probes that act on the device: rotation, 200% text, toggle state updates and pointer cancellation. Also shared helpers for finding and comparing elements. | `OrientationProbe`, `TextSizeProbe`, `StateUpdateProbe`, `PointerCancellationProbe`, `ProbeNodes` |
| `Core/KeyboardAndFormProbes.swift` | 562 | Keyboard activation (Space/Enter on focused controls) and form error messages (submit an empty form, read the errors). | `KeyboardActivationProbe`, `ErrorMessageProbe`, `ErrorMessageHeuristics` |
| `Core/KeyboardFocusTester.swift` | 1247 | Tabs through each screen and records focus. Produces the keyboard focus, focus order, focus indicator, trap, hidden-focus, context-change and modal results. | `KeyboardFocusTester` |
| `Core/ScreenReaderOrderTester.swift` | 254 | Checks VoiceOver or TalkBack reading order against visual order. | `ScreenReaderOrderTester` |

### What runs on the device

| Probe or tester | What it does | Automatic or guided |
| --- | --- | --- |
| `OrientationProbe` | Rotates the screen, compares content with the original, rotates back. A refused rotation or a locked screen fails; missing content asks for review. | Automatic |
| `TextSizeProbe` | Relaunches at the largest text (iOS) or font scale 2.0 (Android), replays the route to the screen, closes a launch alert, and checks resize, clipping, truncation and overlap. Restores the setting afterwards. | Automatic |
| `StateUpdateProbe` | Taps up to 3 safe toggles or checkboxes, checks the state changed, then restores them. | Automatic |
| `PointerCancellationProbe` | Presses a safe button and slides off before releasing, then checks nothing happened. | Automatic |
| `KeyboardActivationProbe` | Tabs to up to 3 safe buttons or links and presses Space/Enter. | Android automatic; iOS automatic, or guided if Appium keys do not reach Full Keyboard Access |
| `ErrorMessageProbe` | Taps a safe submit-type button on an empty form and checks that the errors appear and explain the fix. | Automatic |
| `KeyboardFocusTester` | Presses Tab through every control and records the focus order. | Android automatic; iOS automatic via screenshots, or guided if Tab does not move focus |
| `ScreenReaderOrderTester` | iOS drives VoiceOver through Appium where it can; otherwise the tester swipes and the scanner follows the cursor. | iOS automatic or guided; Android (TalkBack) always guided |
| Shake check (in `AppCrawler`) | Asks the tester to shake the phone, or shakes the simulator, and watches what opens. | Guided on a real phone |

### Rules by theme

Rule IDs are the join key: `BBIssueCatalog` and the Fix Center look results up by them.

| Theme | Rule IDs | How it is checked |
| --- | --- | --- |
| Names and labels | `accessible-name`, `button-name-descriptive`, `image-button-name`, `interactive-name-descriptive`, `placeholder-only-name`, `name-via-hint`, `label-in-name`, `duplicate-interactive-name` | Hierarchy; `label-in-name` also uses OCR |
| Images | `image-accessible-label`, `image-name-descriptive`, `decorative-image`, `map-text-alternative` | Hierarchy (decorative and map ask for review) |
| Roles and traits | `role-trait-consistency`, `text-link-role`, `text-button-role`, `missing-role`, `icon-control-role`, `row-role`, `tab-accessibility`, `segmented-control-interactive`, `adjustable-accessibility-value`, `button-disabled-state` | Hierarchy; `row-role` is confirmed by the crawler's row taps |
| Contrast | `contrast-standard-text-4-5`, `contrast-large-text-3`, `contrast-text-over-image`, `contrast-opacity`, `non-text-contrast`, `form-border-contrast`, `loading-indicator-contrast`, `link-color-differentiation` | Screenshot pixels (`contrast-opacity` never reports: no platform exposes opacity) |
| Target size | `touch-target-size-24` | Hierarchy frames, with the spacing exception |
| Text size at 200% | `text-resize`, `text-clipping`, `text-truncation`, `text-overlap` | `TextSizeProbe` |
| Headings, titles, structure | `heading-quality`, `heading-candidate`, `screen-title`, `reading-order`, `screen-reader-content` | Hierarchy; `reading-order` also from `ScreenReaderOrderTester` |
| Forms and errors | `form-visual-label`, `form-autocomplete`, `error-message-accessibility`, `error-message-suggestion`, `live-region` | Hierarchy and `ErrorMessageProbe` (autocomplete and live region need Android data) |
| Keyboard | `keyboard-focus`, `keyboard-activation`, `focus-order`, `focus-indicator`, `focus-indicator-contrast`, `focus-indicator-color-only`, `focus-not-obscured`, `keyboard-focus-hidden-content`, `keyboard-focus-noninteractive`, `keyboard-focus-context-change`, `modal-focus-containment` | `KeyboardFocusTester` and `KeyboardActivationProbe` |
| Screen reader | `screen-reader-focus-order`, `interactive-screen-reader-hidden`, `modal-accessibility`, `modal-closable` | Hierarchy and `ScreenReaderOrderTester` |
| Interaction | `state-updates-after-interaction`, `touch-up-cancellation`, `orientation-support`, `motion-alternative`, `complex-gesture-alternative`, `gesture-keyboard-operable` | Probes; motion from the shake check and the iOS build |
| Language | `language`, `content-language`, `language-change` | iOS build plus on-screen language detection |
| Placeholders only | `multi-point-gesture-alternative`, `path-based-gesture-alternative`, `accessibility-interface-operable`, `screen-reader-modal-focus`, `screen-reader-trap`, `screen-reader-focus-context-change`, `cancel-undo-mechanism`, `input-context-change`, `time-limited-ui`, `text-spacing` | Always Not tested: a manual check |

## Reports

These files turn crawled screens into the final report. They also check that the report is consistent, and export it as one JSON file and one self-contained HTML file.

| File | Lines | What it does | Main types |
| --- | --- | --- | --- |
| `Reports/ScreenResultBuilder.swift` | 336 | Turns one crawled screen into a screen result. Re-runs the rules per viewport with the screenshot (for contrast), merges results, drops elements already seen higher up the page, applies row-tap verdicts, and builds annotated images. | `ScreenResultBuilder` |
| `Reports/AccessibilityScanResult.swift` | 178 | The top-level saved model of one scan: app, device, times, screens, environment, notes, totals and per-rule summaries. | `AccessibilityScanResult` |
| `Reports/ScreenScanResult.swift` | 87 | The saved result for one screen: name, signature, evaluations, transitions, screenshots and annotations. | `ScreenScanResult` |
| `Reports/RuleResultStatus.swift` | 31 | The result statuses used everywhere: pass, fail, warning, validate, notTested. | `RuleResultStatus` |
| `Reports/RuleSummary.swift` | 61 | Per-rule counts of each status. | `RuleSummary` |
| `Reports/ScanEnvironment.swift` | 86 | Device, OS, app and scanner versions stored on the report, and the scan notes (tap failed, left app, lost navigation, unstable screen, launch failed). | `ScanEnvironment`, `ScanNotes` |
| `Reports/ScanScreenshot.swift` | 59 | Screenshot containers: original and annotated images, and one entry per scroll position. | `ScanScreenshot`, `ScreenshotViewport` |
| `Reports/ScreenNaming.swift` | 80 | Names screens the way the app does: Android pane title, navigation bar title, top heading, selected tab, else "Screen N". Repeated names get a number. | `ScreenNaming` |
| `Reports/ScreenshotAnnotation.swift` | 269 | One numbered marker for a result on a screenshot, with its BB ID and title, in top-to-bottom reading order. | `ScreenshotAnnotation`, `ScreenshotCheckFilter` |
| `Reports/ScreenshotAnnotator.swift` | 514 | Draws boxes and numbered markers on the screenshot (red error, orange warning, blue info), scaling points or dp to pixels. | `ScreenshotAnnotator` |
| `Reports/ReportImageEncoder.swift` | 74 | Shrinks screenshots to JPEG (default 900 px, quality 0.78) for storage and export, falling back to the original bytes. | `ReportImageEncoder` |
| `Reports/FindingGrouping.swift` | 254 | Removes duplicate findings across screens and viewports, groups them by rule, status and BB issue, and gives each a stable fingerprint. | `FindingGrouping`, `GroupedFinding` |
| `Reports/BBReport.swift` | 207 | The report as the BB sheet sees it: grouped by BB code and status, then by the sheet's Element category. Validate results that would be a Fail once confirmed are grouped separately. | `BBReport` |
| `Reports/BBCoverage.swift` | 174 | Accounts for every BB ID on the platform's sheet: found, passed, review, covered by a sibling, nothing applicable, not tested, manual, unavailable, on hold or out of scope (AAA). | `BBCoverage`, `BBCoverageEntry` |
| `Reports/ReportCoverage.swift` | 397 | Rule-level and WCAG 2.2 A/AA coverage matrix: which criteria got an automated verdict, manual review only, or nothing to test. | `ReportCoverage`, `WCAGReference` |
| `Reports/AccessibilityReportIntegrity.swift` | 121 | Self-checks before the report is shown: totals match screens, no duplicate IDs, no negative counts, sensible times. Also adds notes for contradictions such as a rule passing and failing one element. | `AccessibilityReportIntegrity` |
| `Reports/JSONReportExporter.swift` | 529 | Writes the JSON report (schema 1.8): generator versions, scan metadata, summary, findings, screens, rules, WCAG coverage and BB coverage. | `JSONReportExporter` |
| `Reports/HTMLReportExporter.swift` | 742 | Writes one self-contained HTML report: verdict, summary, BB report, WCAG coverage, screens with filterable screenshot boxes, scope and limitations, and a rule appendix. | `HTMLReportExporter` |
| `Reports/TesterFindingGuidance.swift` | 20 | Gives a result a readable target name: label, else identifier, else role. | extension on `AccessibilityRuleEvaluation` |

Both exports are written to the Mac's temporary folder as `<App>_AccessibilityReport_<UTC date-time>.json` or `.html`, from the Export menu.

## Tests and other files

The tests use Swift Testing (`@Suite`, `@Test`) and are built from real scan hierarchies, not made-up apps. Run them with Cmd-U in Xcode, or:

```bash
xcodebuild test -scheme AccessibilityScanner -destination 'platform=macOS'
```

| File | Lines | What it tests |
| --- | --- | --- |
| `AccessibilityScannerTests/TestSupport.swift` | 55 | Shared helpers: `makeNode` builds an element, `makeEvaluation` builds a result. |
| `AccessibilityScannerTests/BBCoverageReport.swift` | 188 | That every code the scanner produces exists in the BB sheet, every Automated or Runtime row is actually produced, and a result's status matches the sheet's type (Fail, Validate, Pass). Runs for iOS and Android. Set `BB_COVERAGE_OUT=<path>` to write the produced map. |
| `AccessibilityScannerTests/BBIssueCatalogTests.swift` | 95 | How results map to specific BB codes: missing vs generic names, keyboard activation by role, large-text contrast codes, orientation, placeholder-only fields, and that Not tested never maps. |
| `AccessibilityScannerTests/PlatformSemanticsTests.swift` | 345 | Android and iOS parsing (Android attributes, iOS custom actions, scroll bars ignored, launch alert closed with OK), rule heuristics (text that grows only wider, label-in-name, carousel clipping) and report building (BB coverage, BB report grouping, HTML filters). |
| `AccessibilityScannerTests/ScannerLogicTests.swift` | 555 | Text size estimates, action safety, scan notes, Appium URL validation, process runner timeouts, result merging, device JSON parsing, screen signatures, target size and overlap, duplicate names, segmented controls, reading order, screen naming and shake-handler detection. |

| Other file | What it is |
| --- | --- |
| `ANDROID_SUPPORT.md` | Android setup (adb, UiAutomator2 driver), known limits, first-run checklist and React Native / Flutter notes. |
| `Docs/iOS-ruleset-coverage.csv` | The iOS BB sheet with the scanner's coverage per row (216 rows). For people; the code does not read it. |
| `Docs/Android-ruleset-coverage.csv` | The same for Android (194 rows). |
| `Docs/TECHNICAL_DOCUMENTATION.md` | This document. |
| `.gitignore` | Ignores Xcode user state, DerivedData, build and .DS_Store. |
