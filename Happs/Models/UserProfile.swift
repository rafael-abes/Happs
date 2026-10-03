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

struct UserLocation: Codable {
    let latitude: Double
    let longitude: Double
    @ServerTimestamp var updatedAt: Date?
}

struct UserProfile: Codable, Identifiable {
    @DocumentID private var documentID: String?
    let displayName: String
    let email: String
    let phoneNumber: String?
    var status: UserStatus
    var isVisible: Bool
    var friendIDs: [String]
    var location: UserLocation?
    @ServerTimestamp var statusUpdatedAt: Date?
    
    var id: String { documentID ?? "" }
    
    init(id: String, displayName: String, email: String, phoneNumber: String? = nil, status: UserStatus = .available, isVisible: Bool = true, friendIDs: [String] = []) {
        self.documentID = id
        self.displayName = displayName
        self.email = email
        self.phoneNumber = phoneNumber
        self.status = status
        self.isVisible = isVisible
        self.friendIDs = friendIDs
        self.location = nil
        self.statusUpdatedAt = nil
    }
    
    var creationData: [String: Any] {
        var data: [String: Any] = [
            "displayName": displayName,
            "email": email,
            "status": status.rawValue,
            "isVisible": isVisible,
            "friendIDs": friendIDs,
            "createdAt": FieldValue.serverTimestamp(),
            "statusUpdatedAt": FieldValue.serverTimestamp()
        ]
        if let phoneNumber { data["phoneNumber"] = phoneNumber }
        return data
    }
}
