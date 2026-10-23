//
//  HappAssistant.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//
import Foundation
import CoreLocation
import MapKit

// ASSUMPTION (check against your file): HappCategory is `enum HappCategory: String, CaseIterable`
// with cases food, sport, study, happs and raw values "Food", "Sport", "Study", "Happs".
extension HappCategory {
    static func fromAI(_ text: String?) -> HappCategory {
        let key = (text ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return HappCategory.allCases.first { $0.rawValue.lowercased() == key } ?? .happs
    }
}

struct ResolvedPlace {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let isOffCampus: Bool
}

struct AssistantResult {
    var draft: HappDraft
    var warnings: [String]
    var group: GroupCandidate?
    var missingFields: [String]
}

struct NormalisedIntent {
    var category: HappCategory
    var start: Date
    var end: Date
    var warnings: [String]
}

/// Orchestrates one "describe it" request: limit check, Gemini parse, clean-up,
/// map lookup, group match. It never saves anything. The user reviews the draft first.
@MainActor
struct HappAssistant {
    let parser: HappIntentParser
    var limiter = AIUsageLimiter()

    func draft(
        from sentence: String,
        groups: [GroupCandidate],
        region: MKCoordinateRegion,
        isOnCampus: (CLLocationCoordinate2D) -> Bool,
        now: Date = Date()
    ) async throws -> AssistantResult {
        guard limiter.canUse else { throw AIError.dailyLimit }
        limiter.record()

        let intent = try await parser.parse(sentence, now: now)
        let normalised = Self.normalise(intent, now: now)
        var warnings = normalised.warnings

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

        let group = GroupMatcher.match(intent.inviteGroupText, in: groups)
        if let said = intent.inviteGroupText, !said.isEmpty, group == nil {
            warnings.append("Couldn't match \"\(said)\" to one of your groups.")
        }

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

    // MARK: Pure helpers (unit tested)

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

        let requested = intent.durationMinutes ?? 60
        let minutes = min(max(requested, 15), 720)
        if intent.durationMinutes != nil && minutes != requested {
            warnings.append("Duration adjusted to \(minutes) minutes.")
        }
        let end = start.addingTimeInterval(Double(minutes) * 60)
        return NormalisedIntent(category: category, start: start, end: end, warnings: warnings)
    }

    nonisolated static func nextQuarterHour(after date: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let base = calendar.date(from: parts) ?? date
        let minute = parts.minute ?? 0
        return base.addingTimeInterval(Double(15 - minute % 15) * 60)
    }

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
