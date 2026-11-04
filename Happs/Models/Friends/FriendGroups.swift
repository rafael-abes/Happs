//
//  FriendGroups.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//

//  CODE OVERVIEW
//  -------------
//  Models for friend groups. FriendGroup is a Firestore document in "friendGroups" holding the owner,
//  accepted members and still-pending invitees; GroupStore reads and writes it. GroupActivity is a
//  small log entry shown in a group's feed. Both are Codable so Firestore maps them automatically.
//
import Foundation
import FirebaseFirestore

/// A named group of friends. Members have accepted; invitedIDs are waiting to accept.
struct FriendGroup: Codable, Identifiable {
    /// Firestore collection name.
    static let collectionName = "friendGroups"
    
    /// Set by Firestore from the document ID when decoding.
    @DocumentID private var documentID: String?
    let name: String
    /// Creator of the group; used to decide who may delete or manage it.
    let ownerID: String
    /// Users who have accepted. var because it changes on join and leave.
    var memberIDs: [String]
    /// Users invited but not yet accepted. var because it changes on accept and decline.
    var invitedIDs: [String]
    /// Server-assigned creation time (nil until the write completes).
    @ServerTimestamp var createdAt: Date?
    
    /// Identifiable id taken from the Firestore document ID.
    var id: String { documentID ?? "" }
    
    /// Creates a new group to be saved. createdAt is left nil so the server timestamp is applied.
    init(name: String, ownerID: String, memberIDs: [String], invitedIDs: [String]) {
        self.name = name
        self.ownerID = ownerID
        self.memberIDs = memberIDs
        self.invitedIDs = invitedIDs
        self.createdAt = nil
    }
}

/// One line in a group's activity feed (for example someone joined), stored as a sub-document.
struct GroupActivity: Codable, Identifiable {
    /// Set by Firestore from the document ID.
    @DocumentID private var documentID: String?
    /// Human-readable description of what happened.
    let text: String
    /// User who caused the event.
    let actorID: String
    @ServerTimestamp var createdAt: Date?
    
    var id: String { documentID ?? "" }
}
