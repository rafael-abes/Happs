//
//  AIConsent.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


import Foundation

nonisolated enum AIConsent {
    /// Raise this when the disclosure wording or what is sent changes.
    static let currentVersion = 1

    static func key(for userID: String) -> String { "geminiConsentVersion.\(userID)" }

    static func hasConsented(userID: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: key(for: userID)) == currentVersion
    }

    static func setConsent(_ allowed: Bool, userID: String, defaults: UserDefaults = .standard) {
        if allowed {
            defaults.set(currentVersion, forKey: key(for: userID))
        } else {
            defaults.removeObject(forKey: key(for: userID))
        }
    }

    /// Shown in the consent sheet. Mirrors what HappIntentParser actually sends.
    static let whatIsSent = [
        "The sentence you type or dictate in Describe it",
        "Today's date, your time zone and the four category names, so dates like \"tomorrow\" are right"
    ]

    static let whatIsNotSent = [
        "Your name, email, photos or location",
        "Your friends or the names of your groups",
        "Anything from other screens"
    ]
}
