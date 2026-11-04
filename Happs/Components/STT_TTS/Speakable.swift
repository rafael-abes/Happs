//
//  Speakable.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
// CODE OVERVIEW
// Extensions that turn model objects into plain sentences for text to speech (the speaker button
// in VoiceControls passes spokenSummary to SpeechSynthesizer). The text is built in the model
// extensions rather than in the views so every screen reads a Happ, profile or notification the
// same way, and the wording lives in one place. They are computed properties, so nothing is stored.
import Foundation

/// Spoken description of a Happ (event): title, place, start time, organiser and attendee count.
extension Happ {
    /// Built from short sentences so the voice pauses naturally between them.
    var spokenSummary: String {
        // Locale aware date style, for example the weekday name plus hour and minute.
        let when = startTime.formatted(.dateTime.weekday(.wide).hour().minute())
        var parts = ["\(title)."]
        // Location is optional in practice, so skip the sentence when it is blank.
        if !location.isEmpty { parts.append("At \(location).") }
        parts.append("Starts \(when).")
        parts.append("Organised by \(creatorName).")
        // Singular and plural handled separately so it does not say "1 people".
        let going = participantIDs.count
        parts.append(going == 1 ? "1 person is going." : "\(going) people are going.")
        return parts.joined(separator: " ")
    }
}

/// Spoken description of a user: name and current status.
extension UserProfile {
    var spokenSummary: String {
        "\(displayName). Status: \(status.rawValue)."
    }
}

/// Spoken description of an inbox notification.
extension AppNotification {
    /// Title alone when there is no body, otherwise title then body.
    var spokenSummary: String {
        body.isEmpty ? title : "\(title). \(body)"
    }
}

