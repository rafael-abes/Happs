//
//  FriendGroups.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//

import Foundation
import FirebaseFirestore

struct FriendGroup: Codable, Identifiable {
    static let collectionName = "friendGroups"
    
    @DocumentID private var documentID: String?
    let name: String
    let ownerID: String
    var memberIDs: [String]
    var invitedIDs: [String]
    @ServerTimestamp var createdAt: Date?
    
    var id: String { documentID ?? "" }
    
    init(name: String, ownerID: String, memberIDs: [String], invitedIDs: [String]) {
        self.name = name
        self.ownerID = ownerID
        self.memberIDs = memberIDs
        self.invitedIDs = invitedIDs
        self.createdAt = nil
    }
}

struct GroupActivity: Codable, Identifiable {
    @DocumentID private var documentID: String?
    let text: String
    let actorID: String
    @ServerTimestamp var createdAt: Date?
    
    var id: String { documentID ?? "" }
}
