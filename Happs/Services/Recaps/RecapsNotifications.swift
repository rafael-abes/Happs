//
//  RecapsNotifications.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//
import Foundation

struct RecapAudience {
    let happTitle: String
    /// Everyone who joined the Happ.
    let attendeeIDs: [String]
    /// The poster's friends.
    let friendIDs: [String]
}

enum RecapNotifications {
    static func drafts(
        for audience: RecapAudience,
        authorID: String,
        authorName: String,
        photoCount: Int
    ) -> [NotificationDraft] {
        guard photoCount > 0 else { return [] }
        let attendees = Set(audience.attendeeIDs).subtracting([authorID])
        let missed = Set(audience.friendIDs).subtracting(attendees).subtracting([authorID])
        let noun = photoCount == 1 ? "a photo" : "\(photoCount) photos"

        let joined = attendees.sorted().map {
            NotificationDraft(
                recipientID: $0,
                kind: .recapPosted,
                title: "New photos from \(audience.happTitle)",
                body: "\(authorName) shared \(noun) from \(audience.happTitle)."
            )
        }
        let others = missed.sorted().map {
            NotificationDraft(
                recipientID: $0,
                kind: .recapMissed,
                title: "You missed this one",
                body: "\(authorName) shared photos from \(audience.happTitle). See what you missed."
            )
        }
        return joined + others
    }
}
