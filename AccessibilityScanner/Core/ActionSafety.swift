//
//  ActionSafety.swift
//  AccessibilityScanner


import Foundation

// MARK: - Which controls may be activated
enum ActionSafety {

    private static let irreversible: [String] = [
        // Deleting data
        "delete", "remove", "erase", "destroy", "trash", "discard", "clear", "reset", "wipe",
        "uninstall", "deactivate", "close account", "delete account",
        // Session
        "sign out", "signout", "log out", "logout",
        // Money
        "buy", "purchase", "pay", "payment", "checkout", "check out", "order", "place order",
        "transfer", "withdraw", "deposit", "donate", "tip", "upgrade", "subscribe", "unsubscribe",
        "cancel subscription", "book", "reserve",
        // Sending or publishing
        "send", "submit", "confirm", "post", "publish", "share", "invite", "reply", "comment",
        "call", "dial", "message", "email",
        // Consent and moderation
        "accept", "agree", "allow", "approve", "authorize", "authorise", "yes",
        "report", "block", "mute", "unfollow", "follow"
    ]

    private static let stateChanging: [String] = [
        "login", "log in", "sign in", "signin", "sign up", "signup", "register",
        "add to cart", "add to bag", "add to favourites", "add to favorites", "like",
        "bookmark", "favourite", "favorite", "star", "pin", "unpin",
        "save", "create", "update", "edit", "enable", "disable"
    ]

    private static let dismissLabels: [String] = [
        "cancel", "close", "dismiss", "not now", "later", "no", "no thanks",
        "don t allow", "dont allow", "deny", "ok", "got it"
    ]

    static func isIrreversible(_ node: AccessibilityNode) -> Bool {
        containsPhrase(words(of: node), irreversible)
    }

    static func isSafeToActivate(_ node: AccessibilityNode) -> Bool {
        !isIrreversible(node) && !isBackButton(node)
    }

    static func isSafeToExplore(_ node: AccessibilityNode) -> Bool {
        let tokens = words(of: node)
        return !containsPhrase(tokens, irreversible) && !containsPhrase(tokens, stateChanging) && !isBackButton(node)
    }

    static func isBackButton(_ node: AccessibilityNode) -> Bool {
        node.identifier == "BackButton" ||
            node.label.caseInsensitiveCompare("Navigate up") == .orderedSame
    }

    static func dismissButton(in buttons: [AccessibilityNode]) -> AccessibilityNode? {
        for label in dismissLabels {
            if let match = buttons.first(where: { wordsOfLabel($0) == label }) {
                return match
            }
        }
        return nil
    }

    // MARK: Matching

    /// Label and identifier as lowercase words; camelCase identifiers are split
    /// ("btnTrash" -> "btn trash") so icon buttons are caught too.
    private static func words(of node: AccessibilityNode) -> String {
        normalize(node.label + " " + splitCamelCase(node.identifier))
    }

    private static func wordsOfLabel(_ node: AccessibilityNode) -> String {
        normalize(node.label).trimmingCharacters(in: .whitespaces)
    }

    private static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let mapped = lowered.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
        }
        return String(mapped)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func splitCamelCase(_ text: String) -> String {
        var result = ""
        var previous: Character?
        for character in text {
            if let previous, previous.isLowercase, character.isUppercase {
                result.append(" ")
            }
            result.append(character)
            previous = character
        }
        return result
    }

    private static func containsPhrase(_ words: String, _ phrases: [String]) -> Bool {
        let padded = " \(words) "
        return phrases.contains { padded.contains(" \($0) ") }
    }
}

// MARK: - Cleanup that survives Stop

enum DeviceRestore {

    static func run(_ body: @escaping () async -> Void) async {
        await Task { await body() }.value
    }
}

// MARK: - Android font scale recovery

nonisolated enum AndroidFontScaleRecovery {

    private static let defaultsKey = "pendingAndroidFontScaleRestore"
    /// Stored for a device whose font scale was unset (system default).
    private static let unsetMarker = "__default__"

    private static var pending: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }


    static func remember(serial: String, original: String?) {
        var values = pending
        if values[serial] == nil {
            values[serial] = original ?? unsetMarker
        }
        pending = values
    }

    static func outstanding(serial: String) -> String?? {
        guard let value = pending[serial] else { return nil }
        return .some(value == unsetMarker ? nil : value)
    }

    static func markRestored(serial: String) {
        var values = pending
        values.removeValue(forKey: serial)
        pending = values
    }

    static func restoreOutstanding(using service: AndroidDeviceService = AndroidDeviceService()) {
        for (serial, value) in pending {
            let original = value == unsetMarker ? nil : value
            if (try? service.setFontScale(serial: serial, value: original)) != nil {
                markRestored(serial: serial)
            }
        }
    }
}
