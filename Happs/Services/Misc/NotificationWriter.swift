//
//  NotificationWriter.swift
//  Happs
//
//  Created by Rafa Abes on 10/11/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

struct NotificationDraft {
    let recipientID: String
    let kind: NotificationKind
    let title: String
    let body: String
}

/// Best-effort sender. A failed notification write never fails the action
/// that triggered it (sending a request, joining a Happ, and so on).
struct NotificationWriter {
    let database: Firestore
    
    /// Reads the signed-in user's name. It does not perform any auth operation.
    static var actorName: String {
        Auth.auth().currentUser?.displayName ?? "Someone"
    }
    
    func send(_ drafts: [NotificationDraft], from actorID: String) async {
        let outgoing = drafts.filter { $0.recipientID != actorID }
        guard !outgoing.isEmpty else { return }
        
        for start in stride(from: 0, to: outgoing.count, by: 400) {
            let chunk = outgoing[start..<min(start + 400, outgoing.count)]
            let batch = database.batch()
            for draft in chunk {
                let reference = database.collection(AppNotification.collectionName).document()
                batch.setData([
                    "recipientID": draft.recipientID,
                    "actorID": actorID,
                    "kind": draft.kind.rawValue,
                    "title": draft.title,
                    "body": draft.body,
                    "isRead": false,
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
