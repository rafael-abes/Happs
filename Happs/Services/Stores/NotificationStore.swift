//
//  NotificationStore.swift
//  Happs
//
//  Created by Rafa Abes on 10/11/26.
//

import Foundation
import FirebaseFirestore
import UserNotifications
import Combine

@MainActor
final class NotificationStore: ObservableObject {
    @Published private(set) var notifications: [AppNotification] = []
    
    var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }
    
    private let database: Firestore
    private var listener: ListenerRegistration?
    private var liveSince = Date()
    private var deliveredIDs: Set<String> = []
    
    init(database: Firestore = .firestore()) {
        self.database = database
    }
    
    func requestPermission() {
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        }
    }
    
    func startListening(for userID: String) {
        guard listener == nil else { return }
        liveSince = Date().addingTimeInterval(-10)
        
        listener = database.collection(AppNotification.collectionName)
            .whereField("recipientID", isEqualTo: userID)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self, let snapshot else { return }
                    self.handle(snapshot)
                }
            }
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
        notifications = []
        deliveredIDs = []
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
    }
    
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
    
    func markAllRead() async {
        let unread = notifications.filter { !$0.isRead }
        guard !unread.isEmpty else { return }
        
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
    
    private func handle(_ snapshot: QuerySnapshot) {
        notifications = snapshot.documents
            .compactMap { try? $0.data(as: AppNotification.self) }
            .sorted { ($0.createdAt ?? .now) > ($1.createdAt ?? .now) }
        
        // Only notifications created after this session started raise an alert.
        // Older unread ones were missed while the app was closed, so they wait
        // in the inbox instead of firing a stale banner.
        for change in snapshot.documentChanges where change.type == .added {
            guard let item = try? change.document.data(as: AppNotification.self),
                  !item.isRead,
                  let created = item.createdAt,
                  created >= liveSince,
                  deliveredIDs.insert(item.id).inserted else { continue }
            deliver(item)
        }
        
        let count = unreadCount
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
    }
    
    private func deliver(_ item: AppNotification) {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: item.id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }
}
