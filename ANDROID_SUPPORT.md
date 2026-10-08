# Android support

The scanner now drives Android devices/emulators through Appium's UiAutomator2
driver, alongside the existing iOS (XCUITest / WebDriverAgent) path.

## Setup (macOS host)
1. Install Android platform-tools (adb) and set `ANDROID_HOME`
   (default Android Studio path `~/Library/Android/sdk` is also detected).
2. `npm i -g appium` then `appium driver install uiautomator2`
3. Start an emulator or connect a device with USB debugging enabled
   (`adb devices` must list it as `device`).
4. Start Appium (`appium`), launch the scanner, pick the Android device and a
   third-party app, then Start Scan.

## What changed
| Area | Change |
|---|---|
| `Core/MobilePlatform.swift` (new) | iOS/Android enum, target sizes (44pt / 48dp), unit names |
| `Core/AccessibilityRole.swift` (new) | Platform-neutral roles resolved from XCUI types and Android class names |
| `Core/AccessibilityNode.swift` | `platform`, `roleOverride`, `role`; helpers are role based |
| `Appium/AndroidElementParser.swift` (new) | UiAutomator2 XML -> `AccessibilityNode` (px -> dp, TalkBack-style names) |
| `Appium/AccessibilitySourceParser.swift` (new) | Parser protocol for WDA and Android |
| `Appium/AppiumClient.swift` | Per-platform capabilities, density detection, tap scaling, Android scroll, `makeParser()` |
| `Services/AndroidDeviceService.swift` (new) | adb device, density, app and launcher-activity discovery |
| `Core/Rules/AccessibilityRules.swift` | Rules use roles; platform aware target size; Android-safe adjustable rule |
| `Core/Crawling/*` | Role based filtering; Android xpath (`resource-id`, `content-desc`/`text`) |
| `Core/AccessibilityFixCenter.swift` | Android guidance (Compose and Views/Kotlin) |
| `Configuration/ScannerConfiguration.swift` | platform, activity, density, signing IDs now configurable |

## Known limitations
- Not compiled or run against a device in the environment this was written in.
  Build in Xcode and run the checklist below.
- Rule IDs/titles keep the "44pt" wording; messages use 48dp on Android.
- UiAutomator2 does not expose range info, heading flags, live regions or
  labelFor, so those rules report VALIDATE (manual TalkBack check) or are skipped.
- Rows in a RecyclerView share a `resource-id`, so the crawler taps the first
  match. Rows without an id/text cannot be navigated.
- App discovery lists third-party packages only, and shows the package tail as
  the name (no launcher labels without aapt).
- Contrast uses screenshots and works the same, but status bar/IME nodes
  (`com.android.systemui`, `inputmethod`) are excluded from the hierarchy.

## First-run checklist
1. Device appears in the picker as "... Android Emulator" / "Android (Connected)".
2. Console prints `Android display scale: <n>` (e.g. 2.625). If it prints the
   warning instead, frames are still in pixels and size rules will be wrong.
3. A scan of a screen with a 24dp icon button reports a target-size failure.
4. Tap/scroll during the crawl move the app (checks scale and scrollGesture).

## Flutter and React Native support

The scanner is black-box and does not require the Flutter or React Native
source project. It scans the native accessibility semantics exposed to Appium.

### Flutter
- Flutter's Android Semantics tree is exposed through Android accessibility
  nodes, which UiAutomator2 can read.
- Semantic identifiers can appear as Android `resource-id` values.
- Generic `android.view.View` semantics are interpreted using accessibility
  state such as clickable, checkable, focusable and content description.
- Keyboard-focus testing includes focusable semantic nodes, not only native
  Android Button/EditText classes.

### React Native
- React Native accessibility properties are consumed from the native Android
  and iOS accessibility hierarchy.
- Android `roleDescription` values exposed through `AccessibilityNodeInfo`
  extras are read when available.
- Generic accessible/focusable React Native views can participate in keyboard
  focus testing even when their native class is not a Button/EditText.
- iOS generic accessibility elements can recover button/link/adjustable roles
  from their accessibility traits when XCUITest reports a generic element type.

### Keyboard focus
The scanner performs runtime Tab navigation through the Appium session and
reads the platform-reported focused element. This is evidence-based:
PASS means the control was reached, FAIL means it was not reached, and
VALIDATE is used when the platform/session cannot expose reliable focus data.
