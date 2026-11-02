//
//  GroupStore.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
final class GroupStore: ObservableObject {
    @Published private(set) var groups: [FriendGroup] = []
    @Published private(set) var allInvitations: [FriendGroup] = []
    /// Set from ContentView. Invitations from a blocked person are hidden.
    @Published var blockedIDs: Set<String> = []
    
    var invitations: [FriendGroup] {
        allInvitations.filter { !blockedIDs.contains($0.ownerID) }
    }
    @Published private(set) var activity: [GroupActivity] = []
    @Published private(set) var names: [String: String] = [:]
    @Published private(set) var errorMessage: String?

    private let database: Firestore
    private let notifications: NotificationWriter
    private var memberListener: ListenerRegistration?
    private var inviteListener: ListenerRegistration?
    private var activityListener: ListenerRegistration?

    init(database: Firestore = .firestore()) {
        self.database = database
        self.notifications = NotificationWriter(database: database)
    }

    func name(for userID: String) -> String {
        names[userID] ?? "Someone"
    }

    func startListening(for userID: String) {
        guard memberListener == nil else { return }

        memberListener = database.collection(FriendGroup.collectionName)
            .whereField("memberIDs", arrayContains: userID)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.groups = Self.decodeGroups(snapshot)
                }
            }

        inviteListener = database.collection(FriendGroup.collectionName)
            .whereField("invitedIDs", arrayContains: userID)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.allInvitations = Self.decodeGroups(snapshot)
                }
            }
    }

    func stopListening() {
        memberListener?.remove()
        memberListener = nil
        inviteListener?.remove()
        inviteListener = nil
        stopActivity()
        groups = []
        allInvitations = []
    }

    func listenToActivity(groupID: String) {
        stopActivity()
        activityListener = database.collection(FriendGroup.collectionName).document(groupID)
            .collection("activity")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, error == nil else { return }
                    self.activity = (snapshot?.documents ?? [])
                        .compactMap { try? $0.data(as: GroupActivity.self) }
                        .sorted { ($0.createdAt ?? .now) > ($1.createdAt ?? .now) }
                }
            }
    }

    func stopActivity() {
        activityListener?.remove()
        activityListener = nil
        activity = []
    }

    func clearError() {
        errorMessage = nil
    }

    func resolveNames(for ids: [String]) async {
        let missing = Array(Set(ids).filter { names[$0] == nil })
        guard !missing.isEmpty else { return }

        for start in stride(from: 0, to: missing.count, by: 10) {
            let chunk = Array(missing[start..<min(start + 10, missing.count)])
            guard let snapshot = try? await database.collection(UserSearchEntry.collectionName)
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments() else { continue }
            for document in snapshot.documents {
                if let entry = try? document.data(as: UserSearchEntry.self) {
                    names[entry.id] = entry.displayName
                }
            }
        }
    }

    // MARK: - Create, edit, delete

    func createGroup(name: String, ownerID: String, inviteIDs: [String]) async throws {
        let cleaned = try validatedName(name, excluding: nil)
        guard !inviteIDs.isEmpty else {
            throw AppError.invalidForm("Pick at least one friend to invite.")
        }
        let group = FriendGroup(name: cleaned, ownerID: ownerID, memberIDs: [ownerID], invitedIDs: inviteIDs)
        let data = try Firestore.Encoder().encode(group)
        try await database.collection(FriendGroup.collectionName).document().setData(data)

        await notifyInvitees(inviteIDs, groupName: cleaned, ownerID: ownerID)
    }

    func updateGroup(_ group: FriendGroup, name: String, selectedIDs: Set<String>) async throws {
        let cleaned = try validatedName(name, excluding: group.id)
        let keptMembers = group.memberIDs.filter { $0 == group.ownerID || selectedIDs.contains($0) }
        let invited = selectedIDs.subtracting(group.memberIDs)
        try await database.collection(FriendGroup.collectionName).document(group.id).updateData([
            "name": cleaned,
            "memberIDs": keptMembers,
            "invitedIDs": Array(invited)
        ])

        let newlyInvited = invited.subtracting(group.invitedIDs)
        await notifyInvitees(Array(newlyInvited), groupName: cleaned, ownerID: group.ownerID)
    }

    func deleteGroup(_ group: FriendGroup) async {
        do {
            try await database.collection(FriendGroup.collectionName).document(group.id).delete()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let recipients = Set(group.memberIDs + group.invitedIDs).subtracting([group.ownerID])
        let ownerName = NotificationWriter.actorName
        let drafts = recipients.map {
            NotificationDraft(
                recipientID: $0,
                kind: .groupDeleted,
                title: "Group deleted",
                body: "\(ownerName) deleted the group \(group.name)"
            )
        }
        await notifications.send(drafts, from: group.ownerID)
    }
    // MARK: - Responding to invites

    func respond(to group: FriendGroup, accept: Bool, userID: String, userName: String) async {
        let text = accept
            ? "\(userName) has joined group \(group.name)"
            : "\(userName) has declined invitation to \(group.name)"

        var update: [String: Any] = ["invitedIDs": FieldValue.arrayRemove([userID])]
        if accept { update["memberIDs"] = FieldValue.arrayUnion([userID]) }

        let succeeded = await commit(update: update, text: text, group: group, userID: userID)
        guard succeeded else { return }
        await notifyOwner(of: group, kind: accept ? .groupJoined : .groupDeclined, text: text, userID: userID)
    }

    func leave(_ group: FriendGroup, userID: String, userName: String) async {
        let text = "\(userName) has left group \(group.name)"
        let succeeded = await commit(
            update: ["memberIDs": FieldValue.arrayRemove([userID])],
            text: text,
            group: group,
            userID: userID
        )
        guard succeeded else { return }
        await notifyOwner(of: group, kind: .groupLeft, text: text, userID: userID)
    }

    // MARK: - Helpers

    private func commit(update: [String: Any], text: String, group: FriendGroup, userID: String) async -> Bool {
        let groupReference = database.collection(FriendGroup.collectionName).document(group.id)
        let activityReference = groupReference.collection("activity").document()

        let batch = database.batch()
        batch.updateData(update, forDocument: groupReference)
        batch.setData([
            "text": text,
            "actorID": userID,
            "createdAt": FieldValue.serverTimestamp()
        ], forDocument: activityReference)

        do {
            try await batch.commit()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func notifyInvitees(_ ids: [String], groupName: String, ownerID: String) async {
        guard !ids.isEmpty else { return }
        let ownerName = NotificationWriter.actorName
        let drafts = ids.map {
            NotificationDraft(
                recipientID: $0,
                kind: .groupInvite,
                title: "Group invitation",
                body: "\(ownerName) invited you to \(groupName)"
            )
        }
        await notifications.send(drafts, from: ownerID)
    }

    private func notifyOwner(of group: FriendGroup, kind: NotificationKind, text: String, userID: String) async {
        await notifications.send([
            NotificationDraft(recipientID: group.ownerID, kind: kind, title: "Group update", body: text)
        ], from: userID)
    }

    private func validatedName(_ name: String, excluding excludedID: String?) throws -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw AppError.invalidForm("Give the group a name.")
        }
        guard cleaned.count <= 40 else {
            throw AppError.invalidForm("Keep the name to 40 characters or fewer.")
        }
        try ContentFilter.validate(cleaned, field: "group name")
        let isDuplicate = groups.contains {
            $0.id != excludedID && $0.name.localizedCaseInsensitiveCompare(cleaned) == .orderedSame
        }
        guard !isDuplicate else {
            throw AppError.invalidForm("You already have a group with that name.")
        }
        return cleaned
    }

    private static func decodeGroups(_ snapshot: QuerySnapshot?) -> [FriendGroup] {
        (snapshot?.documents ?? [])
            .compactMap { try? $0.data(as: FriendGroup.self) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

