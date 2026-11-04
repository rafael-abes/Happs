//
//  GroupStore.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//

// CODE OVERVIEW
// GroupStore manages friend groups: the groups I belong to, invitations to join, each group's
// activity feed, and creating, editing, deleting, joining and leaving. It is an ObservableObject
// (views observe it) and @MainActor (published state is read by the UI). Live data comes from
// Firestore snapshot listeners, so membership and invitations update without refreshing.
// Membership is stored as ID arrays on the group document (memberIDs, invitedIDs) and queried
// with arrayContains. Changes that must happen together (update the group AND log an activity)
// use a batch write. Validation (length, content filter, duplicate name) lives here in the
// store so no screen can skip it. Firestore is injected through init for flexibility.
import Foundation
import FirebaseFirestore
import Combine

/// Observable store for friend groups, invitations and group activity. Created once and shared
/// with views; call startListening after sign in and stopListening on sign out.
@MainActor
final class GroupStore: ObservableObject {
    /// Groups the user is a member of, sorted by name.
    @Published private(set) var groups: [FriendGroup] = []
    /// Groups that have invited the user, including ones from blocked owners.
    /// Views should read invitations instead.
    @Published private(set) var allInvitations: [FriendGroup] = []
    /// Set from ContentView. Invitations from a blocked person are hidden.
    @Published var blockedIDs: Set<String> = []
    
    /// Invitations with blocked owners removed. Computed from allInvitations, so it updates
    /// automatically when either allInvitations or blockedIDs changes.
    var invitations: [FriendGroup] {
        allInvitations.filter { !blockedIDs.contains($0.ownerID) }
    }
    /// Activity feed of the group currently being viewed, newest first.
    @Published private(set) var activity: [GroupActivity] = []
    /// Cache of user ID to display name, filled by resolveNames, so member lists show names.
    @Published private(set) var names: [String: String] = [:]
    /// Last error for the UI to show. Cleared by clearError.
    @Published private(set) var errorMessage: String?

    /// Injected Firestore handle.
    private let database: Firestore
    /// Helper that writes notification documents for other users.
    private let notifications: NotificationWriter
    /// Listener for groups where I am a member.
    private var memberListener: ListenerRegistration?
    /// Listener for groups that have invited me.
    private var inviteListener: ListenerRegistration?
    /// Listener for the activity subcollection of the one group being viewed.
    private var activityListener: ListenerRegistration?

    init(database: Firestore = .firestore()) {
        self.database = database
        self.notifications = NotificationWriter(database: database)
    }

    /// Display name for a user ID from the cache, or "Someone" if not loaded yet.
    func name(for userID: String) -> String {
        names[userID] ?? "Someone"
    }

