//
//  RecapsNotifications.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//
// CODE OVERVIEW
// Pure decision logic (no Firestore, no UI): given who attended, who the poster's friends are and
// how many photos were posted, it returns a list of NotificationDraft values. A separate writer
// (NotificationWriter, referenced in the header above) is what actually saves them. Keeping the
// rules as a pure function of plain values makes them easy to unit test and explain.
// Sets are used so nobody can appear twice, and the result is sorted so the output is deterministic.
//
import Foundation

/// The inputs the rules need, as plain values so tests can build them without Firebase.
struct RecapAudience {
    let happTitle: String
    /// Everyone who joined the Happ.
    let attendeeIDs: [String]
    /// The poster's friends.
    let friendIDs: [String]
}

/// Namespace (caseless enum) for the recap notification rules.
enum RecapNotifications {
    /// Builds the notifications for one recap post.
    /// - Parameters:
    ///   - audience: attendees and friends of the poster.
    ///   - authorID: the poster, who is never notified.
    ///   - authorName: shown in the notification text.
    ///   - photoCount: number of photos posted, 0 gives no notifications.
    /// - Returns: one draft per recipient, attendees first and then friends who did not attend.
    static func drafts(
        for audience: RecapAudience,
        authorID: String,
        authorName: String,
        photoCount: Int
    ) -> [NotificationDraft] {
        guard photoCount > 0 else { return [] }
        // Remove the poster from both groups, and remove attendees from the friend group
        // so a friend who also joined gets only the "posted" message, not both.
        let attendees = Set(audience.attendeeIDs).subtracting([authorID])
        let missed = Set(audience.friendIDs).subtracting(attendees).subtracting([authorID])
        // Singular or plural wording for the body text.
        let noun = photoCount == 1 ? "a photo" : "\(photoCount) photos"

        // Sorting a Set gives a stable order (a Set itself has none).
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
