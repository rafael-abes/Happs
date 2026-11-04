//
//  AppNotification.swift
//  Happs
//
//  Created by Rafa Abes on 10/11/26.
//

//  CODE OVERVIEW
//  -------------
//  Data model for one in-app notification. Notifications are Firestore documents (not push), written
//  by NotificationWriter and read live by NotificationStore, which shows them in the Notifications
//  screen and the unread badge. The model is Codable so FirebaseFirestore can encode and decode it
//  directly. NotificationKind decides the icon and whether the row is styled as a negative event.
//
import Foundation
import FirebaseFirestore

/// What happened. The raw String value is what is stored in Firestore, so renaming a case would break
/// existing documents.
enum NotificationKind: String, Codable {
    case friendRequest
    case groupInvite
    case groupJoined
    case groupDeclined
    case groupLeft
    case groupDeleted
    case happCreated
    case happJoined
    case happLeft
    case happUpdated
    case happCancelled
    case recapPosted
    case recapMissed

    /// SF Symbol shown beside the notification. Uses the newer implicit-return switch expression.
    var symbolName: String {
        switch self {
        case .friendRequest: "person.badge.plus"
        case .groupInvite, .groupJoined, .groupDeclined, .groupLeft: "person.3.fill"
        case .groupDeleted: "person.crop.circle.badge.minus"
        case .happCreated: "sparkles"
        case .happJoined: "person.crop.circle.badge.checkmark"
        case .happLeft: "person.crop.circle.badge.xmark"
        case .happUpdated: "pencil.circle.fill"
        case .happCancelled: "xmark.circle.fill"
        case .recapPosted, .recapMissed: "photo.on.rectangle.angled"
        }
    }

    /// True for events the user may find unwelcome (declined, left, deleted, cancelled), so the UI can style them differently.
    var isNegative: Bool {
        switch self {
        case .groupDeclined,
             .groupLeft,
             .groupDeleted,
             .happLeft,
             .happCancelled:
            true

        default:
            false
        }
    }

}

/// One notification addressed to a single user (recipientID) and caused by another (actorID).
struct AppNotification: Codable, Identifiable {
    /// Firestore collection name, kept in one place to avoid typos across files.
    static let collectionName = "notifications"

    /// Filled in by Firestore from the document ID when decoding; not stored as a field.
    @DocumentID private var documentID: String?
    /// User who should see this notification. Stores query on this field.
    let recipientID: String
    /// User whose action triggered it (used e.g. to hide notifications from blocked people).
    let actorID: String
    let kind: NotificationKind
    let title: String
    let body: String
    /// Mutable so it can be flipped when the user opens the notification.
    var isRead: Bool
    /// @ServerTimestamp lets the server set the time on write, avoiding clock differences between devices. Nil until saved.
    @ServerTimestamp var createdAt: Date?

    /// Identifiable conformance for SwiftUI lists. The document ID is private, so expose it here.
    var id: String { documentID ?? "" }
}
