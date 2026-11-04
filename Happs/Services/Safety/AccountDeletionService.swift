//
//  AccountDeletionService.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//
// CODE OVERVIEW
// Deletes everything tied to a user from Firestore and Supabase before the Auth account is removed.
// It is a struct with its dependencies passed in (Firestore, RecapStore, SafetyStore) so they can be
// swapped for tests. Each area of data is wrapped in step(...), which catches errors and records the
// failed area's name instead of aborting, so one bad step does not leave all the rest undone. Only the
// profile document delete is allowed to throw. Firestore has no cascading deletes, so this client
// code has to find each related document with a query and delete it. See the header above for the order.
//
import Foundation
import FirebaseFirestore

/// Outcome of a purge, so the UI can tell the user if something was left behind.
struct AccountDeletionResult {
    /// Steps that did not finish. Empty means everything was removed.
    var failedSteps: [String] = []
}

/// Runs the multi-step deletion. On the main actor because it calls main-actor stores.
@MainActor
struct AccountDeletionService {
    /// Firestore handle (injectable, defaults to the shared one).
    let database: Firestore
    let recapStore: RecapStore
    let safetyStore: SafetyStore

    /// Dependency injection through the initialiser, with the real Firestore as the default.
    init(recapStore: RecapStore, safetyStore: SafetyStore, database: Firestore = .firestore()) {
        self.database = database
        self.recapStore = recapStore
        self.safetyStore = safetyStore
    }

    /// Removes the user's data. Throws only if the profile document itself cannot be removed;
    /// the caller then deletes the Auth account.
    /// - Parameters:
    ///   - userID: the account being deleted.
    ///   - friendIDs: current friends, whose friend lists must drop this user.
    /// - Returns: which steps failed (empty on full success).
    func purge(userID: String, friendIDs: [String]) async throws -> AccountDeletionResult {
        var result = AccountDeletionResult()

        // 1. Recap photos posted by this user
        await recapStore.removeAll(forAuthor: userID)

        // 2. Happs
        // Three queries: Happs I created (deleted, with recaps), Happs I joined and Happs I was invited to
        // (only my id is removed). arrayRemove edits the array on the server without reading it first.
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
                // Each friend's own document lists this user, so remove the id from their friendIDs.
                try await database.collection("users").document(friendID)
                    .updateData(["friendIDs": FieldValue.arrayRemove([userID])])
            }
            // Two queries because a request can be sent by me (fromUserID) or to me (toUserID).
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
        // Safety data is owned by SafetyStore, so it deletes its own blocked and hidden lists.
        await safetyStore.deleteOwnData(userID: userID)
        await step("Location and search", &result) {
            try await database.collection("liveLocations").document(userID).delete()
            try await database.collection(UserSearchEntry.collectionName).document(userID).delete()
        }

        // 7. On this device
        await RecapReminders.removeAll()
        // Clears the locally stored AI consent for this user.
        AIConsent.setConsent(false, userID: userID)

        // 6b. The profile itself. This one must succeed.
        // Not wrapped in step(): this error propagates so the caller knows deletion did not finish.
        try await database.collection("users").document(userID).delete()
        return result
    }

    // MARK: Helpers

    /// Runs one deletion area, recording its name in the result if it throws instead of stopping the whole purge.
    /// `inout` lets the helper mutate the caller's result value.
    private func step(
        _ name: String,
        _ result: inout AccountDeletionResult,
        _ work: () async throws -> Void
    ) async {
        do { try await work() } catch { result.failedSteps.append(name) }
    }

    /// Deletes a Happ's recap documents, their Supabase files and the blurred previews. Uses try? so
    /// a missing file does not stop the Happ being deleted.
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

    /// Fetches every document matching the query and deletes them one by one (simple, not batched).
    private func deleteAll(in query: Query) async throws {
        let snapshot = try await query.getDocuments()
        for document in snapshot.documents { try await document.reference.delete() }
    }
}

