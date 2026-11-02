//
//  Safety.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//
import Foundation

nonisolated enum ReportKind: String, CaseIterable {
    case photo, happ, group, profile

    var title: String {
        switch self {
        case .photo: "photo"
        case .happ: "Happ"
        case .group: "group"
        case .profile: "profile"
        }
    }
}

nonisolated enum ReportReason: String, CaseIterable, Identifiable {
    case spam = "Spam or scam"
    case sexual = "Nudity or sexual content"
    case harassment = "Harassment or bullying"
    case hate = "Hate speech"
    case violence = "Violence or threats"
    case other = "Something else"

    var id: String { rawValue }
}

/// What is being reported, and who made it.
nonisolated struct ReportTarget: Equatable {
    let kind: ReportKind
    /// ID of the thing reported: recap storage path, Happ ID, group ID or user ID.
    let targetID: String
    /// The Happ the thing belongs to, when there is one.
    let happID: String?
    let offenderID: String
    let offenderName: String
    /// A short line a reviewer can read without opening the app, for example the Happ title or caption.
    let summary: String
    /// Used to hide the item for the reporter. Nil when there is nothing to hide (a profile).
    let hideID: String?

    /// Firestore field values for the report. The server timestamp is added where it is written.
    func payload(reporterID: String, reason: ReportReason, details: String) -> [String: Any] {
        var data: [String: Any] = [
            "reporterID": reporterID,
            "kind": kind.rawValue,
            "targetID": targetID,
            "offenderID": offenderID,
            "offenderName": offenderName,
            "summary": String(summary.prefix(200)),
            "reason": reason.rawValue,
            "details": String(details.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)),
            "status": "open"
        ]
        if let happID { data["happID"] = happID }
        return data
    }

    /// Document IDs cannot contain "/", so a storage path becomes a safe ID.
    static func safeID(_ raw: String) -> String {
        raw.replacingOccurrences(of: "/", with: "_")
    }
}
