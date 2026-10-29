//
//  UserProfile.swift
//  Happs
//
//  Created by Rafa Abes on 9/21/26.
//
import Foundation
import FirebaseFirestore
 
enum UserStatus: String, Codable, CaseIterable, Identifiable {
    case available = "Available"
    case inClass = "In Class"
    case busy = "Busy"
    case doNotDisturb = "Do Not Disturb"
    var id: String { rawValue }
}
 
struct UserProfile: Codable, Identifiable {
    @DocumentID private var documentID: String?
    let displayName: String
    let email: String
    let phoneNumber: String?
    var avatarSymbol: String?
    var status: UserStatus
    var isVisible: Bool
    var friendIDs: [String]
    var isOnCampus: Bool?
    var lastSeenAt: Date?
    @ServerTimestamp var statusUpdatedAt: Date?
 
    var id: String { documentID ?? "" }
 
    init(
        id: String,
        displayName: String,
        email: String,
        phoneNumber: String? = nil,
        avatarSymbol: String? = nil,
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
            status: (data["status"] as? String).flatMap(UserStatus.init(rawValue:)) ?? .available,
            isVisible: (data["isVisible"] as? Bool) ?? true,
            friendIDs: (data["friendIDs"] as? [String]) ?? [],
            isOnCampus: data["isOnCampus"] as? Bool,
            lastSeenAt: (data["lastSeenAt"] as? Timestamp)?.dateValue()
        )
    }
 
    var creationData: [String: Any] {
        var data: [String: Any] = [
            "displayName": displayName, "email": email, "status": status.rawValue,
            "isVisible": isVisible, "friendIDs": friendIDs, "isOnCampus": false,
            "createdAt": FieldValue.serverTimestamp(), "statusUpdatedAt": FieldValue.serverTimestamp()
        ]
        if let phoneNumber { data["phoneNumber"] = phoneNumber }
        if let avatarSymbol { data["avatarSymbol"] = avatarSymbol }
        return data
    }
}
 
enum Freshness {
    /// Heartbeats arrive every 60 seconds, so three minutes means something went quiet.
    static let staleAfter: TimeInterval = 180
 
    static func isFresh(_ date: Date?, now: Date, missingIsFresh: Bool) -> Bool {
        guard let date else { return missingIsFresh }
        return now.timeIntervalSince(date) < staleAfter
    }
}
 
