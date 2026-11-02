//
//  ProfileStore.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profile: UserProfile?

    private let database: Firestore
    private var listener: ListenerRegistration?

    init(database: Firestore = .firestore()) {
        self.database = database
    }

    func startListening(userID: String) {
        listener?.remove()
        listener = database.collection("users").document(userID)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        #if DEBUG
                        print("Profile listener error: \(error)")
                        #endif
                        return
                    }
                    guard let snapshot, let latest = UserProfile.tolerant(from: snapshot) else { return }
                    // Only publish what the UI shows, so heartbeat writes don't redraw the profile.
                    if self.differs(latest) { self.profile = latest }
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        profile = nil
    }

    func updateStatus(_ status: UserStatus, for userID: String) async throws {
        try await database.collection("users").document(userID).updateData([
            "status": status.rawValue,
            "statusUpdatedAt": FieldValue.serverTimestamp()
        ])
    }

    func setVisible(_ isVisible: Bool, for userID: String) async throws {
        try await database.collection("users").document(userID).updateData(["isVisible": isVisible])
    }

    func updateAvatar(_ symbol: String, for userID: String) async throws {
        try await database.collection("users").document(userID).updateData(["avatarSymbol": symbol])
    }

    func setAvatarPhoto(_ jpeg: Data, for userID: String) async throws {
        try await database.collection("users").document(userID).updateData(["avatarPhoto": jpeg])
    }

    func removeAvatarPhoto(for userID: String) async throws {
        try await database.collection("users").document(userID).updateData(["avatarPhoto": FieldValue.delete()])
    }

    private func differs(_ latest: UserProfile) -> Bool {
        guard let current = profile else { return true }
        return latest.status != current.status
            || latest.isVisible != current.isVisible
            || latest.avatarSymbol != current.avatarSymbol
            || latest.avatarPhoto != current.avatarPhoto
    }
}
