//
//  LiveLocation.swift
//  Happs
//
//  Created by Rafa Abes on 10/3/26.
//
import Foundation
import FirebaseFirestore

struct LiveLocation: Codable, Identifiable {
    @DocumentID private var documentID: String?
    let latitude: Double
    let longitude: Double
    @ServerTimestamp var updatedAt: Date?
    
    var id: String { documentID ?? "" }
}
