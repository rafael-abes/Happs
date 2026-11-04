//
//  TicketmasterService.swift
//  Happs
//
//  Created by Rafa Abes on 10/19/26.
//

//  CODE OVERVIEW
//  -------------
//  Client for the Ticketmaster Discovery API: finds upcoming events near a location so a user can turn one into
//  a Happ draft. TicketmasterService is a plain struct with one async method (no stored state); the UI calls
//  events(...) and shows the TicketmasterEvent results.
//  The JSON is decoded into small private Raw* structs that hold only the fields used, then mapped to the
//  app's own TicketmasterEvent. This keeps the rest of the app independent of the API's shape.
//  Errors are a LocalizedError enum so the UI can show errorDescription directly.
//
import Foundation
import CoreLocation

/// App-side model of one Ticketmaster event. Optional fields are things the API may leave out.
struct TicketmasterEvent: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL?
    let imageURL: URL?
    /// Nil when the API gave no usable date.
    let startDate: Date?
    /// True when only the day is known, so the UI hides the time.
    let isTimeTBA: Bool
    let venueName: String?
    let venueAddress: String?
    let latitude: Double?
    let longitude: Double?
    let segment: String?
    let genre: String?
    
    /// Text for the UI: a placeholder when no date, and no time part when the time is unknown.
    var dateText: String {
        guard let startDate else { return "Date to be announced" }
        return startDate.formatted(date: .abbreviated, time: isTimeTBA ? .omitted : .shortened)
    }
}

/// Converts an event into a HappDraft, so the create-Happ form can be pre-filled.
extension TicketmasterEvent {
    func asDraft() -> HappDraft {
        var coordinate: CLLocationCoordinate2D?
        // Build a coordinate only if both latitude and longitude exist.
        if let latitude, let longitude {
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        // Without coordinates it is treated as off campus; otherwise a point-in-polygon test against the campus boundary decides.
        let offCampus: Bool
        if let coordinate {
            offCampus = !LocationService.isInside(coordinate, polygon: LocationService.campusBoundary)
        } else {
            offCampus = true
        }
        
        // Put the ticket link in the notes so the user can find it later.
        var notes = "From Ticketmaster."
        if let url { notes += "\nTickets: \(url.absoluteString)" }
        
        return HappDraft(
            // Title is cut to 80 characters (assumed: the Happ title limit).
            title: String(name.prefix(80)),
            details: notes,
            location: venueName ?? venueAddress ?? "Event venue",
            coordinate: coordinate,
            isOffCampus: offCampus,
            // Sports events become the sport category, everything else the general one.
            category: segment == "Sports" ? .sport : .happs,
            // If no date is known, default to one hour from now.
            startTime: startDate ?? Date().addingTimeInterval(60 * 60),
            endTime: nil
        )
    }
}

/// Filter chips for the search. `rawValue` is the label shown to the user.
enum EventCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case music = "Music"
    case sports = "Sports"
    
    var id: String { rawValue }
    
    /// Ticketmaster segment IDs, taken from the Discovery API documentation.
    /// Maps each chip to Ticketmaster's classification (segment) id; nil means no filter.
    var classificationID: String? {
        switch self {
        case .all: nil
        case .music: "KZFzniwnSyZfZ7v7nJ"
        case .sports: "KZFzniwnSyZfZ7v7nE"
        }
    }
}

/// Failures the service can report, each with a user-readable message.
enum TicketmasterError: LocalizedError {
    case missingKey, badRequest, invalidKey, rateLimited, server(Int)
    
    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your Ticketmaster API key to Secrets.swift."
        case .badRequest: "Couldn't build the Ticketmaster request."
        case .invalidKey: "Ticketmaster rejected the API key. Check Secrets.swift."
        case .rateLimited: "Ticketmaster is limiting requests right now. Try again in a minute."
        case .server(let code): "Ticketmaster returned an error (HTTP \(code))."
        }
    }
}

