//
//  AccessibilityRole.swift
//  AccessibilityScanner
//
//  Platform-neutral element roles. Rules, the crawler and the report layers
//  work with roles instead of raw `XCUIElementType*` / Android class names.
//

import Foundation

enum AccessibilityRole: String, Codable, Hashable {

    case application
    case statusBar
    case navigationBar
    case tabBar
    case button
    case link
    case cell
    case textField
    case secureTextField
    case textView
    case staticText
    case image
    case toggle          // switch / toggle button
    case checkBox
    case radioButton
    case slider
    case stepper
    case picker
    case segmentedControl
    case table
    case scrollView
    case other

    // MARK: - Resolve from raw platform type

    static func resolve(type: String) -> AccessibilityRole {
        if type.hasPrefix("XCUIElementType") {
            return resolveIOS(type)
        }
        return resolveAndroid(type)
    }

    private static func resolveIOS(_ type: String) -> AccessibilityRole {
        switch type {
        case "XCUIElementTypeApplication": return .application
        case "XCUIElementTypeStatusBar": return .statusBar
        case "XCUIElementTypeNavigationBar": return .navigationBar
        case "XCUIElementTypeTabBar": return .tabBar
        case "XCUIElementTypeButton": return .button
        case "XCUIElementTypeLink": return .link
        case "XCUIElementTypeCell": return .cell
        case "XCUIElementTypeTextField": return .textField
        case "XCUIElementTypeSecureTextField": return .secureTextField
        case "XCUIElementTypeTextView": return .textView
        case "XCUIElementTypeStaticText": return .staticText
        case "XCUIElementTypeImage": return .image
        case "XCUIElementTypeSwitch": return .toggle
        case "XCUIElementTypeSlider": return .slider
        case "XCUIElementTypeStepper": return .stepper
        case "XCUIElementTypePickerWheel": return .picker
        case "XCUIElementTypeSegmentedControl": return .segmentedControl
        case "XCUIElementTypeTable", "XCUIElementTypeCollectionView": return .table
        case "XCUIElementTypeScrollView": return .scrollView
        default: return .other
        }
    }

    /// Android class names are matched on their simple name so AndroidX,
    /// Material and AppCompat variants resolve to the same role.
    private static func resolveAndroid(_ type: String) -> AccessibilityRole {
        if type == "hierarchy" { return .application }

        let simple = type.split(separator: ".").last.map(String.init) ?? type

        // Order matters: more specific names first.
        if simple.hasSuffix("ImageButton") || simple.contains("FloatingActionButton") { return .button }
        if simple.hasSuffix("RadioButton") { return .radioButton }
        if simple.hasSuffix("ToggleButton") || simple.contains("Switch") { return .toggle }
        if simple.hasSuffix("CheckBox") || simple == "CheckedTextView" { return .checkBox }
        if simple.hasSuffix("Button") || simple.hasSuffix("Chip") { return .button }
        if simple.hasSuffix("EditText") || simple.contains("AutoCompleteTextView")
            || simple == "SearchAutoComplete" { return .textField }
        if simple.hasSuffix("SeekBar") || simple.hasSuffix("RatingBar") || simple.hasSuffix("Slider") { return .slider }
        if simple.hasSuffix("Spinner") || simple.hasSuffix("NumberPicker") { return .picker }
        if simple.hasSuffix("ImageView") { return .image }
        if simple.hasSuffix("TextView") { return .staticText }
        if simple.hasSuffix("Toolbar") || simple.hasSuffix("ActionBar") || simple == "ActionBarContextView" { return .navigationBar }
        if simple.hasSuffix("TabLayout") || simple.hasSuffix("TabWidget")
            || simple.hasSuffix("BottomNavigationView") || simple.hasSuffix("NavigationBarView") { return .tabBar }
        if simple.hasSuffix("ListView") || simple.hasSuffix("RecyclerView")
            || simple.hasSuffix("GridView") { return .table }
        if simple.hasSuffix("ScrollView") || simple.hasSuffix("ViewPager") || simple.hasSuffix("ViewPager2") { return .scrollView }

        return .other
    }

    // MARK: - Role groups used by rules

    /// Roles that are expected to be operable controls.
    static let controls: Set<AccessibilityRole> = [
        .button, .textField, .secureTextField, .slider, .toggle,
        .stepper, .picker, .segmentedControl, .checkBox, .radioButton
    ]

    static let textInputs: Set<AccessibilityRole> = [
        .textField, .secureTextField, .textView
    ]

    static let textual: Set<AccessibilityRole> = [
        .staticText, .textView, .textField, .secureTextField
    ]
}
