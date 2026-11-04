//
//  HappStore.swift
//  Happs
//
//  Created by Rafa Abes on 9/22/26.
//

// CODE OVERVIEW
// HappStore is the store for Happs (campus events): it listens to the happs collection and
// handles create, update, delete, join and leave. It is an ObservableObject so SwiftUI views
// redraw on change, and @MainActor because views read its published state. A single Firestore
// snapshot listener keeps list, map and detail screens in sync live. Blocked and reported
// Happs are filtered in the computed `happs` property, so every screen gets the filtered list
// for free. Input validation and content filtering are done here, not in the views, so no
// screen can skip them. Notifications to other users are sent through NotificationWriter after
// the main write succeeds. Firestore is injected through init.
import Foundation
import FirebaseFirestore
import Combine

/// Observable store for Happs. Created once and shared with views.
@MainActor
final class HappStore: ObservableObject {
    /// Every Happ from Firestore, sorted by start time, before any blocking or hiding.
    @Published private(set) var allHapps: [Happ] = []
    /// IDs of users the viewer blocked (filters by creator).
    /// Set from ContentView (SafetyStore). Happs from blocked people, or hidden after a report, are left out.
    @Published var blockedIDs: Set<String> = []
    /// IDs of Happs the viewer reported and chose to hide (filters by Happ ID).
    @Published var hiddenIDs: Set<String> = []
    
    /// The Happs views should show: allHapps without blocked creators or hidden Happs.
    /// A computed property, so it recalculates when allHapps, blockedIDs or hiddenIDs changes.
    var happs: [Happ] {
        allHapps.filter { !blockedIDs.contains($0.creatorID) && !hiddenIDs.contains($0.id) }
    }
    /// True from startListening until the first snapshot arrives, for a loading indicator.
    @Published private(set) var isLoading = false
    /// Last error to show in the UI. Cleared by clearError.
    @Published private(set) var errorMessage: String?

    /// Injected Firestore handle.
    private let database: Firestore
    /// Helper that writes notification documents for other users.
    private let notifications: NotificationWriter
    /// The live listener on the happs collection. nil when not listening.
    private var listener: ListenerRegistration?

    init(database: Firestore = .firestore()) {
        self.database = database
        self.notifications = NotificationWriter(database: database)
    }

    /// Starts one snapshot listener on the whole collection. The guard prevents a second one.
    /// All filtering and sorting is done on the client.
    func startListening() {
        guard listener == nil else { return }
        isLoading = true

        // addSnapshotListener fires once with current data and again on every change, so the UI stays live.
        listener = database.collection(Happ.collectionName)
            .addSnapshotListener { [weak self] snapshot, error in
                // The listener closure is not guaranteed to run on the main actor, so hop back before changing published state. [weak self] avoids a retain cycle.
                Task { @MainActor in
                    guard let self else { return }
                    // The first callback (data or error) means loading is over.
                    self.isLoading = false

                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }

                    self.allHapps = (snapshot?.documents ?? [])
                        // Decode each document into a Happ. try? drops documents that fail to decode instead of failing everything.
                        .compactMap { try? $0.data(as: Happ.self) }
                        .sorted { $0.startTime < $1.startTime }
                }
            }
    }

    /// Removes the listener and clears the data (called on sign out).
    func stopListening() {
        listener?.remove()
        listener = nil
        isLoading = false
        allHapps = []
    }

    /// Resets errorMessage once shown.
    func clearError() {
        errorMessage = nil
    }

    // MARK: - Create, update, delete

    /// Validates, saves and announces a new Happ. The creator is automatically the first participant.
    /// The end time defaults to startTime plus Happ.defaultDuration for the check that it is not already
    /// over. Latitude and longitude are optional (a Happ may have no map pin).
    /// - Throws: AppError.invalidForm for bad input, or a Firestore error from the write.
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

        // A Happ with no end time is treated as lasting the default duration.
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
            // Stored as true or left out (nil), so most documents do not carry the field.
            isOffCampus: isOffCampus ? true : nil,
            invitedIDs: invitedIDs.isEmpty ? nil : invitedIDs
        )

        // Encode the Codable Happ into a Firestore dictionary. document() with no ID lets Firestore make a unique ID.
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

    /// Validates and edits an existing Happ with updateData, which changes only the listed fields
    /// (unlike setData, which would replace the document). Then notifies the other participants.
    /// - Throws: AppError.invalidForm or a Firestore error.
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

        // Build a dictionary of only the fields that may change. Timestamp(date:) converts Date to Firestore timestamp.
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
            // FieldValue.delete() removes the field from the document, which is how an optional value is cleared with updateData.
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

    /// Deletes a Happ and notifies everyone except the creator that it was cancelled.
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

    /// Joins or leaves a Happ. If the creator leaves, the Happ is deleted instead. Otherwise
    /// participantIDs is changed with arrayUnion or arrayRemove (atomic server side edits that need
    /// no read first) and the creator is notified.
    /// - Parameter isJoining: true to join, false to leave.
    func toggleParticipation(happID: String, userID: String, isJoining: Bool) async throws {
        // Looked up in the filtered list first, to find the creator and title for the checks and notification.
        let currentHapp = happs.first { $0.id == happID }

        // A Happ with no host is meaningless, so the creator leaving deletes it.
        if !isJoining, let host = currentHapp, host.creatorID == userID {
            try await deleteHapp(host)
            return
        }

        // No transaction needed: arrayUnion and arrayRemove are applied by the server and are safe if two people join at once.
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

    /// Trims and checks title, location and times. Returns the cleaned title and location as a
    /// named tuple.
    /// - Throws: AppError.invalidForm (or the ContentFilter error) when a rule fails.
    private func validated(
        title: String,
        location: String,
        startTime: Date,
        endTime: Date?
    ) throws -> (title: String, location: String) {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        // Content filter first (App Review moderation rule) then the empty and length checks.
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

    /// Sends personal invitations to invited users, and a broadcast notice to the audience.
    /// People who are invited are removed from the audience so nobody gets two notifications.
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
