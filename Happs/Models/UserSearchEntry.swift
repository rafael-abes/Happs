//
//  UserSearchEntry.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//

import Foundation
import FirebaseFirestore

/// A minimal, publicly-readable record used only for friend discovery.
struct UserSearchEntry: Codable, Identifiable {
    static let collectionName = "userSearchIndex"
    
    @DocumentID private var documentID: String?
    let displayName: String
    
    var id: String { documentID ?? "" }
    
    /// Lowercased, accent-free, trimmed form used for matching.
    static func searchKey(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }
}
