//
//  Happ.swift
//  Happs
//
//  Created by Rafa Abes on 9/21/26.
//

//  CODE OVERVIEW
//  -------------
//  The core model of the app: one "Happ" (a campus event/meet-up). It is a Firestore document in the
//  "happs" collection, read live by HappStore and shown in the feed, map and detail screens. It is
//  Codable so Firestore maps fields to properties automatically. The creator and participants are
//  stored as user ID strings (not nested user objects), which keeps documents small and lets
//  other code look people up by ID.
//
import Foundation
import FirebaseFirestore

/// A single event that people can create, join and (if invited) see privately.
struct Happ: Codable, Identifiable {
    /// Firestore collection name.
    static let collectionName = "happs"
    
    /// Filled by Firestore from the document ID when decoding; not stored as a field.
    @DocumentID private var documentID: String?
    let title: String
    /// Free-text description (named details rather than description to avoid clashing with Swift's built-in description).
    let details: String
    /// Human-readable place name; the optional latitude and longitude below are the map pin.
    let location: String
    let category: HappCategory
    /// Users who have joined. var because joining and leaving edit it.
    var participantIDs: [String]
    /// Optional so older documents without the field still decode. When set, the Happ is for invited people only.
    var invitedIDs: [String]?
    let creatorID: String
    /// Creator's name copied in, so lists can show it without another user lookup.
    let creatorName: String
    let startTime: Date
    let endTime: Date?
    /// Optional coordinates; nil when the Happ has no precise spot.
    let latitude: Double?
    let longitude: Double?
    /// Optional (not Bool) so older documents decode; nil is treated as on campus (see showsOnMap).
    let isOffCampus: Bool?
    /// Server-assigned creation time (nil until saved).
    @ServerTimestamp var createdAt: Date?
    
    /// Identifiable id taken from the Firestore document ID.
    var id: String { documentID ?? "" }
    
    /// A pin belongs on the campus map only when it has a spot and isn't off campus.
    var showsOnMap: Bool {
        coordinate != nil && isOffCampus != true
    }
    
    /// Creates a new Happ to save. Optional fields default to nil and createdAt stays nil so the server sets it.
    init(
        title: String,
        details: String,
        location: String,
        category: HappCategory,
        participantIDs: [String],
        creatorID: String,
        creatorName: String,
        startTime: Date,
        endTime: Date? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        isOffCampus: Bool? = nil,
        invitedIDs: [String]? = nil
    ) {
        self.title = title
        self.details = details
        self.location = location
        self.category = category
        self.participantIDs = participantIDs
        self.creatorID = creatorID
        self.creatorName = creatorName
        self.startTime = startTime
        self.endTime = endTime
        self.latitude = latitude
        self.longitude = longitude
        self.isOffCampus = isOffCampus
        self.invitedIDs = invitedIDs
        self.createdAt = nil
    }
    
    /// Whether this user has joined.
    func containsParticipant(_ userID: String) -> Bool {
        participantIDs.contains(userID)
    }
    
    /// Whether this user is on the invite list (a missing list counts as empty).
    func isInvited(_ userID: String) -> Bool {
        (invitedIDs ?? []).contains(userID)
    }
}

/// Event type. Raw values are the display strings and are also what is stored in Firestore.
enum HappCategory: String, Codable, CaseIterable, Identifiable {
    case food = "Food"
    case sport = "Sport"
    case study = "Study"
    case happs = "Happs"
    
    /// Identifiable so SwiftUI pickers can iterate allCases.
    var id: String { rawValue }
}