    /// Starts the two live queries (member groups and invitations). The guard makes a second
    /// call do nothing, so listeners are never doubled.
    /// - Parameter userID: the signed in user's uid, matched with arrayContains.
    func startListening(for userID: String) {
        guard memberListener == nil else { return }

        memberListener = database.collection(FriendGroup.collectionName)
            // arrayContains matches documents whose memberIDs array includes my uid.
            .whereField("memberIDs", arrayContains: userID)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    // Snapshot callbacks may arrive off the main actor, so Task { @MainActor } hops back before
                    // ~changing published state. [weak self] avoids a retain cycle with the listener.
                    self.groups = Self.decodeGroups(snapshot)
                }
            }

        inviteListener = database.collection(FriendGroup.collectionName)
            // Same idea for invitations: the array holds the IDs of invited people.
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

    /// Removes all listeners and clears state, used on sign out.
    func stopListening() {
        memberListener?.remove()
        memberListener = nil
        inviteListener?.remove()
        inviteListener = nil
        stopActivity()
        groups = []
        allInvitations = []
    }

    /// Starts listening to one group's activity subcollection. Any previous activity listener is
    /// stopped first, so only one group's feed is live at a time.
    func listenToActivity(groupID: String) {
        stopActivity()
        activityListener = database.collection(FriendGroup.collectionName).document(groupID)
            .collection("activity")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    // Errors here are ignored on purpose (the feed just stops updating). Assumed reason: the feed is secondary to the group itself.
                    guard let self, error == nil else { return }
                    self.activity = (snapshot?.documents ?? [])
                        .compactMap { try? $0.data(as: GroupActivity.self) }
                        // createdAt can be nil briefly because the server timestamp is not set yet for a local write, so .now is used.
                        .sorted { ($0.createdAt ?? .now) > ($1.createdAt ?? .now) }
                }
            }
    }

    /// Stops the activity listener and clears the feed.
    func stopActivity() {
        activityListener?.remove()
        activityListener = nil
        activity = []
    }

    /// Resets errorMessage once shown.
    func clearError() {
        errorMessage = nil
    }

    /// Looks up display names for IDs not already cached, from the public UserSearchEntry
    /// collection. Firestore's `in` filter accepts at most 10 values (a Firestore limit), so IDs
    /// are fetched in chunks of 10. A failed chunk is skipped with try? and left unresolved.
    func resolveNames(for ids: [String]) async {
        // Set removes duplicates and the filter drops IDs we already know.
        let missing = Array(Set(ids).filter { names[$0] == nil })
        guard !missing.isEmpty else { return }

        // Step through the missing IDs 10 at a time.
        for start in stride(from: 0, to: missing.count, by: 10) {
            let chunk = Array(missing[start..<min(start + 10, missing.count)])
            guard let snapshot = try? await database.collection(UserSearchEntry.collectionName)
                // Query by document ID: the search entries use the user ID as their document ID.
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

    /// Validates and creates a group with the owner as the only member and everyone else as
    /// invited. Throws AppError.invalidForm for bad input. document() with no ID asks Firestore
    /// to generate a unique ID.
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

    /// Renames a group and syncs its people to the selection. The owner is always kept as a
    /// member. Members not selected are removed, selected non members become invited, and only
    /// the newly invited people get a notification.
    func updateGroup(_ group: FriendGroup, name: String, selectedIDs: Set<String>) async throws {
        let cleaned = try validatedName(name, excluding: group.id)
        // Keep the owner always, and keep other members only if still selected.
        let keptMembers = group.memberIDs.filter { $0 == group.ownerID || selectedIDs.contains($0) }
        // Selected people who are not yet members become invitations.
        let invited = selectedIDs.subtracting(group.memberIDs)
        try await database.collection(FriendGroup.collectionName).document(group.id).updateData([
            "name": cleaned,
            "memberIDs": keptMembers,
            "invitedIDs": Array(invited)
        ])

        // Only notify people who were not already invited before this edit.
        let newlyInvited = invited.subtracting(group.invitedIDs)
        await notifyInvitees(Array(newlyInvited), groupName: cleaned, ownerID: group.ownerID)
    }

    /// Deletes the group, then tells every other member and invitee. If the delete fails the
    /// error is stored and no notification is sent.
    func deleteGroup(_ group: FriendGroup) async {
        do {
            try await database.collection(FriendGroup.collectionName).document(group.id).delete()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // Set merges members and invitees without duplicates, and the owner is excluded.
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

    /// Accepts or declines an invitation. Always removes me from invitedIDs, and adds me to
    /// memberIDs only on accept. arrayRemove and arrayUnion edit the array atomically on the server.
    func respond(to group: FriendGroup, accept: Bool, userID: String, userName: String) async {
        let text = accept
            ? "\(userName) has joined group \(group.name)"
            : "\(userName) has declined invitation to \(group.name)"

        // The invitation is consumed either way. On accept the user is also added to memberIDs.
        var update: [String: Any] = ["invitedIDs": FieldValue.arrayRemove([userID])]
        if accept { update["memberIDs"] = FieldValue.arrayUnion([userID]) }

        // Only notify the owner if the write really happened.
        let succeeded = await commit(update: update, text: text, group: group, userID: userID)
        guard succeeded else { return }
        await notifyOwner(of: group, kind: accept ? .groupJoined : .groupDeclined, text: text, userID: userID)
    }

    /// Removes the user from the group's members and logs and notifies it.
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

    /// Applies a group update and writes an activity entry in one batch, so the group change
    /// and its feed entry succeed or fail together.
    /// - Returns: true if the commit worked. On failure errorMessage is set.
    private func commit(update: [String: Any], text: String, group: FriendGroup, userID: String) async -> Bool {
        let groupReference = database.collection(FriendGroup.collectionName).document(group.id)
        let activityReference = groupReference.collection("activity").document()

        let batch = database.batch()
        batch.updateData(update, forDocument: groupReference)
        batch.setData([
            "text": text,
            "actorID": userID,
            // serverTimestamp lets Firestore stamp the time, so it is not affected by the phone clock.
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

    /// Sends a "Group invitation" notification to each invited user.
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

    /// Sends the group owner a notification about a join, decline or leave.
    private func notifyOwner(of group: FriendGroup, kind: NotificationKind, text: String, userID: String) async {
        await notifications.send([
            NotificationDraft(recipientID: group.ownerID, kind: kind, title: "Group update", body: text)
        ], from: userID)
    }

    /// Trims and checks a group name: not empty, at most 40 characters, passes ContentFilter,
    /// and not the same (ignoring case) as another of my groups. excludedID lets an edit keep
    /// its own name.
    /// - Returns: the cleaned name.
    /// - Throws: AppError.invalidForm.
    private func validatedName(_ name: String, excluding excludedID: String?) throws -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw AppError.invalidForm("Give the group a name.")
        }
        guard cleaned.count <= 40 else {
            throw AppError.invalidForm("Keep the name to 40 characters or fewer.")
        }
        try ContentFilter.validate(cleaned, field: "group name")
        // Duplicate check only looks at my own groups, which is what the error message says.
        let isDuplicate = groups.contains {
            $0.id != excludedID && $0.name.localizedCaseInsensitiveCompare(cleaned) == .orderedSame
        }
        guard !isDuplicate else {
            throw AppError.invalidForm("You already have a group with that name.")
        }
        return cleaned
    }

    /// Converts a snapshot into sorted FriendGroup values. static because it uses no instance
    /// state. try? skips documents that fail to decode instead of failing the whole list.
    private static func decodeGroups(_ snapshot: QuerySnapshot?) -> [FriendGroup] {
        (snapshot?.documents ?? [])
            .compactMap { try? $0.data(as: FriendGroup.self) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

