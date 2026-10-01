//
//  FriendRequest.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//
import Foundation
import FirebaseFirestore

enum FriendRequestStatus: String, Codable {
    case pending, accepted, declined
}

struct FriendRequest: Codable, Identifiable {
    static let collectionName = "friendRequests"
    
    @DocumentID private var documentID: String?
    let fromUserID: String
    let fromDisplayName: String
    let toUserID: String
    var status: FriendRequestStatus
    @ServerTimestamp var createdAt: Date?
    
    var id: String { documentID ?? "" }
    
    init(fromUserID: String, fromDisplayName: String, toUserID: String, status: FriendRequestStatus) {
        self.fromUserID = fromUserID
        self.fromDisplayName = fromDisplayName
        self.toUserID = toUserID
        self.status = status
        self.createdAt = nil
    }
}
