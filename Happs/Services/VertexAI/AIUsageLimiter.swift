//
//  AIUsageLimiter.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
//  CODE OVERVIEW
//  -------------
//  Small struct that limits how many assistant calls a device makes per day. It is a client-side guard only:
//  it protects the free quota and is not security, because the user could clear app data.
//  Day and count are stored in UserDefaults. The caller checks `canUse`, then calls `record()` after a use
//  (assumed order, the callers are in other files). UserDefaults and the clock are injected, so tests can use
//  a separate suite and a fixed date.
//
import Foundation

/// Local per-day cap on assistant calls. Stops a bug or a curious user burning the free quota.
/// Stored in UserDefaults under a local-day key, so it resets at local midnight.
struct AIUsageLimiter {
    /// Default maximum calls per day.
    static let defaultCap = 30

    /// Storage; injected so tests do not touch the real defaults.
    private let defaults: UserDefaults
    /// Daily cap.
    private let cap: Int
    /// Clock as a closure so tests can fake the date. @escaping because it is stored.
    private let now: () -> Date
    /// Keys for the stored day string and count.
    private let dayKey = "ai.usage.day"
    private let countKey = "ai.usage.count"

    /// - Parameters: defaults, cap and clock can all be replaced for testing.
    init(defaults: UserDefaults = .standard, cap: Int = AIUsageLimiter.defaultCap, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.cap = cap
        self.now = now
    }

    /// Calls used today. A stored day that is not today counts as zero, which is how the daily reset works with no timer.
    var used: Int {
        guard defaults.string(forKey: dayKey) == today else { return 0 }
        return defaults.integer(forKey: countKey)
    }

    /// Calls left today, never below zero.
    var remaining: Int { max(0, cap - used) }
    /// Whether another call is allowed.
    var canUse: Bool { used < cap }

    /// Counts one call. Writes today's date with it, so a new day starts a fresh count.
    /// A struct method that is not `mutating` because the state lives in UserDefaults, not in the struct.
    func record() {
        let current = used
        defaults.set(today, forKey: dayKey)
        defaults.set(current + 1, forKey: countKey)
    }

    /// Today's date in the user's time zone as yyyy-MM-dd. A fixed POSIX locale keeps the format stable on any device setting.
    private var today: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now())
    }
}
