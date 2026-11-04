//
//  HappAssistant.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
// CODE OVERVIEW
// Turns one free-text sentence ("badminton tomorrow 3pm at the sports hall") into a
// HappDraft for the New Happ form. HappAssistant is the orchestrator: it checks the daily
// AI limit, asks HappIntentParser (which talks to Gemini) for a structured HappIntent,
// cleans the answer up, looks the place up with MapKit and matches a friend group.
// It never saves anything. The result is a draft the user reviews first, which keeps the
// AI as a suggestion tool and not an authority.
// The parsing/clean-up steps are pure static functions (normalise, nextQuarterHour) so
// they can be unit tested without the network or Gemini.
import Foundation
import CoreLocation
import MapKit

// with cases food, sport, study, happs and raw values "Food", "Sport", "Study", "Happs".
/// Adds a safe way to turn the free text category from Gemini into a HappCategory.
extension HappCategory {
    /// Case-insensitive match against the raw values. Anything unknown, empty or nil falls back to .happs,
    /// so a bad AI answer can never produce an invalid category.
    static func fromAI(_ text: String?) -> HappCategory {
        let key = (text ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return HappCategory.allCases.first { $0.rawValue.lowercased() == key } ?? .happs
    }
}

/// A map search hit reduced to what the draft needs.
struct ResolvedPlace {
    let name: String
    let coordinate: CLLocationCoordinate2D
    /// True when the coordinate is outside the campus boundary (decided by the isOnCampus closure).
    let isOffCampus: Bool
}

/// Everything the review screen needs: the draft plus notes about what the AI guessed or could not do.
struct AssistantResult {
    var draft: HappDraft
    /// Human readable notices shown to the user (defaults used, place not found, group not matched).
    var warnings: [String]
    /// The friend group matched from what the user said, or nil if none matched.
    var group: GroupCandidate?
    /// Field names the AI says the user did not give (copied from the parsed intent).
    var missingFields: [String]
}

/// The intent after validation: a real category, a start in the future and an end derived from a clamped duration.
struct NormalisedIntent {
    var category: HappCategory
    var start: Date
    var end: Date
    var warnings: [String]
}

/// Orchestrates one "describe it" request: limit check, Gemini parse, clean-up,
/// map lookup, group match. It never saves anything. The user reviews the draft first.
// Main actor isolated (the whole type) because it is driven from the UI. The pure helpers further
// down opt out with nonisolated so tests and background code can call them freely.
@MainActor
struct HappAssistant {
    /// Injected so the Gemini call can be swapped (the parser itself takes a protocol generator).
    let parser: HappIntentParser
    /// Daily usage cap for AI requests. A var because record() mutates it.
    var limiter = AIUsageLimiter()

