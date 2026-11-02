//
//  RecapReminders.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


import Foundation
import UserNotifications

enum RecapReminders {
    static let identifierPrefix = "recapReminder."
    static let delay: TimeInterval = 30 * 60
    static let maximum = 20

    struct Reminder: Equatable {
        let identifier: String
        let title: String
        let fireDate: Date
    }

    static func plan(happs: [Happ], userID: String, now: Date = Date()) -> [Reminder] {
        happs
            .filter { $0.participantIDs.contains(userID) }
            .map { happ -> Reminder in
                let end = happ.endTime ?? happ.startTime.addingTimeInterval(Happ.defaultDuration)
                return Reminder(
                    identifier: identifierPrefix + happ.id,
                    title: happ.title,
                    fireDate: end.addingTimeInterval(delay)
                )
            }
            .filter { $0.fireDate > now.addingTimeInterval(5) }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(maximum)
            .map { $0 }
    }

    @MainActor
    static func sync(happs: [Happ], userID: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        await removeAll()
        for reminder in plan(happs: happs, userID: userID) where reminder.identifier != identifierPrefix {
            let content = UNMutableNotificationContent()
            content.title = "How was \(reminder.title)?"
            content.body = "Share your photos so friends can see what happened."
            content.sound = .default
            let interval = max(1, reminder.fireDate.timeIntervalSinceNow)
            let request = UNNotificationRequest(
                identifier: reminder.identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            )
            try? await center.add(request)
        }
    }

    @MainActor
    static func removeAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }
}