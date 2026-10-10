//
//  HappStore.swift
//  Happs
//
//  Created by Rafa Abes on 9/22/26.
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
final class HappStore: ObservableObject {
    @Published private(set) var happs: [Happ] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    
    private let database: Firestore
    private var listener: ListenerRegistration?
    
    init(database: Firestore = .firestore()) {
        self.database = database
    }
    
    func startListening() {
        guard listener == nil else { return }
        isLoading = true
        
        listener = database.collection(Happ.collectionName)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isLoading = false
                    
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    
                    let documents = snapshot?.documents ?? []
                    self.happs = documents
                        .compactMap { try? $0.data(as: Happ.self) }
                        .sorted { $0.startTime < $1.startTime }
                }
            }
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
        isLoading = false
        happs = []
    }
    
    func clearError() {
        errorMessage = nil
    }
    
    func createHapp(
        title: String,
        details: String,
        location: String,
        category: HappCategory,
        startTime: Date,
        creatorID: String,
        creatorName: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        invitedIDs: [String] = []
    ) async throws {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanedTitle.isEmpty else {
            throw AppError.invalidForm("Give your happ a title.")
        }
        guard !cleanedLocation.isEmpty else {
            throw AppError.invalidForm("Add a location.")
        }
        guard cleanedTitle.count <= 80 else {
            throw AppError.invalidForm("The title must be 80 characters or fewer.")
        }
        
        let happ = Happ(
            title: cleanedTitle,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            location: cleanedLocation,
            category: category,
            participantIDs: [creatorID],
            creatorID: creatorID,
            creatorName: creatorName,
            startTime: startTime,
            latitude: latitude,
            longitude: longitude,
            invitedIDs: invitedIDs.isEmpty ? nil : invitedIDs
        )
        
        let data = try Firestore.Encoder().encode(happ)
        let reference = database.collection(Happ.collectionName).document()
        try await reference.setData(data)
    }
    
    func toggleParticipation(happID: String, userID: String, isJoining: Bool) async throws {
        let reference = database.collection(Happ.collectionName).document(happID)
        let update: [String: Any] = [
            "participantIDs": isJoining ? FieldValue.arrayUnion([userID]) : FieldValue.arrayRemove([userID])
        ]
        try await reference.updateData(update)
    }
}
