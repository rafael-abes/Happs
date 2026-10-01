//
//  Happ.swift
//  Happs
//
//  Created by Rafa Abes on 9/21/26.
//

import Foundation
import FirebaseFirestore

struct Happ: Codable, Identifiable {
    static let collectionName = "happs"
    
    @DocumentID private var documentID: String?
    let title: String
    let details: String
    let location: String
    let category: HappCategory
    var participantIDs: [String]
    let creatorID: String
    let creatorName: String
    let startTime: Date
    @ServerTimestamp var createdAt: Date?
    
    var id: String {
        documentID ?? ""
    }
    
    init(title: String, details: String, location: String, category: HappCategory, participantIDs: [String], creatorID: String, creatorName: String, startTime: Date) {
        self.title = title
        self.details = details
        self.location = location
        self.category = category
        self.participantIDs = participantIDs
        self.creatorID = creatorID
        self.creatorName = creatorName
        self.startTime = startTime
        createdAt = nil
    }
    
    func containsParticipant(_ userID: String) -> Bool {
        participantIDs.contains(userID)
    }
}

enum HappCategory: String, Codable, CaseIterable, Identifiable {
    case food = "Food"
    case sport = "Sport"
    case study = "Study"
    case happs = "Happs"
    
    var id: String { rawValue }
}