    /// Runs the full pipeline for one sentence.
    /// - Parameters:
    ///   - sentence: the user's text.
    ///   - groups: the user's groups, used to match an invited group by name.
    ///   - region: the map area used to bias the place search toward campus.
    ///   - isOnCampus: closure so this type does not depend on LocationService directly.
    ///   - now: injectable clock (defaults to the current time) for predictable tests.
    /// - Throws: AIError.dailyLimit when the cap is reached, or whatever the parser throws.
    func draft(
        from sentence: String,
        groups: [GroupCandidate],
        region: MKCoordinateRegion,
        isOnCampus: (CLLocationCoordinate2D) -> Bool,
        now: Date = Date()
    ) async throws -> AssistantResult {
        guard limiter.canUse else { throw AIError.dailyLimit }
        // The request is counted before the network call (assumed reason: failed calls still cost quota,
        // and it stops rapid repeat taps from bypassing the cap).
        limiter.record()

        // Step 1: Gemini turns the sentence into structured fields.
        let intent = try await parser.parse(sentence, now: now)
        // Step 2: fix up category, start and duration with plain code, because AI output cannot be trusted.
        let normalised = Self.normalise(intent, now: now)
        var warnings = normalised.warnings

        // Step 3: resolve the place. If the map search finds nothing, the typed text is kept as a text-only
        // location marked off campus, so the user does not lose what they said.
        var locationName = ""
        var coordinate: CLLocationCoordinate2D?
        var offCampus = false
        let wanted = (intent.locationText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !wanted.isEmpty {
            if let place = await Self.resolvePlace(wanted, region: region, isOnCampus: isOnCampus) {
                locationName = place.name
                coordinate = place.coordinate
                offCampus = place.isOffCampus
                warnings.append("Check the map pin for \"\(place.name)\".")
            } else {
                locationName = wanted
                offCampus = true
                warnings.append("Couldn't find \"\(wanted)\" on the map, so it will be listed as text only.")
            }
        }

        // Step 4: match the group name the user mentioned to one of their real groups.
        let group = GroupMatcher.match(intent.inviteGroupText, in: groups)
        if let said = intent.inviteGroupText, !said.isEmpty, group == nil {
            warnings.append("Couldn't match \"\(said)\" to one of your groups.")
        }

        // Step 5: build the draft. The title is cut to 80 characters to stay within the form's limit
        // (assumed reason: matches the title limit used in the form).
        let draft = HappDraft(
            title: String(intent.title.prefix(80)),
            details: intent.notes ?? "",
            location: locationName,
            coordinate: coordinate,
            isOffCampus: offCampus,
            category: normalised.category,
            startTime: normalised.start,
            endTime: normalised.end
        )
        return AssistantResult(draft: draft, warnings: warnings, group: group, missingFields: intent.missingFields)
    }

    // Nothing here touches the network, so the logic can be tested with fixed dates.
    // MARK: Pure helpers (unit tested)

    /// Validates the AI intent. Category falls back to .happs, a missing or past start becomes the next
    /// quarter hour (with a warning), and duration defaults to 60 minutes and is clamped to 15...720 minutes.
    /// The calendar is a parameter so tests can use a fixed time zone.
    nonisolated static func normalise(_ intent: HappIntent, now: Date, calendar: Calendar = .current) -> NormalisedIntent {
        var warnings: [String] = []
        let category = HappCategory.fromAI(intent.category)

        let start: Date
        if let parsed = HappIntentParser.parseLocal(intent.startLocal, calendar: calendar), parsed > now {
            start = parsed
        } else {
            start = nextQuarterHour(after: now, calendar: calendar)
            if intent.startLocal == nil || intent.startLocal?.isEmpty == true {
                warnings.append("No start time given, so I used the next quarter hour.")
            } else {
                warnings.append("That start time has already passed, so I used the next quarter hour.")
            }
        }

        // Clamp rather than reject: a silly duration (like 5 or 5000 minutes) is corrected and the user is told.
        let requested = intent.durationMinutes ?? 60
        let minutes = min(max(requested, 15), 720)
        if intent.durationMinutes != nil && minutes != requested {
            warnings.append("Duration adjusted to \(minutes) minutes.")
        }
        let end = start.addingTimeInterval(Double(minutes) * 60)
        return NormalisedIntent(category: category, start: start, end: end, warnings: warnings)
    }

    /// Next :00, :15, :30 or :45 strictly after the given time (on an exact quarter it moves a full 15 minutes).
    /// Seconds are dropped first by rebuilding the date from year...minute components.
    nonisolated static func nextQuarterHour(after date: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let base = calendar.date(from: parts) ?? date
        let minute = parts.minute ?? 0
        return base.addingTimeInterval(Double(15 - minute % 15) * 60)
    }

    /// Looks up a place name with MapKit local search, biased to the given region.
    /// Returns nil when there is no result or the search throws (errors are deliberately swallowed, the caller
    /// then falls back to text only). Uses the first result as the best match.
    static func resolvePlace(
        _ text: String,
        region: MKCoordinateRegion,
        isOnCampus: (CLLocationCoordinate2D) -> Bool
    ) async -> ResolvedPlace? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = region
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else { return nil }
            let coordinate = item.placemark.coordinate
            return ResolvedPlace(
                name: item.name ?? text,
                coordinate: coordinate,
                isOffCampus: !isOnCampus(coordinate)
            )
        } catch {
            return nil
        }
    }
}
