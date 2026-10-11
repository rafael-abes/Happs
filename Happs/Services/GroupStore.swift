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
    @Published private(set) var invitations: [FriendGroup] = []
    @Published private(set) var activity: [GroupActivity] = []
    @Published private(set) var names: [String: String] = [:]
    @Published private(set) var errorMessage: String?
    
    private let database: Firestore
    private var memberListener: ListenerRegistration?
    private var inviteListener: ListenerRegistration?
    private var activityListener: ListenerRegistration?
    
    init(database: Firestore = .firestore()) {
        self.database = database
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
                    if let error { self.errorMessage = error.localizedDescription; return }
                    self.groups = Self.decodeGroups(snapshot)
                }
            }
        
        inviteListener = database.collection(FriendGroup.collectionName)
            .whereField("invitedIDs", arrayContains: userID)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error { self.errorMessage = error.localizedDescription; return }
                    self.invitations = Self.decodeGroups(snapshot)
                }
            }
    }
    
    func stopListening() {
        memberListener?.remove(); memberListener = nil
        inviteListener?.remove(); inviteListener = nil
        stopActivity()
        groups = []
        invitations = []
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
    
    func clearError() { errorMessage = nil }
    
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
    
    func createGroup(name: String, ownerID: String, inviteIDs: [String]) async throws {
        let cleaned = try validatedName(name, excluding: nil)
        guard !inviteIDs.isEmpty else {
            throw AppError.invalidForm("Pick at least one friend to invite.")
        }
        let group = FriendGroup(name: cleaned, ownerID: ownerID, memberIDs: [ownerID], invitedIDs: inviteIDs)
        let data = try Firestore.Encoder().encode(group)
        try await database.collection(FriendGroup.collectionName).document().setData(data)
    }
    
    func updateGroup(_ group: FriendGroup, name: String, selectedIDs: Set<String>) async throws {
        let cleaned = try validatedName(name, excluding: group.id)
        let keptMembers = group.memberIDs.filter { $0 == group.ownerID || selectedIDs.contains($0) }
        let invited = selectedIDs.subtracting(Set(group.memberIDs))
        try await database.collection(FriendGroup.collectionName).document(group.id).updateData([
            "name": cleaned,
            "memberIDs": keptMembers,
            "invitedIDs": Array(invited)
        ])
    }
    
    func respond(to group: FriendGroup, accept: Bool, userID: String, userName: String) async {
        let groupReference = database.collection(FriendGroup.collectionName).document(group.id)
        let text = accept
            ? "\(userName) has joined group \(group.name)"
            : "\(userName) has declined invitation to \(group.name)"
        
        var update: [String: Any] = ["invitedIDs": FieldValue.arrayRemove([userID])]
        if accept { update["memberIDs"] = FieldValue.arrayUnion([userID]) }
        
        await commit(update: update, text: text, group: group, userID: userID)
    }
    
    func leave(_ group: FriendGroup, userID: String, userName: String) async {
        await commit(
            update: ["memberIDs": FieldValue.arrayRemove([userID])],
            text: "\(userName) has left group \(group.name)",
            group: group,
            userID: userID
        )
    }
    
    func deleteGroup(_ group: FriendGroup) async {
        do {
            try await database.collection(FriendGroup.collectionName).document(group.id).delete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func commit(update: [String: Any], text: String, group: FriendGroup, userID: String) async {
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func validatedName(_ name: String, excluding excludedID: String?) throws -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw AppError.invalidForm("Give the group a name.")
        }
        guard cleaned.count <= 40 else {
            throw AppError.invalidForm("Keep the name to 40 characters or fewer.")
        }
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
