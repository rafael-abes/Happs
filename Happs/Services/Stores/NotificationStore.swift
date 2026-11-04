//
//  NotificationStore.swift
//  Happs
//
//  Created by Rafa Abes on 10/11/26.
//

//  CODE OVERVIEW
//  -------------
//  In-app notification inbox. It is an ObservableObject store (MVC model layer): views observe the
//  published list and badge count, and never talk to Firestore themselves. It is @MainActor so every
//  published change happens on the main thread.
//  A Firestore snapshot listener on the notifications collection (filtered by recipientID) keeps the
//  inbox live without polling. New documents also raise a local banner through UNUserNotificationCenter,
//  and the app icon badge is kept equal to the unread count.
//  The Firestore database is injected through init, with a default, so a different instance can be passed in.
//
import Foundation
import FirebaseFirestore
import UserNotifications
import Combine

/// Owns the signed-in user's notifications: listens to Firestore, exposes the filtered list,
/// marks items read, and raises local alerts for new ones. Created once and shared via the environment
/// (assumed: it is injected as an EnvironmentObject from the app root).
@MainActor
final class NotificationStore: ObservableObject {
    /// Every notification for this user, newest first, including ones from blocked people.
    /// private(set) so only this store can change it; views read `notifications` instead.
    @Published private(set) var allNotifications: [AppNotification] = []
    /// People the user has blocked. Set from ContentView.
    @Published var blockedIDs: Set<String> = []

    /// What the screens show: everything except blocked people.
    var notifications: [AppNotification] {
        allNotifications.filter { !blockedIDs.contains($0.actorID) }
    }

    /// Number of visible notifications not yet read. Also drives the app icon badge.
    var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    /// Injected so the store does not depend on a global; defaults to the shared Firestore instance.
    private let database: Firestore
    /// Handle for the live query. Kept so it can be removed on sign-out (otherwise it keeps firing).
    private var listener: ListenerRegistration?
    /// Cutoff time for banner alerts: only notifications created after this are announced.
    private var liveSince = Date()
    /// Notification ids already announced, so a repeat snapshot cannot fire the same banner twice.
    private var deliveredIDs: Set<String> = []

    /// - Parameter database: Firestore instance to use. Defaults to the app-wide one.
    init(database: Firestore = .firestore()) {
        self.database = database
    }

    /// Asks iOS for permission to show alerts, play sounds and set the badge.
    /// The result is ignored (`try?`): if the user says no, banners simply do not appear.
    func requestPermission() {
        // Task bridges this synchronous method to the async authorization API.
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    /// Starts the live query for this user's notifications. Safe to call twice: the guard stops a
    /// second listener being attached.
    func startListening(for userID: String) {
        guard listener == nil else { return }
        // Start 10 seconds in the past so a notification created right as the listener attaches is not
        // treated as old (assumed reason: allows for clock differences and listener start-up delay).
        liveSince = Date().addingTimeInterval(-10)

        // addSnapshotListener fires once with current data, then again on every change to the query.
        listener = database.collection(AppNotification.collectionName)
            .whereField("recipientID", isEqualTo: userID)
            // [weak self] avoids a retain cycle (the store owns the listener, the listener's closure would own the store).
            // The callback may not run on the main actor, so hop back with Task { @MainActor } before touching state.
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self, let snapshot else { return }
                    self.handle(snapshot)
                }
            }
    }

    /// Stops the listener and clears local state. Call on sign-out so the next user never sees this data.
    func stopListening() {
        listener?.remove()
        listener = nil
        allNotifications = []
        deliveredIDs = []
        // Reset the app icon badge. Fire and forget, errors ignored.
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
    }

    /// Marks one notification as read by updating its Firestore document.
    /// The snapshot listener then delivers the change, so the local list is not edited by hand.
    func markRead(_ item: AppNotification) async {
        guard !item.isRead else { return }
        do {
            try await database.collection(AppNotification.collectionName)
                .document(item.id)
                .updateData(["isRead": true])
        } catch {
            #if DEBUG
            print("markRead failed: \(error)")
            #endif
        }
    }

    /// Marks every visible unread notification as read in one atomic batch (one network round trip,
    /// all or nothing). Blocked people's items are skipped because `notifications` already excludes them.
    func markAllRead() async {
        let unread = notifications.filter { !$0.isRead }
        guard !unread.isEmpty else { return }

        // A WriteBatch groups the updates so they commit together.
        let batch = database.batch()
        for item in unread {
            batch.updateData(
                ["isRead": true],
                forDocument: database.collection(AppNotification.collectionName).document(item.id)
            )
        }
        do {
            try await batch.commit()
        } catch {
            #if DEBUG
            print("markAllRead failed: \(error)")
            #endif
        }
    }

    /// Called for every snapshot: rebuilds the list, announces genuinely new notifications, updates the badge.
    private func handle(_ snapshot: QuerySnapshot) {
        // Documents that fail to decode are dropped by compactMap rather than crashing the list.
        // A missing createdAt (server timestamp not resolved yet) sorts as now, so the item appears at the top.
        allNotifications = snapshot.documents
            .compactMap { try? $0.data(as: AppNotification.self) }
            .sorted { ($0.createdAt ?? .now) > ($1.createdAt ?? .now) }

        // Only notifications created after this session started raise an alert.
        // Older unread ones were missed while the app was closed, so they wait
        // in the inbox instead of firing a stale banner.
        // documentChanges contains only what changed since the last snapshot, so `.added` means new documents
        // (on the first snapshot it contains the existing ones too, which the liveSince check filters out).
        for change in snapshot.documentChanges where change.type == .added {
            guard let item = try? change.document.data(as: AppNotification.self),
                  !item.isRead,
                  let created = item.createdAt,
                  created >= liveSince,
                  !blockedIDs.contains(item.actorID),
                  // Set.insert returns `inserted == false` if the id was already there, so this also de-duplicates.
                  deliveredIDs.insert(item.id).inserted else { continue }
            deliver(item)
        }

        // The badge is set from the filtered unread count, so blocked senders never inflate it.
        let count = unreadCount
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
    }

    /// Schedules a local banner for one notification. Uses the notification id as the request id so a
    /// repeat for the same item replaces the earlier one.
    private func deliver(_ item: AppNotification) {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default

        // A 1 second time-interval trigger is used as a near-immediate delivery (assumed reason:
        // UNNotificationRequest needs a trigger and nil would not behave the same way for local alerts).
        let request = UNNotificationRequest(
            identifier: item.id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }
    /// Deletes one notification document.
    /// Deletes one notification. The Firestore rules already allow the recipient to delete,
        /// and the existing snapshot listener removes the row and updates the badge.
    func deleteNotification(_ item: AppNotification) async {
        let id: String? = item.id   // works whether id is String or String?
        guard let id else { return }
        do {
            // Uses Firestore.firestore() directly instead of the injected `database`; behaviour is the same
            // for the default instance.
            try await Firestore.firestore().collection("notifications").document(id).delete()
        } catch {
            #if DEBUG
            print("Delete notification failed: \(error)")
            #endif
        }
    }
}

