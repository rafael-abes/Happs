//
//  HappIntent.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//

import Foundation

/// What Gemini extracts from a sentence like "pizza with the study crew tomorrow 6pm at the Menzies".
/// Every field except title is optional and decoding is tolerant, so a partly wrong
/// model answer never crashes the app.
nonisolated struct HappIntent: Decodable, Equatable {
    var title: String
    var category: String?
    var locationText: String?
    /// Local time in the user's time zone, format yyyy-MM-dd'T'HH:mm
    var startLocal: String?
    var durationMinutes: Int?
    var inviteGroupText: String?
    var notes: String?
    var missingFields: [String]

    enum CodingKeys: String, CodingKey {
        case title, category, locationText, startLocal, durationMinutes
        case inviteGroupText, notes, missingFields
    }

    init(
        title: String = "",
        category: String? = nil,
        locationText: String? = nil,
        startLocal: String? = nil,
        durationMinutes: Int? = nil,
        inviteGroupText: String? = nil,
        notes: String? = nil,
        missingFields: [String] = []
    ) {
        self.title = title
        self.category = category
        self.locationText = locationText
        self.startLocal = startLocal
        self.durationMinutes = durationMinutes
        self.inviteGroupText = inviteGroupText
        self.notes = notes
        self.missingFields = missingFields
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        category = (try? c.decodeIfPresent(String.self, forKey: .category)) ?? nil
        locationText = (try? c.decodeIfPresent(String.self, forKey: .locationText)) ?? nil
        startLocal = (try? c.decodeIfPresent(String.self, forKey: .startLocal)) ?? nil
        inviteGroupText = (try? c.decodeIfPresent(String.self, forKey: .inviteGroupText)) ?? nil
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? nil
        missingFields = (try? c.decodeIfPresent([String].self, forKey: .missingFields)) ?? []

        if let whole = try? c.decodeIfPresent(Int.self, forKey: .durationMinutes) {
            durationMinutes = whole
        } else if let fractional = try? c.decodeIfPresent(Double.self, forKey: .durationMinutes) {
            durationMinutes = Int(fractional.rounded())
        } else {
            durationMinutes = nil
        }
    }
}
