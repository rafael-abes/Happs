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
    /// How often an on-campus user re-announces themselves, even when standing still.
    static let heartbeatInterval: TimeInterval = 60
    
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isInsideCampus = false
    /// True only once the server has acknowledged this user's on-campus location document.
    @Published private(set) var isPublishedOnCampus = false
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?
    
    private let manager = CLLocationManager()
    private let database = Firestore.firestore()
    private var currentUserID: String?
    private var hasLeftCampus = false
    private var heartbeatTask: Task<Void, Never>?
    
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
        hasLeftCampus = false
        isPublishedOnCampus = false
        manager.startUpdatingLocation()
        startHeartbeat()
    }
    
    func stopSharing() {
        currentUserID = nil
        isPublishedOnCampus = false
        heartbeatTask?.cancel()
        heartbeatTask = nil
        manager.stopUpdatingLocation()
    }
    
    /// Re-announces the user now. Called by the heartbeat and when the app returns to the foreground.
    func refreshNow() {
        guard let userID = currentUserID, isInsideCampus, let coordinate = currentCoordinate else { return }
        publish(coordinate, userID: userID)
    }
    
    /// Call before signing out, while still authenticated, so no ghost pin or
    /// "on campus" flag is left behind.
    func clearLiveLocation(for userID: String) async {
        stopSharing()
        let batch = database.batch()
        batch.deleteDocument(database.collection("liveLocations").document(userID))
        batch.setData(["isOnCampus": false], forDocument: database.collection("users").document(userID), merge: true)
        try? await batch.commit()
    }
    
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.heartbeatInterval))
                guard !Task.isCancelled, let self else { return }
                self.refreshNow()
            }
        }
    }
    
    private func handle(_ coordinate: CLLocationCoordinate2D) {
        currentCoordinate = coordinate
        let inside = Self.isInside(coordinate, polygon: Self.campusBoundary)
        if inside != isInsideCampus { isInsideCampus = inside }
        
        guard let userID = currentUserID else { return }
        if inside {
            publish(coordinate, userID: userID)
        } else {
            leaveCampus(userID: userID)
        }
    }
    
    /// One batch updates the pin and the coarse "on campus" flag friends can see from anywhere.
    private func publish(_ coordinate: CLLocationCoordinate2D, userID: String) {
        hasLeftCampus = false
        let batch = database.batch()
        batch.setData([
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: database.collection("liveLocations").document(userID))
        batch.setData([
            "isOnCampus": true,
            "lastSeenAt": FieldValue.serverTimestamp()
        ], forDocument: database.collection("users").document(userID), merge: true)
        
        batch.commit { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    #if DEBUG
                    print("Couldn't publish location: \(error.localizedDescription)")
                    #endif
                    return
                }
                if self.isInsideCampus && !self.isPublishedOnCampus {
                    self.isPublishedOnCampus = true
                }
            }
        }
    }
    
    private func leaveCampus(userID: String) {
        isPublishedOnCampus = false
        guard !hasLeftCampus else { return }
        hasLeftCampus = true
        
        let batch = database.batch()
        batch.deleteDocument(database.collection("liveLocations").document(userID))
        batch.setData(["isOnCampus": false], forDocument: database.collection("users").document(userID), merge: true)
        batch.commit { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in self?.hasLeftCampus = false }
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
