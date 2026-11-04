//
//  LiveLocation.swift
//  Happs
//
//  Created by Rafa Abes on 10/3/26.
//
//  CODE OVERVIEW
//  -------------
//  Model for a user's last shared position on campus. It is a Firestore document (the ID is the user's
//  ID, taken via @DocumentID) cleared by LocationService (assumed to be written there too) and read by FriendStore to show friends on
//  the map. Only latitude, longitude and a server-set time are stored.
//
import Foundation
import FirebaseFirestore

/// A user's most recent shared coordinate.
struct LiveLocation: Codable, Identifiable {
    @DocumentID private var documentID: String?
    let latitude: Double
    let longitude: Double
    /// Server-set time of the last update, so readers can judge how stale the location is.
    @ServerTimestamp var updatedAt: Date?
    
    /// Identifiable id from the Firestore document ID.
    var id: String { documentID ?? "" }
}
