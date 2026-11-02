//
//  AccountDeletionService.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//
import Foundation
import FirebaseFirestore

struct AccountDeletionResult {
    /// Steps that did not finish. Empty means everything was removed.
    var failedSteps: [String] = []
}

@MainActor
struct AccountDeletionService {
    let database: Firestore
    let recapStore: RecapStore
    let safetyStore: SafetyStore

    init(recapStore: RecapStore, safetyStore: SafetyStore, database: Firestore = .firestore()) {
        self.database = database
        self.recapStore = recapStore
        self.safetyStore = safetyStore
    }

    /// Removes the user's data. Throws only if the profile document itself cannot be removed;
    /// the caller then deletes the Auth account.
    func purge(userID: String, friendIDs: [String]) async throws -> AccountDeletionResult {
        var result = AccountDeletionResult()

        // 1. Recap photos posted by this user
        await recapStore.removeAll(forAuthor: userID)

        // 2. Happs
        await step("Happs", &result) {
            let created = try await database.collection(Happ.collectionName)
                .whereField("creatorID", isEqualTo: userID).getDocuments()
            for happ in created.documents {
                await removeRecaps(under: happ.reference)
                try await happ.reference.delete()
            }
            let joined = try await database.collection(Happ.collectionName)
                .whereField("participantIDs", arrayContains: userID).getDocuments()
            for happ in joined.documents {
                try await happ.reference.updateData(["participantIDs": FieldValue.arrayRemove([userID])])
            }
            let invited = try await database.collection(Happ.collectionName)
                .whereField("invitedIDs", arrayContains: userID).getDocuments()
            for happ in invited.documents {
                try await happ.reference.updateData(["invitedIDs": FieldValue.arrayRemove([userID])])
            }
        }

        // 3. Groups
        await step("Groups", &result) {
            let owned = try await database.collection(FriendGroup.collectionName)
                .whereField("ownerID", isEqualTo: userID).getDocuments()
            for group in owned.documents {
                try await deleteAll(in: group.reference.collection("activity"))
                try await group.reference.delete()
            }
            let member = try await database.collection(FriendGroup.collectionName)
                .whereField("memberIDs", arrayContains: userID).getDocuments()
            for group in member.documents {
                try await group.reference.updateData(["memberIDs": FieldValue.arrayRemove([userID])])
            }
            let invited = try await database.collection(FriendGroup.collectionName)
                .whereField("invitedIDs", arrayContains: userID).getDocuments()
            for group in invited.documents {
                try await group.reference.updateData(["invitedIDs": FieldValue.arrayRemove([userID])])
            }
        }

        // 4. Friends and requests
        await step("Friends", &result) {
            for friendID in friendIDs {
                try await database.collection("users").document(friendID)
                    .updateData(["friendIDs": FieldValue.arrayRemove([userID])])
            }
            try await deleteAll(in: database.collection(FriendRequest.collectionName)
                .whereField("fromUserID", isEqualTo: userID))
            try await deleteAll(in: database.collection(FriendRequest.collectionName)
                .whereField("toUserID", isEqualTo: userID))
        }

        // 5. Notifications
        await step("Notifications", &result) {
            try await deleteAll(in: database.collection(AppNotification.collectionName)
                .whereField("recipientID", isEqualTo: userID))
            try await deleteAll(in: database.collection(AppNotification.collectionName)
                .whereField("actorID", isEqualTo: userID))
        }

        // 6. Safety lists, location, search entry
        await safetyStore.deleteOwnData(userID: userID)
        await step("Location and search", &result) {
            try await database.collection("liveLocations").document(userID).delete()
            try await database.collection(UserSearchEntry.collectionName).document(userID).delete()
        }

        // 7. On this device
        await RecapReminders.removeAll()
        AIConsent.setConsent(false, userID: userID)

        // 6b. The profile itself. This one must succeed.
        try await database.collection("users").document(userID).delete()
        return result
    }

    // MARK: Helpers

    private func step(
        _ name: String,
        _ result: inout AccountDeletionResult,
        _ work: () async throws -> Void
    ) async {
        do { try await work() } catch { result.failedSteps.append(name) }
    }

    private func removeRecaps(under happ: DocumentReference) async {
        if let recaps = try? await happ.collection("recaps").getDocuments() {
            for recap in recaps.documents {
                if let path = recap.data()["storagePath"] as? String {
                    try? await SupabaseStorageService.shared.remove(path)
                }
                try? await recap.reference.delete()
            }
        }
        try? await deleteAll(in: happ.collection("recapPreviews"))
    }

    private func deleteAll(in query: Query) async throws {
        let snapshot = try await query.getDocuments()
        for document in snapshot.documents { try await document.reference.delete() }
    }
}
