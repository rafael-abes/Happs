//
//  SupportInfo.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


// CODE OVERVIEW
// A single caseless enum holding the support email and policy links, so every screen that shows
// them reads the same constants and they can be replaced in one place before release. The URLs
// are optionals because URL(string:) returns nil for an invalid string.
//
import Foundation

/// Static support contact details (placeholders for now, see the header above).
enum SupportInfo {
    static let contactEmail = "support@happs.example"
    static let privacyPolicyURL = URL(string: "https://happs.example/privacy")
    static let communityRulesURL = URL(string: "https://happs.example/rules")

    /// A mailto link with a prefilled subject (%20 is an encoded space), for opening the Mail app.
    static var mailtoURL: URL? {
        URL(string: "mailto:\(contactEmail)?subject=Happs%20support")
    }
}
