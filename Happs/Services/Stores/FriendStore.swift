//
//  FriendStore.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//

// CODE OVERVIEW
// FriendStore is the app's model/controller for everything social: the friend list, friend
// requests, live friend locations and online presence. It is an ObservableObject, so SwiftUI
// views that observe it redraw when a @Published property changes. It is @MainActor because it
// mutates published state that the UI reads, so all changes happen on the main thread.
// Data comes from Firestore snapshot listeners rather than one off reads, so the lists update
// live when a friend moves, comes online or sends a request. There is one listener per friend
// (see syncFriendListeners) so one unreadable profile cannot hide everyone else. The Firestore
// instance is injected through init (default .firestore()) so a test could pass a different one.
// Friendship changes use a batch write so both users' friendIDs update together or not at all.
import Foundation
import FirebaseFirestore
import Combine

/// Observable store for friends, friend requests, friend locations and presence.
/// Owned by the app (see ContentView) and shared with views. Call startListening after sign in
/// and stopListening on sign out so no listener outlives the session.
@MainActor
final class FriendStore: ObservableObject {
    /// Resolved profiles of the current user's friends, sorted by name. private(set) so only this
    /// store changes it and views can only read.
    @Published private(set) var friends: [UserProfile] = []
    /// Latest live location per friend ID. Only filled while the viewer has location access.
    @Published private(set) var friendLocations: [String: LiveLocation] = [:]
    /// Every pending request addressed to the user, including from blocked people.
    /// Views should use incomingRequests, which filters blocked senders out.
    @Published private(set) var allIncoming: [FriendRequest] = []
    /// Set from ContentView (SafetyStore).
    @Published var blockedIDs: Set<String> = []

    /// Pending friend requests with blocked senders removed (a computed property, so it
    /// re-evaluates whenever allIncoming or blockedIDs changes).
    var incomingRequests: [FriendRequest] {
        allIncoming.filter { !blockedIDs.contains($0.fromUserID) }
    }
    /// Last error to show in the UI. Views call clearError once they have shown it.
    @Published private(set) var errorMessage: String?
    /// Refreshed every 30 seconds so stale pins and presence drop off without a data change.
    @Published private(set) var now = Date()

    /// Injected Firestore handle. Stored so every method uses the same instance.
    private let database: Firestore
    /// Helper that writes notification documents for other users (for example a friend request alert).
    private let notifications: NotificationWriter
    /// Listener for requests sent to me.
    private var incomingListener: ListenerRegistration?
    /// Listener for my own user document, used to learn when my friendIDs list changes.
    private var profileListener: ListenerRegistration?
    /// One listener per friend's profile, keyed by friend ID.
    private var friendListeners: [String: ListenerRegistration] = [:]
    /// One listener per friend's liveLocations document, keyed by friend ID.
    private var locationListeners: [String: ListenerRegistration] = [:]
    /// Latest decoded profile for each friend. friends is rebuilt from this dictionary.
    private var profilesByID: [String: UserProfile] = [:]
    /// The friendIDs array we last synced listeners for. nil means not synced yet. Lets us ignore
    /// snapshots of my profile where friendIDs did not change (for example a status edit).
    private var watchedFriendIDs: [String]?
    /// Mirrors setLocationAccess: location listeners only run while this is true.
    private var hasLocationAccess = false
    /// Background task that updates now every 30 seconds. Cancelled in stopListening.
    private var clockTask: Task<Void, Never>?

    init(database: Firestore = .firestore()) {
        self.database = database
        self.notifications = NotificationWriter(database: database)
    }

    // MARK: - Derived state

    /// Returns the friend's location only if updatedAt is recent. missingIsFresh: true means a
    /// location with no timestamp is still shown (assumed reason: older documents may lack the field).
    /// A friend's pin, only while it is fresh.
    func location(for friendID: String) -> LiveLocation? {
        guard let location = friendLocations[friendID] else { return nil }
        let fresh = Freshness.isFresh(location.updatedAt, now: now, missingIsFresh: true)
        return fresh ? location : nil
    }

    /// A friend counts as online only if they are visible (not in Invisible Mode), marked on
    /// campus and their lastSeenAt is recent. A missing lastSeenAt counts as not fresh here.
    func isOnlineOnCampus(_ friend: UserProfile) -> Bool {
        friend.isVisible
            && friend.isOnCampus == true
            && Freshness.isFresh(friend.lastSeenAt, now: now, missingIsFresh: false)
    }

