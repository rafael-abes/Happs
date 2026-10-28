//
//  Recaps.swift
//  Happs
//
//  Created by Rafa Abes on 10/27/26.
//
import Foundation
import FirebaseFirestore

/// A full recap photo. Lives in happs/{happID}/recaps/{uid}_{slot}. Attendees only.
nonisolated struct Recap: Identifiable, Equatable {
    let id: String
    let happID: String
    let authorID: String
    let authorName: String
    let storagePath: String
    let caption: String
    let createdAt: Date

    init?(id: String, happID: String, data: [String: Any]) {
        guard let authorID = data["authorID"] as? String,
              let path = data["storagePath"] as? String else { return nil }
        self.id = id
        self.happID = happID
        self.authorID = authorID
        self.authorName = data["authorName"] as? String ?? "Someone"
        self.storagePath = path
        self.caption = data["caption"] as? String ?? ""
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
    }

    /// Unguessable path inside the private bucket: {happID}/{uid}/{random}.jpg
    static func makePath(happID: String, userID: String, unique: UUID = UUID()) -> String {
        "\(happID)/\(userID)/\(unique.uuidString.lowercased()).jpg"
    }
}

/// The tiny blurred preview. Lives in happs/{happID}/recapPreviews/{uid}_{slot}.
/// Readable by any signed-in user, so it holds no path and no real photo.
nonisolated struct RecapPreview: Identifiable, Equatable {
    let id: String
    let happID: String
    let authorID: String
    let imageData: Data?
    let createdAt: Date

    init?(id: String, happID: String, data: [String: Any]) {
        guard let authorID = data["authorID"] as? String else { return nil }
        self.id = id
        self.happID = happID
        self.authorID = authorID
        self.imageData = data["imageData"] as? Data
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
    }
}

/// Window and slot rules. The same numbers are enforced by the Firestore rules.
nonisolated enum RecapRules {
    static let windowHours = 24
    static let maxPhotosPerPerson = 3

    static func windowCloses(endsAt: Date) -> Date {
        endsAt.addingTimeInterval(Double(windowHours) * 3600)
    }

    static func isWindowOpen(endsAt: Date, now: Date) -> Bool {
        now >= endsAt && now < windowCloses(endsAt: endsAt)
    }

    static func slotID(userID: String, slot: Int) -> String {
        "\(userID)_\(slot)"
    }

    /// Slots 1...max that this user has not used yet.
    static func freeSlots(userID: String, existingIDs: [String]) -> [Int] {
        (1...maxPhotosPerPerson).filter { !existingIDs.contains(slotID(userID: userID, slot: $0)) }
    }
}

enum RecapError: LocalizedError {
    case notConfigured
    case tooMany
    case badImage

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Photo storage isn't set up yet. Add the Supabase keys to Secrets.swift."
        case .tooMany: return "You can add up to \(RecapRules.maxPhotosPerPerson) photos per Happ."
        case .badImage: return "Couldn't load that photo."
        }
    }

    /// Friendly text for any error thrown while posting or loading.
    static func message(for error: Error) -> String {
        if let known = error as? RecapError { return known.errorDescription ?? "Something went wrong." }
        let text = (String(describing: error) + " " + error.localizedDescription).lowercased()
        if text.contains("row-level security") || text.contains("row level security") || text.contains("unauthorized") {
            return "Not allowed to upload this photo. Check the recap window and try again."
        }
        if text.contains("jwt") || text.contains("token") {
            return "Couldn't verify your sign-in with photo storage. Sign out and back in."
        }
        if text.contains("offline") || text.contains("internet") || text.contains("network") {
            return "You seem to be offline. Try again when you're connected."
        }
        if text.contains("permission") {
            return "The recap window may have closed, or you didn't join this Happ."
        }
        return "Something went wrong. Try again."
    }
}

