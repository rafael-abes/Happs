//
//  UserSearchEntry.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//

import Foundation
import FirebaseFirestore

struct UserSearchEntry: Codable, Identifiable {
    static let collectionName = "userSearchIndex"
    
    @DocumentID private var documentID: String?
    let displayName: String
    
    var id: String { documentID ?? "" }
}
