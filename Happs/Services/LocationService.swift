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
    /// True only once the server has acknowledged this user's on-campus location document.
    @Published private(set) var isPublishedOnCampus = false
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?
    
    private let manager = CLLocationManager()
    private let database = Firestore.firestore()
    private var currentUserID: String?
    private var hasClearedOutside = false
    private var lastPresence: Bool?
    
    static let campusBoundary: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: -37.90670054042203, longitude: 145.14179024978608),
        CLLocationCoordinate2D(latitude: -37.91590874335654, longitude: 145.13996290463174),
        CLLocationCoordinate2D(latitude: -37.91414957559327, longitude: 145.12767414509705),
        CLLocationCoordinate2D(latitude: -37.90731929578369, longitude: 145.1288163701678)
    ]
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 15
    }
    
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }
    
    func startSharing(userID: String) {
        currentUserID = userID
        hasClearedOutside = false
        isPublishedOnCampus = false
        lastPresence = nil
        manager.startUpdatingLocation()
    }
    
    func stopSharing() {
        currentUserID = nil
        isPublishedOnCampus = false
        manager.stopUpdatingLocation()
    }
    
    /// Call before signing out, while still authenticated, so no ghost pin or
    /// "on campus" flag is left behind.
    func clearLiveLocation(for userID: String) async {
        stopSharing()
        try? await database.collection("liveLocations").document(userID).delete()
        try? await database.collection("users").document(userID).updateData(["isOnCampus": false])
    }
    
    private func handle(_ coordinate: CLLocationCoordinate2D) {
        currentCoordinate = coordinate
        let inside = Self.isInside(coordinate, polygon: Self.campusBoundary)
        if inside != isInsideCampus { isInsideCampus = inside }
        
        guard let userID = currentUserID else { return }
        updatePresence(inside, userID: userID)
        if inside {
            publishLocation(coordinate, userID: userID)
        } else {
            removeLocation(userID: userID)
        }
    }
    
    /// A coarse "on campus" flag friends can see from anywhere. It carries no coordinates.
    private func updatePresence(_ onCampus: Bool, userID: String) {
        guard lastPresence != onCampus else { return }
        lastPresence = onCampus
        database.collection("users").document(userID).updateData(["isOnCampus": onCampus]) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in self?.lastPresence = nil }
        }
    }
    
    private func publishLocation(_ coordinate: CLLocationCoordinate2D, userID: String) {
        hasClearedOutside = false
        database.collection("liveLocations").document(userID).setData([
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { [weak self] error in
            guard error == nil else { return }
            Task { @MainActor in
                guard let self, self.isInsideCampus, !self.isPublishedOnCampus else { return }
                self.isPublishedOnCampus = true
            }
        }
    }
    
    private func removeLocation(userID: String) {
        isPublishedOnCampus = false
        guard !hasClearedOutside else { return }
        hasClearedOutside = true
        database.collection("liveLocations").document(userID).delete { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in self?.hasClearedOutside = false }
        }
    }
    
    static func isInside(_ point: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
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
