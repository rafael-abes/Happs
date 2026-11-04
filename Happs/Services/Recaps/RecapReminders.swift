//
//  RecapReminders.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


// CODE OVERVIEW
// Schedules local notifications (UNUserNotificationCenter) that nudge a user to post photos after a
// Happ they joined has finished. It is split in two on purpose: plan(...) is a pure function that
// works out which reminders should exist (easy to test), and sync(...) is the side-effecting part
// that clears old requests and schedules the planned ones. Local notifications were chosen over
// push so no server or push entitlement is needed. It is called when the Happ list changes and
// the user signs in or out (see the header above for the rules).
//
import Foundation
import UserNotifications

/// Namespace for planning and scheduling post-Happ reminders.
enum RecapReminders {
    /// Prefix on every request id, so removeAll() deletes only our reminders and not other notifications.
    static let identifierPrefix = "recapReminder."
    /// Seconds after a Happ ends before the reminder fires (30 minutes).
    static let delay: TimeInterval = 30 * 60
    /// Cap on how many reminders are scheduled at once, well under the iOS limit of 64 pending.
    static let maximum = 20

    /// One planned reminder: a stable id (so it can be replaced), the Happ title and when it fires.
    struct Reminder: Equatable {
        let identifier: String
        let title: String
        let fireDate: Date
    }

    /// Pure planning step. Keeps Happs the user joined, computes end time plus delay, drops reminders
    /// already due, sorts soonest first and keeps at most `maximum`.
    /// `now` is a parameter (default current time) so tests can pass a fixed date.
    static func plan(happs: [Happ], userID: String, now: Date = Date()) -> [Reminder] {
        happs
            .filter { $0.participantIDs.contains(userID) }
            .map { happ -> Reminder in
                // If the Happ has no end time, assume a default duration after its start.
                let end = happ.endTime ?? happ.startTime.addingTimeInterval(Happ.defaultDuration)
                return Reminder(
                    identifier: identifierPrefix + happ.id,
                    title: happ.title,
                    fireDate: end.addingTimeInterval(delay)
                )
            }
            // Skip anything that is already past or fires within 5 seconds.
            .filter { $0.fireDate > now.addingTimeInterval(5) }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(maximum)
            // prefix returns an ArraySlice, so convert back to an Array to match the return type.
            .map { $0 }
    }

    /// Replaces all pending recap reminders with the freshly planned set. Does nothing if the user has
    /// not allowed notifications. Runs on the main actor (assumed reason: it uses the shared notification centre from UI-driven code).
    @MainActor
    static func sync(happs: [Happ], userID: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        // Do not schedule anything without permission (this app never prompts here).
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        // Clear first, then add: simpler than diffing, and it picks up edited or cancelled Happs.
        await removeAll()
        // The where clause skips a reminder whose id is just the prefix (an empty Happ id).
        for reminder in plan(happs: happs, userID: userID) where reminder.identifier != identifierPrefix {
            let content = UNMutableNotificationContent()
            content.title = "How was \(reminder.title)?"
            content.body = "Share your photos so friends can see what happened."
            content.sound = .default
            // A time interval trigger must be greater than 0, so clamp to at least 1 second.
            let interval = max(1, reminder.fireDate.timeIntervalSinceNow)
            let request = UNNotificationRequest(
                identifier: reminder.identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            )
            // A single failed schedule is ignored so the others still get added.
            try? await center.add(request)
        }
    }

    /// Cancels every pending reminder whose id starts with identifierPrefix. Used by sync, sign-out and account deletion.
    @MainActor
    static func removeAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }
}
