//
//  AIConsent.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


//  CODE OVERVIEW
//  -------------
//  Pure helper for the user's consent to send text to the AI service. It is a caseless enum used as a namespace
//  (no instances), with static functions that take UserDefaults as a parameter so unit tests can pass a throwaway store.
//  Consent is saved as an Int version number under a key containing the user id. Comparing it to `currentVersion`
//  means a bumped version silently invalidates old consent. The consent sheet and the Describe it flow read
//  hasConsented before calling the AI service (assumed callers).
//  `nonisolated` lets it be called from any actor, not just the main actor.
//
import Foundation

/// Namespace for reading and writing AI consent. Stored locally per account, not in Firestore.
nonisolated enum AIConsent {
    /// Raise this when the disclosure wording or what is sent changes.
    static let currentVersion = 1

    /// UserDefaults key for one account, so two users on one device keep separate consent.
    static func key(for userID: String) -> String { "geminiConsentVersion.\(userID)" }

    /// True only if the stored version equals the current one. A missing key reads as 0, which never matches.
    static func hasConsented(userID: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: key(for: userID)) == currentVersion
    }

    /// Saves or withdraws consent. Withdrawing removes the key rather than storing false.
    static func setConsent(_ allowed: Bool, userID: String, defaults: UserDefaults = .standard) {
        if allowed {
            defaults.set(currentVersion, forKey: key(for: userID))
        } else {
            defaults.removeObject(forKey: key(for: userID))
        }
    }

    /// Shown in the consent sheet. Mirrors what HappIntentParser actually sends.
    // Bullet text for the disclosure screen.
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
