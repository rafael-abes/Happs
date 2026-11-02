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
    @Published private(set) var allIncoming: [FriendRequest] = []
    /// Set from ContentView (SafetyStore).
    @Published var blockedIDs: Set<String> = []

    var incomingRequests: [FriendRequest] {
        allIncoming.filter { !blockedIDs.contains($0.fromUserID) }
    }
    @Published private(set) var errorMessage: String?
    /// Refreshed every 30 seconds so stale pins and presence drop off without a data change.
    @Published private(set) var now = Date()

    private let database: Firestore
    private let notifications: NotificationWriter
    private var incomingListener: ListenerRegistration?
    private var profileListener: ListenerRegistration?
    private var friendListeners: [String: ListenerRegistration] = [:]
    private var locationListeners: [String: ListenerRegistration] = [:]
    private var profilesByID: [String: UserProfile] = [:]
    private var watchedFriendIDs: [String]?
    private var hasLocationAccess = false
    private var clockTask: Task<Void, Never>?

    init(database: Firestore = .firestore()) {
        self.database = database
        self.notifications = NotificationWriter(database: database)
    }

    // MARK: - Derived state

    /// A friend's pin, only while it is fresh.
    func location(for friendID: String) -> LiveLocation? {
        guard let location = friendLocations[friendID] else { return nil }
        let fresh = Freshness.isFresh(location.updatedAt, now: now, missingIsFresh: true)
        return fresh ? location : nil
    }

    func isOnlineOnCampus(_ friend: UserProfile) -> Bool {
        friend.isVisible
            && friend.isOnCampus == true
            && Freshness.isFresh(friend.lastSeenAt, now: now, missingIsFresh: false)
    }

    var onlineFriends: [UserProfile] {
        friends.filter { isOnlineOnCampus($0) }
    }

    /// Friends on campus right now, ignoring Invisible Mode. Used to pick who gets a
    /// broadcast notification, since invisibility hides you from others, not them from you.
    var onCampusFriendIDs: [String] {
        let moment = Date()
        return friends
            .filter { (friend: UserProfile) -> Bool in
                friend.isOnCampus == true
                    && Freshness.isFresh(friend.lastSeenAt, now: moment, missingIsFresh: false)
            }
            .map(\.id)
    }

    func refreshClock() {
        now = Date()
    }

    // MARK: - Listening

    func startListening(for userID: String) {
        incomingListener?.remove()
        profileListener?.remove()
        startClock()

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
                    self.allIncoming = (snapshot?.documents ?? [])
                        .compactMap { try? $0.data(as: FriendRequest.self) }
                }
            }

        profileListener = database.collection("users").document(userID)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self, let snapshot,
                          let profile = UserProfile.tolerant(from: snapshot),
                          profile.friendIDs != self.watchedFriendIDs else { return }
                    self.watchedFriendIDs = profile.friendIDs
                    self.syncFriendListeners(ids: profile.friendIDs)
                }
            }
    }

    func stopListening() {
        incomingListener?.remove()
        incomingListener = nil
        profileListener?.remove()
        profileListener = nil
        clockTask?.cancel()
        clockTask = nil
        for id in Array(friendListeners.keys) { detachFriendListener(id) }
        for id in Array(locationListeners.keys) { detachLocationListener(id) }
        hasLocationAccess = false
        watchedFriendIDs = nil
        profilesByID = [:]
        friends = []
        friendLocations = [:]
        allIncoming = []
    }

    func clearError() {
        errorMessage = nil
    }

    /// Friend locations are only listened to while the viewer is confirmed on campus.
    func setLocationAccess(_ allowed: Bool) {
        guard allowed != hasLocationAccess else { return }
        hasLocationAccess = allowed
        for id in watchedFriendIDs ?? [] { reconcileLocationListener(for: id) }
        if !allowed { friendLocations = [:] }
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                self.now = Date()
            }
        }
    }

    // MARK: - Per-friend listeners

    /// One listener per friend, so a document that can't be read hides only that friend.
    private func syncFriendListeners(ids: [String]) {
        let wanted = Set(ids)
        for id in Array(friendListeners.keys) where !wanted.contains(id) {
            detachFriendListener(id)
            detachLocationListener(id)
            profilesByID[id] = nil
            friendLocations[id] = nil
        }
        for id in wanted where friendListeners[id] == nil {
            attachFriendListener(id)
        }
        publishFriends()
    }

    private func attachFriendListener(_ id: String) {
        friendListeners[id] = database.collection("users").document(id)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        #if DEBUG
                        print("Can't read friend \(id): \(error.localizedDescription)")
                        #endif
                        // A failed listener is finished. Clearing it lets the next sync retry.
                        self.detachFriendListener(id)
                        self.profilesByID[id] = nil
                    } else if let snapshot, let profile = UserProfile.tolerant(from: snapshot) {
                        self.profilesByID[id] = profile
                    } else {
                        self.profilesByID[id] = nil
                    }
                    self.publishFriends()
                    self.reconcileLocationListener(for: id)
                }
            }
    }

    private func reconcileLocationListener(for id: String) {
        let visible = profilesByID[id]?.isVisible ?? false
        if hasLocationAccess && visible {
            if locationListeners[id] == nil { attachLocationListener(id) }
        } else {
            detachLocationListener(id)
            friendLocations[id] = nil
        }
    }

    private func attachLocationListener(_ id: String) {
        locationListeners[id] = database.collection("liveLocations").document(id)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        #if DEBUG
                        print("Can't read location of \(id): \(error.localizedDescription)")
                        #endif
                        self.detachLocationListener(id)
                        self.friendLocations[id] = nil
                        return
                    }
                    if let snapshot, snapshot.exists,
                       let location = try? snapshot.data(as: LiveLocation.self) {
                        self.friendLocations[id] = location
                    } else {
                        self.friendLocations[id] = nil
                    }
                }
            }
    }

    private func detachFriendListener(_ id: String) {
        friendListeners[id]?.remove()
        friendListeners[id] = nil
    }

    private func detachLocationListener(_ id: String) {
        locationListeners[id]?.remove()
        locationListeners[id] = nil
    }

    private func publishFriends() {
        friends = profilesByID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    // MARK: - Search and requests

    func searchUsers(matching query: String, excluding currentUserID: String) async throws -> [UserSearchEntry] {
        let key = UserSearchEntry.searchKey(for: query)
        guard !key.isEmpty else { return [] }

        let snapshot = try await database.collection(UserSearchEntry.collectionName)
            .order(by: "searchKey")
            .start(at: [key])
            .end(at: [key + "\u{f8ff}"])
            .limit(to: 20)
            .getDocuments()

        return snapshot.documents
            .compactMap { try? $0.data(as: UserSearchEntry.self) }
            .filter { $0.id != currentUserID && !blockedIDs.contains($0.id) }
    }

    func sendFriendRequest(from currentUserID: String, fromDisplayName: String, to targetUserID: String) async throws {
        guard currentUserID != targetUserID else {
            throw AppError.invalidForm("You can't friend yourself.")
        }
        guard watchedFriendIDs?.contains(targetUserID) != true else {
            throw AppError.invalidForm("You're already friends.")
        }

        let requests = database.collection(FriendRequest.collectionName)
        let outgoing = requests.document(FriendRequest.documentID(from: currentUserID, to: targetUserID))
        let incoming = requests.document(FriendRequest.documentID(from: targetUserID, to: currentUserID))

        do {
            if try await outgoing.getDocument().exists {
                throw AppError.invalidForm("Friend request already sent.")
            }
            if try await incoming.getDocument().exists {
                throw AppError.invalidForm("They already sent you a request. Accept it under Requests.")
            }
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.invalidForm("Couldn't check for an existing request: \(error.localizedDescription)")
        }

        let request = FriendRequest(
            fromUserID: currentUserID,
            fromDisplayName: fromDisplayName,
            toUserID: targetUserID,
            status: .pending
        )
        do {
            let data = try Firestore.Encoder().encode(request)
            try await outgoing.setData(data)
        } catch {
            throw AppError.invalidForm("Couldn't send the request: \(error.localizedDescription)")
        }

        await notifications.send([
            NotificationDraft(
                recipientID: targetUserID,
                kind: .friendRequest,
                title: "New friend request",
                body: "\(fromDisplayName) wants to be your friend"
            )
        ], from: currentUserID)
    }

    /// The security rules check that this request exists before letting the acceptor
    /// add themselves to the sender's friend list.
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

    /// Removes the friendship from both sides. Each person may only remove themselves
    /// from the other's list, which is exactly what the rules allow.
    func removeFriend(_ friendID: String, currentUserID: String) async {
        let batch = database.batch()
        batch.updateData(
            ["friendIDs": FieldValue.arrayRemove([friendID])],
            forDocument: database.collection("users").document(currentUserID)
        )
        batch.updateData(
            ["friendIDs": FieldValue.arrayRemove([currentUserID])],
            forDocument: database.collection("users").document(friendID)
        )
        do {
            try await batch.commit()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
