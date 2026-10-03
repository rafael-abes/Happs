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
                    do {
                        let newProfile = try snapshot?.data(as: UserProfile.self)
                        guard newProfile?.status != self.profile?.status
                            || newProfile?.isVisible != self.profile?.isVisible
                            || self.profile == nil else { return }
                        self.profile = newProfile
                    } catch {
                        #if DEBUG
                        print("Failed to decode profile: \(error)")
                        #endif
                    }
                }
            }
    }
    
    func stopListening() {
        listener?.remove(); listener = nil; profile = nil
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
}
