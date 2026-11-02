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
    @Published private(set) var allHapps: [Happ] = []
    /// Set from ContentView (SafetyStore). Happs from blocked people, or hidden after a report, are left out.
    @Published var blockedIDs: Set<String> = []
    @Published var hiddenIDs: Set<String> = []
    
    var happs: [Happ] {
        allHapps.filter { !blockedIDs.contains($0.creatorID) && !hiddenIDs.contains($0.id) }
    }
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

                    self.allHapps = (snapshot?.documents ?? [])
                        .compactMap { try? $0.data(as: Happ.self) }
                        .sorted { $0.startTime < $1.startTime }
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        isLoading = false
        allHapps = []
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Create, update, delete

    /// `invitedIDs` get a personal invitation wherever they are. `audienceIDs` (friends on
    /// campus right now) get the broadcast "New Happ" notification.
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
        invitedIDs: [String] = [],
        audienceIDs: [String] = []
    ) async throws {
        let checked = try validated(title: title, location: location, startTime: startTime, endTime: endTime)
        try ContentFilter.validate(details, field: "details")

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

        await notifyAboutNewHapp(
            title: checked.title,
            creatorID: creatorID,
            creatorName: creatorName,
            invitedIDs: invitedIDs,
            audienceIDs: audienceIDs
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
        try ContentFilter.validate(details, field: "details")

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
        try ContentFilter.validate(cleanedTitle, field: "title")
        try ContentFilter.validate(cleanedLocation, field: "location")

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

    private func notifyAboutNewHapp(
        title: String,
        creatorID: String,
        creatorName: String,
        invitedIDs: [String],
        audienceIDs: [String]
    ) async {
        let invitations = invitedIDs.map {
            NotificationDraft(
                recipientID: $0,
                kind: .happCreated,
                title: "You're invited",
                body: "\(creatorName) invited you to \(title)"
            )
        }
        let broadcasts = audienceIDs
            .filter { !invitedIDs.contains($0) }
            .map {
                NotificationDraft(
                    recipientID: $0,
                    kind: .happCreated,
                    title: "New Happ",
                    body: "\(creatorName) created \(title)"
                )
            }
        await notifications.send(invitations + broadcasts, from: creatorID)
    }
}
