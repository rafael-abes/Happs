//
//  AIUsageLimiter.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
import Foundation

/// Local per-day cap on assistant calls. Stops a bug or a curious user burning the free quota.
/// Stored in UserDefaults under a local-day key, so it resets at local midnight.
struct AIUsageLimiter {
    static let defaultCap = 30

    private let defaults: UserDefaults
    private let cap: Int
    private let now: () -> Date
    private let dayKey = "ai.usage.day"
    private let countKey = "ai.usage.count"

    init(defaults: UserDefaults = .standard, cap: Int = AIUsageLimiter.defaultCap, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.cap = cap
        self.now = now
    }

    var used: Int {
        guard defaults.string(forKey: dayKey) == today else { return 0 }
        return defaults.integer(forKey: countKey)
    }

    var remaining: Int { max(0, cap - used) }
    var canUse: Bool { used < cap }

    func record() {
        let current = used
        defaults.set(today, forKey: dayKey)
        defaults.set(current + 1, forKey: countKey)
    }

    private var today: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now())
    }
}
