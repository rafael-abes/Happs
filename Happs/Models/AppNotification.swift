//
//  AppNotification.swift
//  Happs
//
//  Created by Rafa Abes on 10/11/26.
//

import Foundation
import FirebaseFirestore

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

struct AppNotification: Codable, Identifiable {
    static let collectionName = "notifications"

    @DocumentID private var documentID: String?
    let recipientID: String
    let actorID: String
    let kind: NotificationKind
    let title: String
    let body: String
    var isRead: Bool
    @ServerTimestamp var createdAt: Date?

    var id: String { documentID ?? "" }
}
