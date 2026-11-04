//
//  UserSearchEntry.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//

//  CODE OVERVIEW
//  -------------
//  A deliberately tiny record in the "userSearchIndex" collection used by friend search. Keeping
//  searchable data apart from the full profile means the search collection can be readable by all
//  signed-in users without exposing email, phone or friends. FriendStore queries it by name.
//
import Foundation
import FirebaseFirestore

/// A minimal, publicly-readable record used only for friend discovery.
struct UserSearchEntry: Codable, Identifiable {
    /// Firestore collection name.
    static let collectionName = "userSearchIndex"
    
    /// Set by Firestore from the document ID (the matching user's ID).
    @DocumentID private var documentID: String?
    let displayName: String
    
    /// Identifiable id from the Firestore document ID.
    var id: String { documentID ?? "" }
    
    /// Lowercased, accent-free, trimmed form used for matching.
    static func searchKey(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            // Fold away case and accents so "Zoë" matches "zoe".
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }
}
