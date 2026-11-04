//
//  FriendRequest.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//
//  CODE OVERVIEW
//  -------------
//  Model for a friend request, stored in the "friendRequests" collection and managed by FriendStore.
//  The document ID is built from the two user IDs ("sender_recipient") instead of being random, so a
//  request's existence can be checked directly by ID, including from Firestore security rules.
//
import Foundation
import FirebaseFirestore

/// Lifecycle of a request. Stored as its raw String in Firestore.
enum FriendRequestStatus: String, Codable {
    case pending, accepted, declined
}

/// A request from one user to become friends with another.
struct FriendRequest: Codable, Identifiable {
    /// Firestore collection name.
    static let collectionName = "friendRequests"
    
    /// Requests live at a predictable ID so security rules can prove one exists.
    static func documentID(from senderID: String, to recipientID: String) -> String {
        "\(senderID)_\(recipientID)"
    }
    
    /// Set by Firestore from the document ID when decoding.
    @DocumentID private var documentID: String?
    let fromUserID: String
    /// Sender's name copied into the request so the recipient can show it without another lookup.
    let fromDisplayName: String
    let toUserID: String
    /// var because accepting or declining updates it.
    var status: FriendRequestStatus
    /// Server-assigned time; nil until saved.
    @ServerTimestamp var createdAt: Date?
    
    /// Identifiable id from the Firestore document ID.
    var id: String { documentID ?? "" }
    
    /// Builds a request to save; createdAt stays nil so the server fills it in.
    init(fromUserID: String, fromDisplayName: String, toUserID: String, status: FriendRequestStatus) {
        self.fromUserID = fromUserID
        self.fromDisplayName = fromDisplayName
        self.toUserID = toUserID
        self.status = status
        self.createdAt = nil
    }
}
