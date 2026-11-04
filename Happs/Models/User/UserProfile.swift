//
//  UserProfile.swift
//  Happs
//
//  Created by Rafa Abes on 9/21/26.
//
//  CODE OVERVIEW
//  -------------
//  The user profile model, stored as one Firestore document per user in the users collection. It is
//  read live by ProfileStore (own profile) and FriendStore (friends). Besides the Codable model it has
//  a "tolerant" decoder that rebuilds a profile field by field with defaults, so an old or partly
//  written document never makes a friend disappear, and Freshness, a small pure function for judging
//  how recent a heartbeat time is.
//
import Foundation
import FirebaseFirestore

/// Availability status a user can set. Raw values are shown in the UI and stored in Firestore.
enum UserStatus: String, Codable, CaseIterable, Identifiable {
    case available = "Available"
    case inClass = "In Class"
    case busy = "Busy"
    case doNotDisturb = "Do Not Disturb"
    /// Identifiable so statuses can be listed in a picker.
    var id: String { rawValue }
}

/// One user's public profile and presence information.
struct UserProfile: Codable, Identifiable {
    /// The user's ID, filled in by Firestore from the document ID.
    @DocumentID private var documentID: String?
    let displayName: String
    let email: String
    let phoneNumber: String?
    /// Name of an SF Symbol used as the avatar when there is no photo.
    var avatarSymbol: String?
    /// Small JPEG avatar (see the profile pictures note above); nil means use the symbol.
    var avatarPhoto: Data?
    var status: UserStatus
    /// Whether the user appears to others (for example in search and on the map).
    var isVisible: Bool
    /// IDs of accepted friends; the friendship list lives on the profile.
    var friendIDs: [String]
    /// Optional so older documents decode; nil means unknown.
    var isOnCampus: Bool?
    /// Last heartbeat time from the device (see Freshness).
    var lastSeenAt: Date?
    /// Server-set time of the last status change.
    @ServerTimestamp var statusUpdatedAt: Date?

    /// Identifiable id from the Firestore document ID.
    var id: String { documentID ?? "" }

    /// Creates a profile in memory. Sets documentID directly so a locally built profile has an id before saving.
    init(
        id: String,
        displayName: String,
        email: String,
        phoneNumber: String? = nil,
        avatarSymbol: String? = nil,
        avatarPhoto: Data? = nil,
        status: UserStatus = .available,
        isVisible: Bool = true,
        friendIDs: [String] = [],
        isOnCampus: Bool? = nil,
        lastSeenAt: Date? = nil
    ) {
        self.documentID = id
        self.displayName = displayName
        self.email = email
        self.phoneNumber = phoneNumber
        self.avatarSymbol = avatarSymbol
        self.avatarPhoto = avatarPhoto
        self.status = status
        self.isVisible = isVisible
        self.friendIDs = friendIDs
        self.isOnCampus = isOnCampus
        self.lastSeenAt = lastSeenAt
        self.statusUpdatedAt = nil
    }

    /// Decodes strictly first, then falls back to defaults for any missing field, so an
    /// older or partly written profile never makes a friend vanish.
    static func tolerant(from snapshot: DocumentSnapshot) -> UserProfile? {
        guard snapshot.exists, let data = snapshot.data() else { return nil }
        if let decoded = try? snapshot.data(as: UserProfile.self) { return decoded }
        return tolerant(id: snapshot.documentID, data: data)
    }

    /// The fallback path, split out so it can be unit tested without a Firestore snapshot.
    /// Every field has a default, and a wrong type falls back to the default too.
    static func tolerant(id: String, data: [String: Any]) -> UserProfile {
        UserProfile(
            id: id,
            displayName: (data["displayName"] as? String) ?? "Happs User",
            email: (data["email"] as? String) ?? "",
            phoneNumber: data["phoneNumber"] as? String,
            avatarSymbol: data["avatarSymbol"] as? String,
            avatarPhoto: data["avatarPhoto"] as? Data,
            status: (data["status"] as? String).flatMap(UserStatus.init(rawValue:)) ?? .available,
            isVisible: (data["isVisible"] as? Bool) ?? true,
            friendIDs: (data["friendIDs"] as? [String]) ?? [],
            isOnCampus: data["isOnCampus"] as? Bool,
            lastSeenAt: (data["lastSeenAt"] as? Timestamp)?.dateValue()
        )
    }

    /// Dictionary written when a profile is first created. Uses FieldValue.serverTimestamp() so times
    /// come from the server. Optional values are only included when present, so no nil fields are written.
    var creationData: [String: Any] {
        var data: [String: Any] = [
            "displayName": displayName, "email": email, "status": status.rawValue,
            "isVisible": isVisible, "friendIDs": friendIDs, "isOnCampus": false,
            "createdAt": FieldValue.serverTimestamp(), "statusUpdatedAt": FieldValue.serverTimestamp()
        ]
        if let phoneNumber { data["phoneNumber"] = phoneNumber }
        if let avatarSymbol { data["avatarSymbol"] = avatarSymbol }
        if let avatarPhoto { data["avatarPhoto"] = avatarPhoto }
        return data
    }
}

/// Decides whether a time-stamped presence value is recent enough to trust.
enum Freshness {
    /// Heartbeats arrive every 60 seconds, so three minutes means something went quiet.
    static let staleAfter: TimeInterval = 180

    /// Returns true if date is within staleAfter of now. A nil date returns missingIsFresh, which lets
    /// callers choose whether "never recorded" counts as fresh. now is a parameter so tests can fix the time.
    static func isFresh(_ date: Date?, now: Date, missingIsFresh: Bool) -> Bool {
        guard let date else { return missingIsFresh }
        return now.timeIntervalSince(date) < staleAfter
    }
}
 