/// Stateless client. A struct is enough because there is nothing to keep between calls.
struct TicketmasterService {
    /// Base URL of the Discovery API events endpoint.
    private static let endpoint = "https://app.ticketmaster.com/discovery/v2/events.json"
    
    /// Searches events starting from now.
    /// - Parameters:
    ///   - keyword: free text; ignored when empty.
    ///   - category: Music, Sports or All.
    ///   - center: search centre; sent as a geohash because the API's geoPoint parameter expects one.
    ///   - radiusKm: search radius in kilometres.
    ///   - pageSize: maximum events returned (a single page, no paging).
    /// - Throws: TicketmasterError for key, HTTP status problems, or a decoding error.
    func events(
        keyword: String,
        category: EventCategory,
        near center: CLLocationCoordinate2D,
        radiusKm: Int = 40,
        pageSize: Int = 30
    ) async throws -> [TicketmasterEvent] {
        // Fail early with a clear message if the key was never filled in.
        let key = Secrets.ticketmasterAPIKey
        guard !key.isEmpty, key != "PASTE_YOUR_KEY_HERE" else {
            throw TicketmasterError.missingKey
        }
        
        // One formatter is reused for the query date and for parsing dates in the response.
        let formatter = ISO8601DateFormatter()
        // An array of pairs (not a dictionary) keeps the order and lets queryString encode each value itself.
        var parameters: [(String, String)] = [
            ("apikey", key),
            ("geoPoint", Geohash.encode(latitude: center.latitude, longitude: center.longitude)),
            ("radius", String(radiusKm)),
            ("unit", "km"),
            ("startDateTime", formatter.string(from: Date())),
            ("sort", "date,asc"),
            ("size", String(pageSize)),
            // locale * returns events in any language.
            ("locale", "*"),
            // Leave out events whose date is not announced yet.
            ("includeTBA", "no"),
            ("includeTBD", "no")
        ]
        if !keyword.isEmpty { parameters.append(("keyword", keyword)) }
        if let id = category.classificationID { parameters.append(("classificationId", id)) }
        
        // Built by hand with a strict encoder (see queryString) rather than URLComponents.
        guard let url = URL(string: Self.endpoint + "?" + queryString(parameters)) else {
            throw TicketmasterError.badRequest
        }
        
        // async URLSession call: suspends without blocking the main thread.
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw TicketmasterError.server(0)
        }
        // Translate HTTP status codes into specific errors: bad key, rate limit, or other server error.
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw TicketmasterError.invalidKey
        case 429: throw TicketmasterError.rateLimited
        default: throw TicketmasterError.server(http.statusCode)
        }
        
        // Events live under _embedded; missing means no results, so an empty array is returned.
        let decoded = try JSONDecoder().decode(EventsResponse.self, from: data)
        return (decoded.embedded?.events ?? []).map { map($0, parser: formatter) }
    }
    
    // MARK: - Mapping
    
    /// Percent-encodes every value, keeping only unreserved characters, so characters such as & + or spaces cannot break the query.
    private func queryString(_ items: [(String, String)]) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let pairs = items.map { (item: (String, String)) -> String in
            let encoded = item.1.addingPercentEncoding(withAllowedCharacters: unreserved) ?? item.1
            return "\(item.0)=\(encoded)"
        }
        return pairs.joined(separator: "&")
    }
    
    /// Converts one raw API event into the app's model, picking the first venue and classification.
    private func map(_ raw: RawEvent, parser: ISO8601DateFormatter) -> TicketmasterEvent {
        let start = raw.dates?.start
        var date: Date?
        if let text = start?.dateTime { date = parser.date(from: text) }
        // Fall back to the local date when there is no exact time.
        if date == nil, let local = start?.localDate { date = localDay(local) }
        // The time is treated as unknown if the API says so or if no dateTime was sent.
        let timeUnknown = (start?.timeTBA ?? false) || (start?.noSpecificTime ?? false) || start?.dateTime == nil
        
        let venue = raw.embedded?.venues?.first
        // Join the street line and city, skipping whichever is missing.
        let address = [venue?.address?.line1, venue?.city?.name].compactMap { $0 }.joined(separator: ", ")
        let classification = raw.classifications?.first
        
        return TicketmasterEvent(
            id: raw.id,
            name: raw.name,
            url: secureURL(raw.url),
            imageURL: secureURL(bestImage(raw.images)),
            startDate: date,
            isTimeTBA: timeUnknown,
            venueName: venue?.name,
            venueAddress: address.isEmpty ? nil : address,
            latitude: venue?.location?.latitude?.value,
            longitude: venue?.location?.longitude?.value,
            segment: classification?.segment?.name,
            genre: classification?.genre?.name
        )
    }
    
    /// Chooses the smallest 16:9 image at least 300 px wide (cheap to load), else the first image.
    private func bestImage(_ images: [RawImage]?) -> String? {
        guard let images, !images.isEmpty else { return nil }
        let wide = images
            .filter { $0.ratio == "16_9" && ($0.width ?? 0) >= 300 }
            .sorted { ($0.width ?? 0) < ($1.width ?? 0) }
        return (wide.first ?? images.first)?.url
    }
    
    /// Upgrades http links to https (assumed reason: iOS blocks plain http by default).
    private func secureURL(_ text: String?) -> URL? {
        guard let text else { return nil }
        return URL(string: text.replacingOccurrences(of: "http://", with: "https://"))
    }
    
    /// Parses the yyyy-MM-dd date and moves it to 12:00, so it stays on the same day across time zones
    /// (assumed reason). POSIX locale makes the format fixed regardless of the user's settings.
    private func localDay(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)?.addingTimeInterval(12 * 60 * 60)
    }
}

