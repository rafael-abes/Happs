//
//  TicketmasterService.swift
//  Happs
//
//  Created by Rafa Abes on 10/19/26.
//

import Foundation
import CoreLocation

struct TicketmasterEvent: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL?
    let imageURL: URL?
    let startDate: Date?
    let isTimeTBA: Bool
    let venueName: String?
    let venueAddress: String?
    let latitude: Double?
    let longitude: Double?
    let segment: String?
    let genre: String?
    
    var dateText: String {
        guard let startDate else { return "Date to be announced" }
        return startDate.formatted(date: .abbreviated, time: isTimeTBA ? .omitted : .shortened)
    }
}

extension TicketmasterEvent {
    func asDraft() -> HappDraft {
        var coordinate: CLLocationCoordinate2D?
        if let latitude, let longitude {
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        let offCampus: Bool
        if let coordinate {
            offCampus = !LocationService.isInside(coordinate, polygon: LocationService.campusBoundary)
        } else {
            offCampus = true
        }
        
        var notes = "From Ticketmaster."
        if let url { notes += "\nTickets: \(url.absoluteString)" }
        
        return HappDraft(
            title: String(name.prefix(80)),
            details: notes,
            location: venueName ?? venueAddress ?? "Event venue",
            coordinate: coordinate,
            isOffCampus: offCampus,
            category: segment == "Sports" ? .sport : .happs,
            startTime: startDate ?? Date().addingTimeInterval(60 * 60),
            endTime: nil
        )
    }
}

enum EventCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case music = "Music"
    case sports = "Sports"
    
    var id: String { rawValue }
    
    /// Ticketmaster segment IDs, taken from the Discovery API documentation.
    var classificationID: String? {
        switch self {
        case .all: nil
        case .music: "KZFzniwnSyZfZ7v7nJ"
        case .sports: "KZFzniwnSyZfZ7v7nE"
        }
    }
}

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

struct TicketmasterService {
    private static let endpoint = "https://app.ticketmaster.com/discovery/v2/events.json"
    
    func events(
        keyword: String,
        category: EventCategory,
        near center: CLLocationCoordinate2D,
        radiusKm: Int = 40,
        pageSize: Int = 30
    ) async throws -> [TicketmasterEvent] {
        let key = Secrets.ticketmasterAPIKey
        guard !key.isEmpty, key != "PASTE_YOUR_KEY_HERE" else {
            throw TicketmasterError.missingKey
        }
        
        let formatter = ISO8601DateFormatter()
        var parameters: [(String, String)] = [
            ("apikey", key),
            ("geoPoint", Geohash.encode(latitude: center.latitude, longitude: center.longitude)),
            ("radius", String(radiusKm)),
            ("unit", "km"),
            ("startDateTime", formatter.string(from: Date())),
            ("sort", "date,asc"),
            ("size", String(pageSize)),
            ("locale", "*"),
            ("includeTBA", "no"),
            ("includeTBD", "no")
        ]
        if !keyword.isEmpty { parameters.append(("keyword", keyword)) }
        if let id = category.classificationID { parameters.append(("classificationId", id)) }
        
        guard let url = URL(string: Self.endpoint + "?" + queryString(parameters)) else {
            throw TicketmasterError.badRequest
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw TicketmasterError.server(0)
        }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw TicketmasterError.invalidKey
        case 429: throw TicketmasterError.rateLimited
        default: throw TicketmasterError.server(http.statusCode)
        }
        
        let decoded = try JSONDecoder().decode(EventsResponse.self, from: data)
        return (decoded.embedded?.events ?? []).map { map($0, parser: formatter) }
    }
    
    // MARK: - Mapping
    
    private func queryString(_ items: [(String, String)]) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let pairs = items.map { (item: (String, String)) -> String in
            let encoded = item.1.addingPercentEncoding(withAllowedCharacters: unreserved) ?? item.1
            return "\(item.0)=\(encoded)"
        }
        return pairs.joined(separator: "&")
    }
    
    private func map(_ raw: RawEvent, parser: ISO8601DateFormatter) -> TicketmasterEvent {
        let start = raw.dates?.start
        var date: Date?
        if let text = start?.dateTime { date = parser.date(from: text) }
        if date == nil, let local = start?.localDate { date = localDay(local) }
        let timeUnknown = (start?.timeTBA ?? false) || (start?.noSpecificTime ?? false) || start?.dateTime == nil
        
        let venue = raw.embedded?.venues?.first
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
    
    private func bestImage(_ images: [RawImage]?) -> String? {
        guard let images, !images.isEmpty else { return nil }
        let wide = images
            .filter { $0.ratio == "16_9" && ($0.width ?? 0) >= 300 }
            .sorted { ($0.width ?? 0) < ($1.width ?? 0) }
        return (wide.first ?? images.first)?.url
    }
    
    private func secureURL(_ text: String?) -> URL? {
        guard let text else { return nil }
        return URL(string: text.replacingOccurrences(of: "http://", with: "https://"))
    }
    
    private func localDay(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)?.addingTimeInterval(12 * 60 * 60)
    }
}

// MARK: - Response shapes (only the fields we use)

private struct EventsResponse: Decodable {
    let embedded: Embedded?
    
    struct Embedded: Decodable {
        let events: [RawEvent]?
    }
    
    enum CodingKeys: String, CodingKey {
        case embedded = "_embedded"
    }
}

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

private struct RawImage: Decodable {
    let url: String
    let ratio: String?
    let width: Int?
}

private struct RawDates: Decodable {
    let start: RawStart?
}

private struct RawStart: Decodable {
    let localDate: String?
    let dateTime: String?
    let timeTBA: Bool?
    let noSpecificTime: Bool?
}

private struct RawClassification: Decodable {
    let segment: RawName?
    let genre: RawName?
}

private struct RawName: Decodable {
    let name: String?
}

private struct RawEventEmbedded: Decodable {
    let venues: [RawVenue]?
}

private struct RawVenue: Decodable {
    let name: String?
    let address: RawAddress?
    let city: RawName?
    let location: RawLocation?
}

private struct RawAddress: Decodable {
    let line1: String?
}

private struct RawLocation: Decodable {
    let latitude: FlexibleDouble?
    let longitude: FlexibleDouble?
}

/// The docs say number, but the sample responses send strings.
private struct FlexibleDouble: Decodable {
    let value: Double?
    
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
