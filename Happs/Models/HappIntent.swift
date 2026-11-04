//
//  HappIntent.swift
//  Happs
//
//  Created by Rafa Abes on 10/23/26.
//

//  CODE OVERVIEW
//  -------------
//  The structured result of the AI "describe your plan in a sentence" feature. AIService asks Gemini to
//  return JSON and decodes it into HappIntent, which the UI then uses to prefill a HappDraft. Model
//  output is unreliable, so the decoder is deliberately forgiving: every field falls back to a
//  default instead of throwing. The type is marked nonisolated so it can be decoded off the main actor.
//
import Foundation

/// What Gemini extracts from a sentence like "pizza with the study crew tomorrow 6pm at the Menzies".
/// Every field except title is optional and decoding is tolerant, so a partly wrong
/// model answer never crashes the app.
nonisolated struct HappIntent: Decodable, Equatable {
    /// The only required field; empty string if the model omitted it.
    var title: String
    var category: String?
    var locationText: String?
    /// Local time in the user's time zone, format yyyy-MM-dd'T'HH:mm
    var startLocal: String?
    var durationMinutes: Int?
    var inviteGroupText: String?
    var notes: String?
    /// Names of details the model could not find, so the UI can ask the user for them.
    var missingFields: [String]

    /// Explicit keys because the custom decoder below reads each one individually.
    enum CodingKeys: String, CodingKey {
        case title, category, locationText, startLocal, durationMinutes
        case inviteGroupText, notes, missingFields
    }

    /// Memberwise-style initialiser with defaults. Needed because defining init(from:) below removes the synthesised one.
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

    /// Tolerant decoding: `try?` turns a wrong type or missing key into nil/default rather than an error.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        category = (try? c.decodeIfPresent(String.self, forKey: .category)) ?? nil
        locationText = (try? c.decodeIfPresent(String.self, forKey: .locationText)) ?? nil
        startLocal = (try? c.decodeIfPresent(String.self, forKey: .startLocal)) ?? nil
        inviteGroupText = (try? c.decodeIfPresent(String.self, forKey: .inviteGroupText)) ?? nil
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? nil
        missingFields = (try? c.decodeIfPresent([String].self, forKey: .missingFields)) ?? []

        // The model may send durationMinutes as 60 or 60.0 (or 59.5), so try Int first, then round a Double.
        if let whole = try? c.decodeIfPresent(Int.self, forKey: .durationMinutes) {
            durationMinutes = whole
        } else if let fractional = try? c.decodeIfPresent(Double.self, forKey: .durationMinutes) {
            durationMinutes = Int(fractional.rounded())
        } else {
            durationMinutes = nil
        }
    }
}
