//
//  PlacesService.swift
//  Happs
//
//  Created by Rafa Abes on 10/3/26.
//
import Foundation
import MapKit

@MainActor
final class PlacesService {
    func nearbyPlaces(around coordinate: CLLocationCoordinate2D, filter: MKPointOfInterestFilter?, radius: CLLocationDistance = 500) async throws -> [MKMapItem] {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: min(radius, MKLocalPointsOfInterestRequest.maxRadius))
        if let filter { request.pointOfInterestFilter = filter }
        return try await MKLocalSearch(request: request).start().mapItems
    }
    
    func searchPlaces(matching query: String, near coordinate: CLLocationCoordinate2D) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 3000, longitudinalMeters: 3000)
        return try await MKLocalSearch(request: request).start().mapItems
    }
}
