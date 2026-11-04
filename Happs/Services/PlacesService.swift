//
//  PlacesService.swift
//  Happs
//
//  Created by Rafa Abes on 10/3/26.
//
// CODE OVERVIEW
// Thin wrapper over MapKit's local search so the rest of the app does not depend on MKLocalSearch
// details. It offers two async calls: points of interest around a coordinate, and a free-text
// search near a coordinate. Both return MKMapItem values and throw on network or search errors,
// leaving error handling to the caller. Using Apple's MapKit means no API key or extra cost.
//
import Foundation
import MapKit

/// Looks up real-world places through MapKit.
@MainActor
final class PlacesService {
    /// Points of interest within a radius (metres) of a coordinate, optionally limited by a category filter.
    /// The radius is clamped to MapKit's maximum, which would otherwise be rejected.
    func nearbyPlaces(around coordinate: CLLocationCoordinate2D, filter: MKPointOfInterestFilter?, radius: CLLocationDistance = 500) async throws -> [MKMapItem] {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: min(radius, MKLocalPointsOfInterestRequest.maxRadius))
        if let filter { request.pointOfInterestFilter = filter }
        return try await MKLocalSearch(request: request).start().mapItems
    }
    
    /// Natural language search (for example "coffee") biased to a 3 km square around the coordinate.
    func searchPlaces(matching query: String, near coordinate: CLLocationCoordinate2D) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 3000, longitudinalMeters: 3000)
        return try await MKLocalSearch(request: request).start().mapItems
    }
}
