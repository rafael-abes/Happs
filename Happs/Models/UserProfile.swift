//
//  UserProfile.swift
//  Happs
//
//  Created by Rafa Abes on 9/21/26.
//
import Foundation
import FirebaseFirestore

struct UserProfile: Identifiable {
    let id: String
    let displayName: String
    let email: String
    let phoneNumber: String?
    
    var creationData: [String: Any] {
        var data: [String: Any] = [
            "displayName": displayName,
            "email": email,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let phoneNumber {
            data["phoneNumber"] = phoneNumber
        }
        return data
    }
}
