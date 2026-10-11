//
//  FriendStore.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
final class FriendStore: ObservableObject {
    @Published private(set) var friends: [UserProfile] = []
    @Published private(set) var friendLocations: [String: LiveLocation] = [:]
    @Published private(set) var incomingRequests: [FriendRequest] = []
    @Published private(set) var errorMessage: String?
    
    private let database: Firestore
    private var incomingListener: ListenerRegistration?
    private var profileListener: ListenerRegistration?
    private var friendsListeners: [ListenerRegistration] = []
    private var locationListeners: [ListenerRegistration] = []
    
    init(database: Firestore = .firestore()) {
        self.database = database
    }
    
    func startListening(for userID: String) {
        incomingListener = database.collection(FriendRequest.collectionName)
            .whereField("toUserID", isEqualTo: userID)
            .whereField("status", isEqualTo: FriendRequestStatus.pending.rawValue)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error { self.errorMessage = error.localizedDescription; return }
                    self.incomingRequests = (snapshot?.documents ?? [])
                        .compactMap { try? $0.data(as: FriendRequest.self) }
                }
            }
        
        // Re-attach the friends listener whenever this user's own friendIDs array changes.
        profileListener = database.collection("users").document(userID)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self, let profile = try? snapshot?.data(as: UserProfile.self) else { return }
                    self.listenToFriends(ids: profile.friendIDs)
                    self.listenToLocations(ids: profile.friendIDs)
                }
            }
    }
    

    private func listenToFriends(ids: [String]) {
        friendsListeners.forEach { $0.remove() }
        friendsListeners = []
        guard !ids.isEmpty else { friends = []; return }
        
        var combined: [String: UserProfile] = [:]
        let chunks = stride(from: 0, to: ids.count, by: 10).map { Array(ids[$0..<min($0 + 10, ids.count)]) }
        
        for chunk in chunks {
            let listener = database.collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .addSnapshotListener { [weak self] snapshot, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let error { self.errorMessage = error.localizedDescription; return }
                        for profile in (snapshot?.documents ?? []).compactMap({ try? $0.data(as: UserProfile.self) }) {
                            combined[profile.id] = profile
                        }
                        self.friends = Array(combined.values).sorted { $0.displayName < $1.displayName }
                    }
                }
            friendsListeners.append(listener)
        }
    }
    
    private func listenToLocations(ids: [String]) {
        locationListeners.forEach { $0.remove() }
        locationListeners = []
        guard !ids.isEmpty else { friendLocations = [:]; return }
        
        let chunks = stride(from: 0, to: ids.count, by: 10).map { Array(ids[$0..<min($0 + 10, ids.count)]) }
        for chunk in chunks {
            let listener = database.collection("liveLocations")
                .whereField(FieldPath.documentID(), in: chunk)
                .addSnapshotListener { [weak self] snapshot, _ in
                    Task { @MainActor in
                        guard let self else { return }
                        let documents = snapshot?.documents ?? []
                        for doc in documents {
                            if let location = try? doc.data(as: LiveLocation.self) {
                                self.friendLocations[location.id] = location
                            }
                        }
                        // A friend whose doc is no longer returned here is either off
                        // campus, invisible, or unfriended, the rule silently filters
                        // them out rather than erroring, so we clear them locally too.
                        let present = Set(documents.map { $0.documentID })
                        for id in chunk where !present.contains(id) {
                            self.friendLocations.removeValue(forKey: id)
                        }
                    }
                }
            locationListeners.append(listener)
        }
    }
    
    func stopListening() {
        incomingListener?.remove(); incomingListener = nil
        profileListener?.remove(); profileListener = nil
        friendsListeners.forEach { $0.remove() }; friendsListeners = []
        locationListeners.forEach { $0.remove() }; locationListeners = []
        friends = []
        incomingRequests = []
    }
    
    func searchUsers(matching query: String, excluding currentUserID: String) async throws -> [UserSearchEntry] {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }
        
        let snapshot = try await database.collection(UserSearchEntry.collectionName)
            .order(by: "displayName")
            .start(at: [cleaned])
            .end(at: [cleaned + "\u{f8ff}"])
            .limit(to: 20)
            .getDocuments()
        
        return snapshot.documents
            .compactMap { try? $0.data(as: UserSearchEntry.self) }
            .filter { $0.id != currentUserID }
    }
    
    func sendFriendRequest(from currentUserID: String, fromDisplayName: String, to targetUserID: String) async throws {
        guard currentUserID != targetUserID else {
            throw AppError.invalidForm("You can't friend yourself.")
        }
        let existing = try await database.collection(FriendRequest.collectionName)
            .whereField("fromUserID", isEqualTo: currentUserID)
            .whereField("toUserID", isEqualTo: targetUserID)
            .whereField("status", isEqualTo: FriendRequestStatus.pending.rawValue)
            .getDocuments()
        guard existing.documents.isEmpty else {
            throw AppError.invalidForm("Friend request already sent.")
        }
        
        let request = FriendRequest(fromUserID: currentUserID, fromDisplayName: fromDisplayName, toUserID: targetUserID, status: .pending)
        let data = try Firestore.Encoder().encode(request)
        try await database.collection(FriendRequest.collectionName).document().setData(data)
    }
    
    func acceptRequest(_ request: FriendRequest) async throws {
        let batch = database.batch()
        batch.updateData(["friendIDs": FieldValue.arrayUnion([request.toUserID])],
                          forDocument: database.collection("users").document(request.fromUserID))
        batch.updateData(["friendIDs": FieldValue.arrayUnion([request.fromUserID])],
                          forDocument: database.collection("users").document(request.toUserID))
        batch.deleteDocument(database.collection(FriendRequest.collectionName).document(request.id))
        try await batch.commit()
    }
    
    func declineRequest(_ request: FriendRequest) async throws {
        try await database.collection(FriendRequest.collectionName).document(request.id).delete()
    }
    
    func clearError() { errorMessage = nil }
}
