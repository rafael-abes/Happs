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
    private let notifications: NotificationWriter
    private var listener: ListenerRegistration?
    
    init(database: Firestore = .firestore()) {
        self.database = database
        self.notifications = NotificationWriter(database: database)
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
                    
                    self.happs = (snapshot?.documents ?? [])
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
    
    // MARK: - Create, update, delete
    
    func createHapp(
        title: String,
        details: String,
        location: String,
        category: HappCategory,
        startTime: Date,
        endTime: Date?,
        creatorID: String,
        creatorName: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        isOffCampus: Bool = false,
        invitedIDs: [String] = []
    ) async throws {
        let checked = try validated(title: title, location: location, startTime: startTime, endTime: endTime)
        
        let effectiveEnd = endTime ?? startTime.addingTimeInterval(Happ.defaultDuration)
        guard effectiveEnd > Date() else {
            throw AppError.invalidForm("That time has already passed.")
        }
        
        let happ = Happ(
            title: checked.title,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            location: checked.location,
            category: category,
            participantIDs: [creatorID],
            creatorID: creatorID,
            creatorName: creatorName,
            startTime: startTime,
            endTime: endTime,
            latitude: latitude,
            longitude: longitude,
            isOffCampus: isOffCampus ? true : nil,
            invitedIDs: invitedIDs.isEmpty ? nil : invitedIDs
        )
        
        let data = try Firestore.Encoder().encode(happ)
        try await database.collection(Happ.collectionName).document().setData(data)
        
        await notifyFriendsOfNewHapp(
            title: checked.title,
            creatorID: creatorID,
            creatorName: creatorName,
            invitedIDs: invitedIDs
        )
    }
    
    func updateHapp(
        _ happ: Happ,
        title: String,
        details: String,
        location: String,
        category: HappCategory,
        startTime: Date,
        endTime: Date?,
        latitude: Double?,
        longitude: Double?,
        isOffCampus: Bool
    ) async throws {
        let checked = try validated(title: title, location: location, startTime: startTime, endTime: endTime)
        
        var fields: [String: Any] = [
            "title": checked.title,
            "details": details.trimmingCharacters(in: .whitespacesAndNewlines),
            "location": checked.location,
            "category": category.rawValue,
            "startTime": Timestamp(date: startTime),
            "isOffCampus": isOffCampus
        ]
        if let endTime {
            fields["endTime"] = Timestamp(date: endTime)
        } else {
            fields["endTime"] = FieldValue.delete()
        }
        if let latitude, let longitude {
            fields["latitude"] = latitude
            fields["longitude"] = longitude
        } else {
            fields["latitude"] = FieldValue.delete()
            fields["longitude"] = FieldValue.delete()
        }
        
        try await database.collection(Happ.collectionName).document(happ.id).updateData(fields)
        
        let others = happ.participantIDs.filter { $0 != happ.creatorID }
        let drafts = others.map {
            NotificationDraft(
                recipientID: $0,
                kind: .happUpdated,
                title: "Happ updated",
                body: "\(happ.creatorName) updated \(checked.title)"
            )
        }
        await notifications.send(drafts, from: happ.creatorID)
    }
    
    func deleteHapp(_ happ: Happ) async throws {
        try await database.collection(Happ.collectionName).document(happ.id).delete()
        
        let others = happ.participantIDs.filter { $0 != happ.creatorID }
        let drafts = others.map {
            NotificationDraft(
                recipientID: $0,
                kind: .happCancelled,
                title: "Happ cancelled",
                body: "\(happ.creatorName) cancelled \(happ.title)"
            )
        }
        await notifications.send(drafts, from: happ.creatorID)
    }
    
    // MARK: - Joining and leaving
    
    func toggleParticipation(happID: String, userID: String, isJoining: Bool) async throws {
        let currentHapp = happs.first { $0.id == happID }
        
        // A Happ with no host is meaningless, so the creator leaving deletes it.
        if !isJoining, let host = currentHapp, host.creatorID == userID {
            try await deleteHapp(host)
            return
        }
        
        let reference = database.collection(Happ.collectionName).document(happID)
        let update: [String: Any] = [
            "participantIDs": isJoining ? FieldValue.arrayUnion([userID]) : FieldValue.arrayRemove([userID])
        ]
        try await reference.updateData(update)
        
        guard let happ = currentHapp else { return }
        let name = NotificationWriter.actorName
        let draft = NotificationDraft(
            recipientID: happ.creatorID,
            kind: isJoining ? .happJoined : .happLeft,
            title: isJoining ? "New attendee" : "Someone left",
            body: isJoining ? "\(name) joined \(happ.title)" : "\(name) left \(happ.title)"
        )
        await notifications.send([draft], from: userID)
    }
    
    // MARK: - Helpers
    
    private func validated(
        title: String,
        location: String,
        startTime: Date,
        endTime: Date?
    ) throws -> (title: String, location: String) {
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
        if let endTime, endTime <= startTime {
            throw AppError.invalidForm("The end time must be after the start time.")
        }
        return (cleanedTitle, cleanedLocation)
    }
    
    /// Friends on campus get the broadcast. Direct group invitations always go out,
    /// because they are personal and the invitee may be heading in.
    private func notifyFriendsOfNewHapp(title: String, creatorID: String, creatorName: String, invitedIDs: [String]) async {
        let snapshot = try? await database.collection("users").document(creatorID).getDocument()
        let friendIDs = snapshot?.get("friendIDs") as? [String] ?? []
        guard !friendIDs.isEmpty else { return }
        
        let onCampusIDs = await friendsOnCampus(among: friendIDs)
        
        var drafts: [NotificationDraft] = []
        for friendID in friendIDs {
            if invitedIDs.contains(friendID) {
                drafts.append(NotificationDraft(
                    recipientID: friendID,
                    kind: .happCreated,
                    title: "You're invited",
                    body: "\(creatorName) invited you to \(title)"
                ))
            } else if onCampusIDs.contains(friendID) {
                drafts.append(NotificationDraft(
                    recipientID: friendID,
                    kind: .happCreated,
                    title: "New Happ",
                    body: "\(creatorName) created \(title)"
                ))
            }
        }
        await notifications.send(drafts, from: creatorID)
    }
    
    /// Invisible Mode doesn't matter here: it hides you from others, not others from you.
    private func friendsOnCampus(among ids: [String]) async -> Set<String> {
        var found = Set<String>()
        for start in stride(from: 0, to: ids.count, by: 10) {
            let chunk = Array(ids[start..<min(start + 10, ids.count)])
            guard let snapshot = try? await database.collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments() else { continue }
            for document in snapshot.documents where (document.get("isOnCampus") as? Bool) == true {
                found.insert(document.documentID)
            }
        }
        return found
    }
}