// MARK: - Response shapes (only the fields we use)

/// Top-level response; events are under the "_embedded" key, renamed by CodingKeys.
private struct EventsResponse: Decodable {
    let embedded: Embedded?
    
    struct Embedded: Decodable {
        let events: [RawEvent]?
    }
    
    enum CodingKeys: String, CodingKey {
        case embedded = "_embedded"
    }
}

/// One event as returned by the API (only the fields used).
private struct RawEvent: Decodable {
    let id: String
    let name: String
    let url: String?
    let images: [RawImage]?
    let dates: RawDates?
    let classifications: [RawClassification]?
    let embedded: RawEventEmbedded?
    
    enum CodingKeys: String, CodingKey {
        case id, name, url, images, dates, classifications
        case embedded = "_embedded"
    }
}

/// An image variant; the API sends several sizes and ratios per event.
private struct RawImage: Decodable {
    let url: String
    let ratio: String?
    let width: Int?
}

/// Date block of an event.
private struct RawDates: Decodable {
    let start: RawStart?
}

/// Start of the event. timeTBA and noSpecificTime flag an unknown time.
private struct RawStart: Decodable {
    let localDate: String?
    let dateTime: String?
    let timeTBA: Bool?
    let noSpecificTime: Bool?
}

/// Category info; segment (Music, Sports) and genre.
private struct RawClassification: Decodable {
    let segment: RawName?
    let genre: RawName?
}

/// Any object with just a name.
private struct RawName: Decodable {
    let name: String?
}

/// Wrapper for the venues list.
private struct RawEventEmbedded: Decodable {
    let venues: [RawVenue]?
}

/// Venue where the event is held.
private struct RawVenue: Decodable {
    let name: String?
    let address: RawAddress?
    let city: RawName?
    let location: RawLocation?
}

/// Street address of a venue.
private struct RawAddress: Decodable {
    let line1: String?
}

/// Venue coordinates; may arrive as numbers or strings, hence FlexibleDouble.
private struct RawLocation: Decodable {
    let latitude: FlexibleDouble?
    let longitude: FlexibleDouble?
}

/// The docs say number, but the sample responses send strings.
/// Decodes a number that may be sent as a JSON number or a string.
private struct FlexibleDouble: Decodable {
    let value: Double?
    
    /// Tries Double first, then String converted to Double; nil if neither works. Never throws, so a bad coordinate cannot fail the whole response.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Double(text)
        } else {
            value = nil
        }
    }
}