    /// Friends currently online on campus, for presence lists and badges.
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

    /// Sets now immediately. Because now is @Published, views using it re-evaluate freshness.
    func refreshClock() {
        now = Date()
    }

    // MARK: - Listening

    /// Begins live updates for this user. Safe to call again: old listeners are removed first so
    /// they are not duplicated.
    /// - Parameter userID: the signed in user's Firebase uid.
    func startListening(for userID: String) {
        incomingListener?.remove()
        profileListener?.remove()
        startClock()

        incomingListener = database.collection(FriendRequest.collectionName)
            // Server side filter: only pending requests addressed to me, so we never download others' requests.
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

        // Listening to my own user document tells us when friendIDs changes (friend added or removed).
        profileListener = database.collection("users").document(userID)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self, let snapshot,
                          let profile = UserProfile.tolerant(from: snapshot),
                          // Skip unrelated edits to my profile: only re-sync when the friend list really changed.
                          profile.friendIDs != self.watchedFriendIDs else { return }
                    self.watchedFriendIDs = profile.friendIDs
                    // tolerant(from:) is a lenient decoder (assumed reason: so one odd field does not drop the profile).
                    self.syncFriendListeners(ids: profile.friendIDs)
                }
            }
    }

    /// Detaches every listener and clears all state. Called on sign out so one account's data
    /// cannot leak into the next, and so listeners stop costing reads.
    func stopListening() {
        incomingListener?.remove()
        incomingListener = nil
        profileListener?.remove()
        profileListener = nil
        clockTask?.cancel()
        clockTask = nil
        // Array(...) copies the keys first so we are not mutating the dictionary while looping over it.
        for id in Array(friendListeners.keys) { detachFriendListener(id) }
        for id in Array(locationListeners.keys) { detachLocationListener(id) }
        hasLocationAccess = false
        watchedFriendIDs = nil
        profilesByID = [:]
        friends = []
        friendLocations = [:]
        allIncoming = []
    }

    /// Resets errorMessage after the UI has shown it.
    func clearError() {
        errorMessage = nil
    }

    /// Turns friend location listening on or off. The guard avoids redoing work when the value is
    /// unchanged. Turning it off also clears friendLocations so stale pins disappear at once.
    /// Friend locations are only listened to while the viewer is confirmed on campus.
    func setLocationAccess(_ allowed: Bool) {
        guard allowed != hasLocationAccess else { return }
        hasLocationAccess = allowed
        for id in watchedFriendIDs ?? [] { reconcileLocationListener(for: id) }
        if !allowed { friendLocations = [:] }
    }

    /// Starts the 30 second ticker. [weak self] stops the task keeping the store alive, and the
    /// loop exits when the task is cancelled.
    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                // try? so a cancelled sleep just ends the loop check instead of throwing.
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                self.now = Date()
            }
        }
    }

    // MARK: - Per-friend listeners

    /// Makes the set of friend listeners match the friend ID list: removes listeners for people
    /// no longer friends, adds listeners for new ones, then republishes the sorted list.
    /// One listener per friend, so a document that can't be read hides only that friend.
    private func syncFriendListeners(ids: [String]) {
        // Set gives fast contains checks and removes duplicate IDs.
        let wanted = Set(ids)
        for id in Array(friendListeners.keys) where !wanted.contains(id) {
            detachFriendListener(id)
            detachLocationListener(id)
            profilesByID[id] = nil
            friendLocations[id] = nil
        }
        // Only attach listeners for friends we are not already listening to.
        for id in wanted where friendListeners[id] == nil {
            attachFriendListener(id)
        }
        publishFriends()
    }

    /// Listens to one friend's user document. The snapshot closure is not guaranteed to run on
    /// the main actor, so it hops back with Task { @MainActor } before touching state.
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

    /// Starts or stops a friend's location listener so it matches the rules: only when the
    /// viewer has location access AND that friend is visible (not in Invisible Mode).
    private func reconcileLocationListener(for id: String) {
        // Invisible Mode: a friend who hides themselves is not tracked, so their pin disappears.
        let visible = profilesByID[id]?.isVisible ?? false
        if hasLocationAccess && visible {
            if locationListeners[id] == nil { attachLocationListener(id) }
        } else {
            detachLocationListener(id)
            friendLocations[id] = nil
        }
    }

    /// Listens to one friend's liveLocations document and mirrors it into friendLocations.
    /// A missing document or a decode failure removes the pin.
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

    /// Removes a friend profile listener and forgets it.
    private func detachFriendListener(_ id: String) {
        friendListeners[id]?.remove()
        friendListeners[id] = nil
    }

    /// Removes a friend location listener and forgets it.
    private func detachLocationListener(_ id: String) {
        locationListeners[id]?.remove()
        locationListeners[id] = nil
    }

    /// Rebuilds the friends array from profilesByID, sorted by name ignoring case.
    private func publishFriends() {
        friends = profilesByID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    // MARK: - Search and requests

    /// Prefix search on UserSearchEntry documents (a separate public collection, assumed so
    /// that full user profiles do not need to be readable by everyone).
    /// - Returns: up to 20 matches, excluding the current user and blocked people.
    /// - Throws: Firestore errors from the query.
    func searchUsers(matching query: String, excluding currentUserID: String) async throws -> [UserSearchEntry] {
        let key = UserSearchEntry.searchKey(for: query)
        guard !key.isEmpty else { return [] }

        let snapshot = try await database.collection(UserSearchEntry.collectionName)
            // Prefix query trick: order by the key, start at the typed text and end at the text plus the very high Unicode character, which matches everything that begins with the query.
            .order(by: "searchKey")
            .start(at: [key])
            // U+F8FF is a private-use character that sorts after normal text, so it closes the prefix range.
            .end(at: [key + "\u{f8ff}"])
            .limit(to: 20)
            .getDocuments()

        return snapshot.documents
            .compactMap { try? $0.data(as: UserSearchEntry.self) }
            // Done on the client: Firestore cannot exclude values like this in a prefix range query (assumed reason).
            .filter { $0.id != currentUserID && !blockedIDs.contains($0.id) }
    }

    /// Creates a pending friend request and notifies the target. It first checks for self
    /// requests, existing friendship, and an existing request in either direction.
    /// Request document IDs are built from both user IDs, so the same pair cannot create duplicates.
    /// - Throws: AppError.invalidForm with a message that can be shown to the user.
    func sendFriendRequest(from currentUserID: String, fromDisplayName: String, to targetUserID: String) async throws {
        guard currentUserID != targetUserID else {
            throw AppError.invalidForm("You can't friend yourself.")
        }
        guard watchedFriendIDs?.contains(targetUserID) != true else {
            throw AppError.invalidForm("You're already friends.")
        }

        let requests = database.collection(FriendRequest.collectionName)
        // Deterministic document IDs (from + to) make duplicates detectable with a simple document lookup.
        let outgoing = requests.document(FriendRequest.documentID(from: currentUserID, to: targetUserID))
        let incoming = requests.document(FriendRequest.documentID(from: targetUserID, to: currentUserID))

        do {
            if try await outgoing.getDocument().exists {
                throw AppError.invalidForm("Friend request already sent.")
            }
            if try await incoming.getDocument().exists {
                throw AppError.invalidForm("They already sent you a request. Accept it under Requests.")
            }
        // Re-throw our own friendly errors unchanged, and wrap any other error (for example network) in a readable one.
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
            // Encode the Codable struct to a Firestore dictionary, then write with a fixed ID using setData.
            let data = try Firestore.Encoder().encode(request)
            try await outgoing.setData(data)
        } catch {
            throw AppError.invalidForm("Couldn't send the request: \(error.localizedDescription)")
        }

        // Notification failure is not thrown here (send is not marked throws), so the request itself still counts as sent.
        await notifications.send([
            NotificationDraft(
                recipientID: targetUserID,
                kind: .friendRequest,
                title: "New friend request",
                body: "\(fromDisplayName) wants to be your friend"
            )
        ], from: currentUserID)
    }

    /// Accepts a request with one batch: add each user to the other's friendIDs (arrayUnion adds
    /// without duplicates and without reading first) and delete the request. A batch is atomic,
    /// so the friendship is never half created.
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

    /// Declines by deleting the request document.
    func declineRequest(_ request: FriendRequest) async throws {
        try await database.collection(FriendRequest.collectionName).document(request.id).delete()
    }

    /// One batch with arrayRemove on both users' documents, so removal is atomic.
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
