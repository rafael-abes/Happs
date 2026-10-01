//
//  UserProfile.swift
//  Happs
//
//  Created by Rafa Abes on 9/21/26.
//
import Foundation
import FirebaseFirestore

enum UserStatus: String, Codable, CaseIterable, Identifiable {
    case free = "Free"
    case inClass = "In Class"
    case busy = "Busy"
    var id: String { rawValue }
}

struct UserProfile: Codable, Identifiable {
    @DocumentID private var documentID: String?
    let displayName: String
    let email: String
    let phoneNumber: String?
    var status: UserStatus
    var isVisible: Bool
    var friendIDs: [String]
    @ServerTimestamp var statusUpdatedAt: Date?
    
    var id: String { documentID ?? "" }
    
    init(id: String, displayName: String, email: String, phoneNumber: String? = nil, status: UserStatus = .free, isVisible: Bool = true, friendIDs: [String] = []) {
        self.documentID = id
        self.displayName = displayName
        self.email = email
        self.phoneNumber = phoneNumber
        self.status = status
        self.isVisible = isVisible
        self.friendIDs = friendIDs
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
