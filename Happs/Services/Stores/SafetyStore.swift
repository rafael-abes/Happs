//
//  SafetyStore.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//
// CODE OVERVIEW
// ObservableObject store for blocking, hiding and reporting, following the same pattern as the other
// stores: it attaches Firestore snapshot listeners so views update live whenever the lists change
// (on this or another device), exposes the data as @Published properties, and writes with async
// methods. Views read blockedIDs and hiddenContentIDs to filter content. Reports go to a top level
// "reports" collection for moderation. The block and hidden lists are subcollections of the user
// document so Firestore rules can limit them to the owner.
//
import Foundation
import FirebaseFirestore
import Combine

/// One person I blocked, with the name saved at block time so the list works even if their profile is gone.
struct BlockedUser: Identifiable, Equatable {
    let id: String
    let name: String
    let blockedAt: Date
}

/// Source of truth for what this user has blocked, hidden and reported.
@MainActor
final class SafetyStore: ObservableObject {
    /// People I blocked, sorted by name. Only this class can change it (private(set)).
    @Published private(set) var blocked: [BlockedUser] = []
    /// IDs of content I hid or reported. A Set gives fast contains checks in list views.
    @Published private(set) var hiddenContentIDs: Set<String> = []
    /// Last user-facing error, shown by the view. Not private(set) so the view can clear it.
    @Published var errorMessage: String?

    /// Computed set of blocked user ids for quick filtering in views.
    var blockedIDs: Set<String> { Set(blocked.map(\.id)) }

    private let database: Firestore
    /// Handles needed to stop the Firestore listeners later (remove()).
    private var blockListener: ListenerRegistration?
    private var hiddenListener: ListenerRegistration?
    /// Which user the listeners belong to.
    private var currentUserID: String?

    /// The database is a parameter so tests can pass another instance.
    init(database: Firestore = .firestore()) {
        self.database = database
    }

    // MARK: Queries used by the views

    /// True if this user is on my block list.
    func isBlocked(_ userID: String) -> Bool {
        blocked.contains { $0.id == userID }
    }

    /// True if this content id is on my hidden list. A nil id (content without one) is never hidden.
    func isHidden(_ contentID: String?) -> Bool {
        guard let contentID else { return false }
        return hiddenContentIDs.contains(contentID)
    }

    // MARK: Listening

    /// Attaches both snapshot listeners. Safe to call repeatedly: it does nothing if already listening for this user.
    func startListening(userID: String) {
        // Avoids duplicate listeners when the view appears more than once.
        guard currentUserID != userID else { return }
        // Remove listeners from any earlier user first.
        stopListening()
        currentUserID = userID
        let user = database.collection("users").document(userID)

        // The listener closure is not on the main actor, so Task { @MainActor } is used to update published state. [weak self] avoids a retain cycle with the listener.
        blockListener = user.collection("blocked").addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.log(error); return }
                self.blocked = (snapshot?.documents ?? []).map { document in
                    BlockedUser(
                        id: document.documentID,
                        name: document.data()["name"] as? String ?? "Blocked user",
                        blockedAt: (document.data()["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    )
                }
                // Firestore returns documents in id order, so sort by name for display.
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }

        hiddenListener = user.collection("hidden").addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.log(error); return }
                self.hiddenContentIDs = Set((snapshot?.documents ?? []).map(\.documentID))
            }
        }
    }

    /// Removes listeners and clears state, for example on sign out so the next user does not see old data.
    func stopListening() {
        blockListener?.remove()
        hiddenListener?.remove()
        blockListener = nil
        hiddenListener = nil
        currentUserID = nil
        blocked = []
        hiddenContentIDs = []
    }

    // MARK: Blocking

    /// Blocks a person and removes the friendship in the same step.
    func block(userID: String, name: String, currentUserID: String, friendStore: FriendStore) async {
        // Cannot block yourself.
        guard userID != currentUserID else { return }
        do {
            try await database.collection("users").document(currentUserID)
                .collection("blocked").document(userID)
                // serverTimestamp lets the server set the time, so a wrong phone clock does not matter.
                .setData(["name": name, "createdAt": FieldValue.serverTimestamp()])
            // Blocking also unfriends, so location sharing between the two stops.
            await friendStore.removeFriend(userID, currentUserID: currentUserID)
        } catch {
            errorMessage = "Couldn't block \(name). Check your connection and try again."
            log(error)
        }
    }

    /// Deletes the block document. The snapshot listener then updates `blocked` by itself.
    func unblock(userID: String, currentUserID: String) async {
        do {
            try await database.collection("users").document(currentUserID)
                .collection("blocked").document(userID).delete()
        } catch {
            errorMessage = "Couldn't unblock this person. Try again."
            log(error)
        }
    }

    // MARK: Hiding and reporting

    /// Hides one item (photo, Happ and so on) for me only, by saving its id. Errors are only logged.
    func hide(contentID: String, currentUserID: String) async {
        do {
            try await database.collection("users").document(currentUserID)
                .collection("hidden").document(contentID)
                .setData(["createdAt": FieldValue.serverTimestamp()])
        } catch {
            log(error)
        }
    }

    /// Writes the report, then hides the item for the reporter if asked.
    // (the report is created with document() so Firestore chooses a new id)
    func report(
        _ target: ReportTarget,
        reason: ReportReason,
        details: String,
        reporterID: String,
        hideForMe: Bool
    ) async throws {
        var data = target.payload(reporterID: reporterID, reason: reason, details: details)
        data["createdAt"] = FieldValue.serverTimestamp()
        // document() with no argument makes a new auto-id document.
        try await database.collection("reports").document().setData(data)

        if hideForMe, let hideID = target.hideID {
            await hide(contentID: hideID, currentUserID: reporterID)
        }
    }

    // MARK: Deletion support

    /// Removes the user's own safety data. Used by account deletion.
    func deleteOwnData(userID: String) async {
        let user = database.collection("users").document(userID)
        for name in ["blocked", "hidden"] {
            if let snapshot = try? await user.collection(name).getDocuments() {
                for document in snapshot.documents { try? await document.reference.delete() }
            }
        }
    }

    /// Debug-only console logging; compiled out of release builds by #if DEBUG.
    private func log(_ error: Error) {
        #if DEBUG
        print("SafetyStore error: \(error)")
        #endif
    }
}
