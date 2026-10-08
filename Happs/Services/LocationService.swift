//
//  LocationService.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//
import Foundation
import CoreLocation
import FirebaseFirestore
import Combine

@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isInsideCampus = false
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?
    
    private let manager = CLLocationManager()
    private let database = Firestore.firestore()
    private var currentUserID: String?
    
    static let campusBoundary: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: -37.90777268374264, longitude: 145.13021258121205),
        CLLocationCoordinate2D(latitude: -37.90830783929267, longitude: 145.1366105888795),
        CLLocationCoordinate2D(latitude: -37.91522197879005, longitude: 145.1341950163024),
        CLLocationCoordinate2D(latitude: -37.91358788712169, longitude: 145.12876989249247)
    ]
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 15
    }
    
    func requestPermission() { manager.requestWhenInUseAuthorization() }
    func startSharing(userID: String) { currentUserID = userID; manager.startUpdatingLocation() }
    func stopSharing() { currentUserID = nil; manager.stopUpdatingLocation() }
    
    /// Writes continuously while on campus, regardless of visibility. Whether a
    /// friend can actually *read* this document is now entirely a Firestore
    /// rules decision (see liveLocations rule), not a client-side one, this is
    /// what makes it an actual security boundary rather than good-faith behavior.
    private func handle(_ coordinate: CLLocationCoordinate2D) {
        currentCoordinate = coordinate
        isInsideCampus = Self.isInside(coordinate, polygon: Self.campusBoundary)
        guard let userID = currentUserID else { return }
        
        if isInsideCampus {
            publishLocation(coordinate, userID: userID)
        } else {
            removeLocation(userID: userID)
        }
    }
    
    private func publishLocation(_ coordinate: CLLocationCoordinate2D, userID: String) {
        try? database.collection("liveLocations").document(userID).setData([
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }
    
    private func removeLocation(userID: String) {
        try? database.collection("liveLocations").document(userID).delete()
    }
    
    private static func isInside(_ point: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
        var isInside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            if (a.longitude > point.longitude) != (b.longitude > point.longitude) {
                let slope = (b.latitude - a.latitude) / (b.longitude - a.longitude)
                let intersectLat = a.latitude + slope * (point.longitude - a.longitude)
                if point.latitude < intersectLat { isInside.toggle() }
            }
            j = i
        }
        return isInside
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in self.handle(coordinate) }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.authorizationStatus = manager.authorizationStatus }
    }
}
