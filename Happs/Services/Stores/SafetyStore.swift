//
//  SafetyStore.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//
import Foundation
import FirebaseFirestore
import Combine

struct BlockedUser: Identifiable, Equatable {
    let id: String
    let name: String
    let blockedAt: Date
}

@MainActor
final class SafetyStore: ObservableObject {
    @Published private(set) var blocked: [BlockedUser] = []
    @Published private(set) var hiddenContentIDs: Set<String> = []
    @Published var errorMessage: String?

    var blockedIDs: Set<String> { Set(blocked.map(\.id)) }

    private let database: Firestore
    private var blockListener: ListenerRegistration?
    private var hiddenListener: ListenerRegistration?
    private var currentUserID: String?

    init(database: Firestore = .firestore()) {
        self.database = database
    }

    // MARK: Queries used by the views

    func isBlocked(_ userID: String) -> Bool {
        blocked.contains { $0.id == userID }
    }

    func isHidden(_ contentID: String?) -> Bool {
        guard let contentID else { return false }
        return hiddenContentIDs.contains(contentID)
    }

    // MARK: Listening

    func startListening(userID: String) {
        guard currentUserID != userID else { return }
        stopListening()
        currentUserID = userID
        let user = database.collection("users").document(userID)

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
        guard userID != currentUserID else { return }
        do {
            try await database.collection("users").document(currentUserID)
                .collection("blocked").document(userID)
                .setData(["name": name, "createdAt": FieldValue.serverTimestamp()])
            await friendStore.removeFriend(userID, currentUserID: currentUserID)
        } catch {
            errorMessage = "Couldn't block \(name). Check your connection and try again."
            log(error)
        }
    }

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
    func report(
        _ target: ReportTarget,
        reason: ReportReason,
        details: String,
        reporterID: String,
        hideForMe: Bool
    ) async throws {
        var data = target.payload(reporterID: reporterID, reason: reason, details: details)
        data["createdAt"] = FieldValue.serverTimestamp()
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

    private func log(_ error: Error) {
        #if DEBUG
        print("SafetyStore error: \(error)")
        #endif
    }
}
