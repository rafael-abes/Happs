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
    @Published private(set) var errorMessage: String?
    
    private let database: Firestore
    private var listener: ListenerRegistration?
    
    init(database: Firestore = .firestore()) {
        self.database = database
    }
    
    func startListening(for userID: String) {
        guard listener == nil else { return }
        listener = database.collection(FriendGroup.collectionName)
            .whereField("ownerID", isEqualTo: userID)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.groups = (snapshot?.documents ?? [])
                        .compactMap { try? $0.data(as: FriendGroup.self) }
                        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }
            }
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
        groups = []
    }
    
    func clearError() { errorMessage = nil }
    
    func createGroup(name: String, ownerID: String, memberIDs: [String]) async throws {
        let cleaned = try validatedName(name, memberIDs: memberIDs, excluding: nil)
        let group = FriendGroup(name: cleaned, ownerID: ownerID, memberIDs: memberIDs)
        let data = try Firestore.Encoder().encode(group)
        try await database.collection(FriendGroup.collectionName).document().setData(data)
    }
    
    func updateGroup(_ group: FriendGroup, name: String, memberIDs: [String]) async throws {
        let cleaned = try validatedName(name, memberIDs: memberIDs, excluding: group.id)
        try await database.collection(FriendGroup.collectionName).document(group.id).updateData([
            "name": cleaned,
            "memberIDs": memberIDs
        ])
    }
    
    func deleteGroup(_ group: FriendGroup) async {
        do {
            try await database.collection(FriendGroup.collectionName).document(group.id).delete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func validatedName(_ name: String, memberIDs: [String], excluding excludedID: String?) throws -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw AppError.invalidForm("Give the group a name.")
        }
        guard cleaned.count <= 40 else {
            throw AppError.invalidForm("Keep the name to 40 characters or fewer.")
        }
        guard !memberIDs.isEmpty else {
            throw AppError.invalidForm("Pick at least one friend.")
        }
        let isDuplicate = groups.contains {
            $0.id != excludedID && $0.name.localizedCaseInsensitiveCompare(cleaned) == .orderedSame
        }
        guard !isDuplicate else {
            throw AppError.invalidForm("You already have a group with that name.")
        }
        return cleaned
    }
}
