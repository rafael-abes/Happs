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
    private let notifications: NotificationWriter
    private var incomingListener: ListenerRegistration?
    private var profileListener: ListenerRegistration?
    private var friendListeners: [ListenerRegistration] = []
    private var locationListeners: [ListenerRegistration] = []
    private var watchedFriendIDs: [String]?
    private var profilesByID: [String: UserProfile] = [:]
    private var hasLocationAccess = false
    
    /// Smaller than the friend chunk: the location rule makes one lookup per friend
    /// plus one for the viewer, and Firestore caps rule lookups at 10 per query.
    private static let locationChunkSize = 8
    
    init(database: Firestore = .firestore()) {
        self.database = database
        self.notifications = NotificationWriter(database: database)
    }
    
    func startListening(for userID: String) {
        incomingListener?.remove()
        profileListener?.remove()
        
        incomingListener = database.collection(FriendRequest.collectionName)
            .whereField("toUserID", isEqualTo: userID)
            .whereField("status", isEqualTo: FriendRequestStatus.pending.rawValue)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.incomingRequests = (snapshot?.documents ?? [])
                        .compactMap { try? $0.data(as: FriendRequest.self) }
                }
            }
        
        profileListener = database.collection("users").document(userID)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self,
                          let profile = try? snapshot?.data(as: UserProfile.self),
                          profile.friendIDs != self.watchedFriendIDs else { return }
                    self.watchedFriendIDs = profile.friendIDs
                    self.watchFriends(ids: profile.friendIDs)
                    if self.hasLocationAccess {
                        self.watchLocations(ids: profile.friendIDs)
                    }
                }
            }
    }
    
    func stopListening() {
        incomingListener?.remove()
        incomingListener = nil
        profileListener?.remove()
        profileListener = nil
        friendListeners.forEach { $0.remove() }
        friendListeners = []
        stopWatchingLocations()
        hasLocationAccess = false
        watchedFriendIDs = nil
        profilesByID = [:]
        friends = []
        incomingRequests = []
    }
    
    func clearError() {
        errorMessage = nil
    }
    
    /// Friend locations are only listened to while the viewer is confirmed on campus.
    func setLocationAccess(_ allowed: Bool) {
        guard allowed != hasLocationAccess else { return }
        hasLocationAccess = allowed
        if allowed {
            watchLocations(ids: watchedFriendIDs ?? [])
        } else {
            stopWatchingLocations()
        }
    }
    
    // MARK: - Listeners
    
    private static func chunks(of ids: [String], size: Int) -> [[String]] {
        stride(from: 0, to: ids.count, by: size).map { Array(ids[$0..<min($0 + size, ids.count)]) }
    }
    
    private func watchFriends(ids: [String]) {
        friendListeners.forEach { $0.remove() }
        friendListeners = []
        profilesByID = [:]
        guard !ids.isEmpty else {
            friends = []
            return
        }
        
        for chunk in Self.chunks(of: ids, size: 10) {
            let listener = database.collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .addSnapshotListener { [weak self] snapshot, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let error {
                            self.errorMessage = error.localizedDescription
                            return
                        }
                        for document in snapshot?.documents ?? [] {
                            if let profile = try? document.data(as: UserProfile.self) {
                                self.profilesByID[profile.id] = profile
                            }
                        }
                        self.friends = self.profilesByID.values.sorted {
                            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                        }
                    }
                }
            friendListeners.append(listener)
        }
    }
    
    private func watchLocations(ids: [String]) {
        stopWatchingLocations()
        guard !ids.isEmpty else { return }
        
        for chunk in Self.chunks(of: ids, size: Self.locationChunkSize) {
            let listener = database.collection("liveLocations")
                .whereField(FieldPath.documentID(), in: chunk)
                .addSnapshotListener { [weak self] snapshot, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if error != nil {
                            // The rule denies this read once the viewer is off campus.
                            self.friendLocations = [:]
                            return
                        }
                        let documents = snapshot?.documents ?? []
                        let present = Set(documents.map { $0.documentID })
                        for id in chunk where !present.contains(id) {
                            self.friendLocations.removeValue(forKey: id)
                        }
                        for document in documents {
                            if let location = try? document.data(as: LiveLocation.self) {
                                self.friendLocations[location.id] = location
                            }
                        }
                    }
                }
            locationListeners.append(listener)
        }
    }
    
    private func stopWatchingLocations() {
        locationListeners.forEach { $0.remove() }
        locationListeners = []
        friendLocations = [:]
    }
    
    // MARK: - Search and requests
    
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
        
        let request = FriendRequest(
            fromUserID: currentUserID,
            fromDisplayName: fromDisplayName,
            toUserID: targetUserID,
            status: .pending
        )
        let data = try Firestore.Encoder().encode(request)
        try await database.collection(FriendRequest.collectionName).document().setData(data)
        
        await notifications.send([
            NotificationDraft(
                recipientID: targetUserID,
                kind: .friendRequest,
                title: "New friend request",
                body: "\(fromDisplayName) wants to be your friend"
            )
        ], from: currentUserID)
    }
    
    func acceptRequest(_ request: FriendRequest) async throws {
        let batch = database.batch()
        batch.updateData(
            ["friendIDs": FieldValue.arrayUnion([request.toUserID])],
            forDocument: database.collection("users").document(request.fromUserID)
        )
        batch.updateData(
            ["friendIDs": FieldValue.arrayUnion([request.fromUserID])],
            forDocument: database.collection("users").document(request.toUserID)
        )
        batch.deleteDocument(database.collection(FriendRequest.collectionName).document(request.id))
        try await batch.commit()
    }
    
    func declineRequest(_ request: FriendRequest) async throws {
        try await database.collection(FriendRequest.collectionName).document(request.id).delete()
    }
}
