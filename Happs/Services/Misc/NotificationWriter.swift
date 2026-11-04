//
//  NotificationWriter.swift
//  Happs
//
//  Created by Rafa Abes on 10/11/26.
//

//  CODE OVERVIEW
//  -------------
//  Helper that writes notification documents to Firestore. The stores (friends, groups, Happs, recaps)
//  build NotificationDraft values and hand them to NotificationWriter.send. Notifications are written
//  in batches (one round trip, all-or-nothing per batch) and failures are swallowed on purpose, since
//  a missed notification should not undo the action that caused it. NotificationStore reads them back.
//
import Foundation
import FirebaseAuth
import FirebaseFirestore

/// The parts of a notification a caller decides. The actor and timestamp are added when sending.
struct NotificationDraft {
    let recipientID: String
    let kind: NotificationKind
    let title: String
    let body: String
}

/// Best-effort sender. A failed notification write never fails the action
/// that triggered it (sending a request, joining a Happ, and so on).
struct NotificationWriter {
    /// Injected Firestore handle (rather than Firestore.firestore() inside) so the caller controls the instance.
    let database: Firestore
    
    /// Reads the signed-in user's name. It does not perform any auth operation.
    static var actorName: String {
        Auth.auth().currentUser?.displayName ?? "Someone"
    }
    
    /// Writes one document per draft. Drafts addressed to the actor themselves are dropped, so nobody
    /// notifies themselves. Never throws: errors are only printed in Debug builds.
    func send(_ drafts: [NotificationDraft], from actorID: String) async {
        let outgoing = drafts.filter { $0.recipientID != actorID }
        guard !outgoing.isEmpty else { return }
        
        // A Firestore batch holds at most 500 writes, so split into chunks of 400 (safe margin).
        for start in stride(from: 0, to: outgoing.count, by: 400) {
            let chunk = outgoing[start..<min(start + 400, outgoing.count)]
            let batch = database.batch()
            for draft in chunk {
                // document() with no argument creates a reference with a fresh auto-generated ID.
                let reference = database.collection(AppNotification.collectionName).document()
                batch.setData([
                    "recipientID": draft.recipientID,
                    "actorID": actorID,
                    "kind": draft.kind.rawValue,
                    "title": draft.title,
                    "body": draft.body,
                    "isRead": false,
                    // Server time, not device time, so ordering is consistent across devices.
                    "createdAt": FieldValue.serverTimestamp()
                ], forDocument: reference)
            }
            do {
                try await batch.commit()
            } catch {
                #if DEBUG
                print("Notification write failed: \(error)")
                #endif
            }
        }
    }
}
