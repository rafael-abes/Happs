//
//  SupportInfo.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


import Foundation

enum SupportInfo {
    static let contactEmail = "happssupport@gmail.com"
    static let privacyPolicyURL = URL(string: "https://happs.example/privacy")
    static let communityRulesURL = URL(string: "https://happs.example/rules")

    static var mailtoURL: URL? {
        URL(string: "mailto:\(contactEmail)?subject=Happs%20support")
    }
}
