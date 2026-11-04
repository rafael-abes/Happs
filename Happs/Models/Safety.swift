//
//  Safety.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//
//  CODE OVERVIEW
//  -------------
//  Value types for the report/block safety flow. ReportKind says what is reported, ReportReason is the
//  menu of reasons, and ReportTarget bundles the details and builds the dictionary written to the
//  Firestore "reports" collection. They are plain Foundation types (no Firebase import) so they are
//  easy to unit test, and nonisolated so any thread can use them. SafetyStore and the report UI use them.
//
import Foundation

/// What kind of thing is being reported.
nonisolated enum ReportKind: String, CaseIterable {
    case photo, happ, group, profile

    /// Lowercase word used inside sentences in the report UI.
    var title: String {
        switch self {
        case .photo: "photo"
        case .happ: "Happ"
        case .group: "group"
        case .profile: "profile"
        }
    }
}

/// Reasons offered to the reporter. Raw values are the display text and are stored on the report.
nonisolated enum ReportReason: String, CaseIterable, Identifiable {
    case spam = "Spam or scam"
    case sexual = "Nudity or sexual content"
    case harassment = "Harassment or bullying"
    case hate = "Hate speech"
    case violence = "Violence or threats"
    case other = "Something else"

    /// Identifiable so the reasons can be listed in a picker.
    var id: String { rawValue }
}

/// What is being reported, and who made it.
nonisolated struct ReportTarget: Equatable {
    let kind: ReportKind
    /// ID of the thing reported: recap storage path, Happ ID, group ID or user ID.
    let targetID: String
    /// The Happ the thing belongs to, when there is one.
    let happID: String?
    /// The user who made the thing being reported.
    let offenderID: String
    let offenderName: String
    /// A short line a reviewer can read without opening the app, for example the Happ title or caption.
    let summary: String
    /// Used to hide the item for the reporter. Nil when there is nothing to hide (a profile).
    let hideID: String?

    /// Firestore field values for the report. The server timestamp is added where it is written.
    func payload(reporterID: String, reason: ReportReason, details: String) -> [String: Any] {
        // Text is truncated (200 and 500 characters) to keep report documents small and bounded.
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
        // happID is optional, so it is only added when present.
        if let happID { data["happID"] = happID }
        return data
    }

    /// Document IDs cannot contain "/", so a storage path becomes a safe ID.
    static func safeID(_ raw: String) -> String {
        raw.replacingOccurrences(of: "/", with: "_")
    }
}
