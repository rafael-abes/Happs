//
//  Speakable.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
import Foundation

// Plain-language summaries for the speaker button.
// ASSUMPTIONS (check against your models): Happ has title, location, startTime, creatorName,
// participantIDs; UserProfile has displayName and status with a String rawValue;
// AppNotification has title and body.

extension Happ {
    var spokenSummary: String {
        let when = startTime.formatted(.dateTime.weekday(.wide).hour().minute())
        var parts = ["\(title)."]
        if !location.isEmpty { parts.append("At \(location).") }
        parts.append("Starts \(when).")
        parts.append("Organised by \(creatorName).")
        let going = participantIDs.count
        parts.append(going == 1 ? "1 person is going." : "\(going) people are going.")
        return parts.joined(separator: " ")
    }
}

extension UserProfile {
    var spokenSummary: String {
        "\(displayName). Status: \(status.rawValue)."
    }
}

extension AppNotification {
    var spokenSummary: String {
        body.isEmpty ? title : "\(title). \(body)"
    }
}

