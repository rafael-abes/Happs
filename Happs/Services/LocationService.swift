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
    
    var isInvisible = false
    
    private let manager = CLLocationManager()
    private let database = Firestore.firestore()
    private var currentUserID: String?
    
    private static let campusBoundary: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: -37.90777268374264, longitude: 145.13021258121205),
        CLLocationCoordinate2D(latitude: -37.90830783929267, longitude: 145.1366105888795),
        CLLocationCoordinate2D(latitude: -37.91522197879005, longitude: 145.1341950163024),
        CLLocationCoordinate2D(latitude: -37.91358788712169, longitude: 145.12876989249247)
    ]
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 15 // throttle writes to roughly every 15m of movement
    }
    
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }
    
    func startSharing(userID: String) {
        currentUserID = userID
        manager.startUpdatingLocation()
    }
    
    func stopSharing() {
        currentUserID = nil
        manager.stopUpdatingLocation()
    }
    
    private func handle(_ coordinate: CLLocationCoordinate2D) {
        isInsideCampus = Self.isInside(coordinate, polygon: Self.campusBoundary)
        guard let userID = currentUserID else { return }
        
        if isInvisible || !isInsideCampus {
            removeLocation(userID: userID)
        } else {
            publishLocation(coordinate, userID: userID)
        }
    }
    
    /// Replaces only the `location` field on the document, nothing else on the
    /// profile is touched by this write.
    private func publishLocation(_ coordinate: CLLocationCoordinate2D, userID: String) {
        try? database.collection("users").document(userID).updateData([
            "location": [
                "latitude": coordinate.latitude,
                "longitude": coordinate.longitude,
                "updatedAt": FieldValue.serverTimestamp()
            ]
        ])
    }
    
    /// Deleting the field entirely, not just hiding it client-side, is the actual
    /// privacy mechanism: a friend with no `location` field simply has nothing to read.
    private func removeLocation(userID: String) {
        try? database.collection("users").document(userID).updateData([
            "location": FieldValue.delete()
        ])
    }
    
    /// Ray-casting point-in-polygon test, sufficient for this fixed four-point boundary.
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
