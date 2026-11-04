//
//  ProfileStore.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//

//  CODE OVERVIEW
//  -------------
//  Holds the signed-in user's own profile document (users/{uid}) and writes changes to it.
//  ObservableObject store used by the Me tab and any view that needs the current status, visibility or
//  avatar. A Firestore snapshot listener keeps `profile` live, so edits made from another device or by
//  a Cloud Function show up without a manual refresh. @MainActor keeps all published changes on the main thread.
//  Writes use updateData with only the changed field, and FieldValue.serverTimestamp() / FieldValue.delete()
//  so the server decides the time and field removal.
//
import Foundation
import FirebaseFirestore
import Combine

/// Live copy of the signed-in user's profile document, shared with views as an ObservableObject.
@MainActor
final class ProfileStore: ObservableObject {
    /// The current user's profile (nil when signed out). private(set): only this store changes it.
    @Published private(set) var profile: UserProfile?

    /// Injected Firestore instance (defaults to the shared one).
    private let database: Firestore
    /// Live query handle, removed on sign-out or when restarting for another user.
    private var listener: ListenerRegistration?

    /// - Parameter database: Firestore instance to use.
    init(database: Firestore = .firestore()) {
        self.database = database
    }

    /// Attaches a snapshot listener to users/{userID}. Any earlier listener is removed first, so calling
    /// this again (for example after account switch) never leaves two listeners running.
    func startListening(userID: String) {
        listener?.remove()
        listener = database.collection("users").document(userID)
            // [weak self] avoids a retain cycle; the callback hops to the main actor before touching state.
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        #if DEBUG
                        print("Profile listener error: \(error)")
                        #endif
                        return
                    }
                    // `tolerant(from:)` is a decoding helper on UserProfile that returns nil when the document cannot be read
                    // (assumed reason: older documents may lack some fields).
                    guard let snapshot, let latest = UserProfile.tolerant(from: snapshot) else { return }
                    // Only publish what the UI shows, so heartbeat writes don't redraw the profile.
                    if self.differs(latest) { self.profile = latest }
                }
            }
    }

    /// Removes the listener and clears the profile (called on sign-out).
    func stopListening() {
        listener?.remove()
        listener = nil
        profile = nil
    }

    /// Sets the user's status. statusUpdatedAt uses a server timestamp so every device agrees on the time.
    /// - Throws: any Firestore error, so the caller can show it.
    func updateStatus(_ status: UserStatus, for userID: String) async throws {
        try await database.collection("users").document(userID).updateData([
            "status": status.rawValue,
            "statusUpdatedAt": FieldValue.serverTimestamp()
        ])
    }

    /// Turns the user's map visibility on or off.
    func setVisible(_ isVisible: Bool, for userID: String) async throws {
        try await database.collection("users").document(userID).updateData(["isVisible": isVisible])
    }

    /// Saves the chosen SF Symbol name used as the symbol avatar.
    func updateAvatar(_ symbol: String, for userID: String) async throws {
        try await database.collection("users").document(userID).updateData(["avatarSymbol": symbol])
    }

    /// Saves the processed JPEG bytes directly in the user document (so no separate file storage is used for avatars).
    func setAvatarPhoto(_ jpeg: Data, for userID: String) async throws {
        try await database.collection("users").document(userID).updateData(["avatarPhoto": jpeg])
    }

    /// Deletes the avatarPhoto field entirely (FieldValue.delete) rather than writing empty data.
    func removeAvatarPhoto(for userID: String) async throws {
        try await database.collection("users").document(userID).updateData(["avatarPhoto": FieldValue.delete()])
    }

    /// True when something the UI shows has changed. Compares only status, visibility and avatar fields,
    /// so the frequent background writes to the document (such as a heartbeat) do not republish and redraw views.
    private func differs(_ latest: UserProfile) -> Bool {
        guard let current = profile else { return true }
        return latest.status != current.status
            || latest.isVisible != current.isVisible
            || latest.avatarSymbol != current.avatarSymbol
            || latest.avatarPhoto != current.avatarPhoto
    }
}
