//
//  Recaps.swift
//  Happs
//
//  Created by Rafa Abes on 10/27/26.
//
//  CODE OVERVIEW
//  -------------
//  Models and rules for "recaps": photos people share after a Happ. A Recap is the real photo record
//  (only a storage path, the image itself lives in private Supabase storage). A RecapPreview is a tiny
//  blurred image stored in Firestore that anyone signed in can see, used as the teaser for the FOMO
//  feature. RecapRules holds the shared numbers (24 hour window, 3 photos each) and RecapError turns
//  failures into friendly text. RecapStore reads and writes these. The types are built by hand from
//  dictionaries (init?) instead of Codable, so a malformed document returns nil and is skipped
//  rather than crashing. They are nonisolated so they can be created off the main actor.
//
import Foundation
import FirebaseFirestore

/// A full recap photo. Lives in happs/{happID}/recaps/{uid}_{slot}. Attendees only.
nonisolated struct Recap: Identifiable, Equatable {
    let id: String
    let happID: String
    let authorID: String
    let authorName: String
    /// Location of the image file in the storage bucket (not a URL).
    let storagePath: String
    let caption: String
    let createdAt: Date

    /// Failable: returns nil if required fields are missing. Optional fields get defaults.
    init?(id: String, happID: String, data: [String: Any]) {
        guard let authorID = data["authorID"] as? String,
              let path = data["storagePath"] as? String else { return nil }
        self.id = id
        self.happID = happID
        self.authorID = authorID
        self.authorName = data["authorName"] as? String ?? "Someone"
        self.storagePath = path
        self.caption = data["caption"] as? String ?? ""
        // Firestore stores dates as Timestamp; convert, falling back to now if still pending a server value.
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
    }

    /// Unguessable path inside the private bucket: {happID}/{uid}/{random}.jpg
    /// The random UUID makes the path impossible to guess; unique is a parameter so tests can fix it.
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
    /// Small JPEG bytes stored directly in the Firestore document.
    let imageData: Data?
    let createdAt: Date

    init?(id: String, happID: String, data: [String: Any]) {
        // Only authorID is required; a preview without image data is still valid.
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
    /// How long after a Happ ends people can still post photos.
    static let windowHours = 24
    /// Photos allowed per person per Happ (also the number of slots).
    static let maxPhotosPerPerson = 3

    /// The moment the posting window ends.
    static func windowCloses(endsAt: Date) -> Date {
        endsAt.addingTimeInterval(Double(windowHours) * 3600)
    }

    /// Open from the Happ's end time until windowHours later. Takes now as a parameter so it is a pure, testable function.
    static func isWindowOpen(endsAt: Date, now: Date) -> Bool {
        now >= endsAt && now < windowCloses(endsAt: endsAt)
    }

    /// Document ID for one of a user's photo slots. A fixed ID per slot means a second upload to the same slot replaces the first.
    static func slotID(userID: String, slot: Int) -> String {
        "\(userID)_\(slot)"
    }

    /// Slots 1...max that this user has not used yet.
    static func freeSlots(userID: String, existingIDs: [String]) -> [Int] {
        (1...maxPhotosPerPerson).filter { !existingIDs.contains(slotID(userID: userID, slot: $0)) }
    }
}

/// Errors shown to the user while posting or loading recap photos.
enum RecapError: LocalizedError {
    /// Supabase keys are missing.
    case notConfigured
    case tooMany
    case badImage

    /// LocalizedError text, shown directly in alerts.
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
        // Errors come from several SDKs (Firebase, Supabase, URLSession) with no shared type,
        // so match on lowercased message text to pick a friendly explanation.
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

