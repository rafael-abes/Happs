//
//  LocationService.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//
// CODE OVERVIEW
// Owns the device's location for the campus feature. It uses CLLocationManager (via the
// CLLocationManagerDelegate extension at the bottom) and decides locally whether the user is
// inside the campus polygon. While inside, it writes the user's coordinate to the
// "liveLocations" collection and a coarse "isOnCampus" flag on the "users" document, in one
// Firestore batch so both change together. Leaving the campus deletes the pin.
// It is an ObservableObject so SwiftUI views can observe the @Published state, and it is
// @MainActor so every state change happens on the main thread. A 60 second heartbeat
// re-publishes the position so other clients can treat stale pins as offline
// (assumed reason: updatedAt is refreshed even when the user stands still).
//
import Foundation
import CoreLocation
import FirebaseFirestore
import Combine

/// Observable location store: tracks authorization, campus membership and publishes presence to Firestore.
@MainActor
final class LocationService: NSObject, ObservableObject {
    /// How often an on-campus user re-announces themselves, even when standing still.
    static let heartbeatInterval: TimeInterval = 60
    
    /// Mirrors the system location permission; updated from the delegate callback.
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// Result of the local point-in-polygon test on the latest fix.
    @Published private(set) var isInsideCampus = false
    /// True only once the server has acknowledged this user's on-campus location document.
    @Published private(set) var isPublishedOnCampus = false
    /// Most recent device coordinate, nil until the first fix arrives.
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?
    
    /// The Core Location object that delivers fixes; we are its delegate.
    private let manager = CLLocationManager()
    /// Firestore handle used for the batch writes below.
    private let database = Firestore.firestore()
    /// Signed-in user we publish for; nil means sharing is off.
    private var currentUserID: String?
    /// Guards against sending the "left campus" delete on every fix outside the polygon.
    private var hasLeftCampus = false
    /// Repeating task that calls refreshNow(); kept so it can be cancelled.
    private var heartbeatTask: Task<Void, Never>?
    
    /// Corner points of the campus, in order around the edge, used by isInside(_:polygon:).
    static let campusBoundary: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: -37.90670054042203, longitude: 145.14179024978608),
        CLLocationCoordinate2D(latitude: -37.91590874335654, longitude: 145.13996290463174),
        CLLocationCoordinate2D(latitude: -37.91414957559327, longitude: 145.12767414509705),
        CLLocationCoordinate2D(latitude: -37.90731929578369, longitude: 145.1288163701678)
    ]
    
    /// NSObject subclass (required for the delegate protocol), so init must call super.init() first.
    override init() {
        super.init()
        manager.delegate = self
        // Ten metre accuracy is enough for a campus map and uses less battery than best accuracy.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // Only deliver a new fix after moving 15 metres, which limits Firestore writes.
        manager.distanceFilter = 15
    }
    
    /// Asks for "When In Use" permission only; the app never tracks in the background.
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }
    
    /// Begins location updates and the heartbeat for this user.
    func startSharing(userID: String) {
        currentUserID = userID
        hasLeftCampus = false
        isPublishedOnCampus = false
        manager.startUpdatingLocation()
        startHeartbeat()
    }
    
    /// Stops updates and cancels the heartbeat. Does not delete the Firestore pin (see clearLiveLocation).
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
        // try? because sign-out should continue even if the cleanup write fails.
        try? await batch.commit()
    }
    
    /// Starts a repeating task that republishes the position every heartbeatInterval seconds.
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        // [weak self] avoids a retain cycle: the service owns the task and the task refers back to it.
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.heartbeatInterval))
                guard !Task.isCancelled, let self else { return }
                self.refreshNow()
            }
        }
    }
    
    /// Called for every new fix: updates state, then publishes or removes the pin depending on campus membership.
    private func handle(_ coordinate: CLLocationCoordinate2D) {
        currentCoordinate = coordinate
        let inside = Self.isInside(coordinate, polygon: Self.campusBoundary)
        // Only assign on change so views observing isInsideCampus are not invalidated needlessly.
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
        
        // Completion handler runs off the main actor, so hop back with Task { @MainActor } before touching state.
        batch.commit { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    #if DEBUG
                    print("Couldn't publish location: \(error.localizedDescription)")
                    #endif
                    return
                }
                // Only mark published once the commit succeeded and the user is still on campus.
                if self.isInsideCampus && !self.isPublishedOnCampus {
                    self.isPublishedOnCampus = true
                }
            }
        }
    }
    
    /// Removes the pin and clears the "on campus" flag, once per departure.
    private func leaveCampus(userID: String) {
        isPublishedOnCampus = false
        // Already sent the delete for this departure.
        guard !hasLeftCampus else { return }
        hasLeftCampus = true
        
        let batch = database.batch()
        batch.deleteDocument(database.collection("liveLocations").document(userID))
        batch.setData(["isOnCampus": false], forDocument: database.collection("users").document(userID), merge: true)
        batch.commit { [weak self] error in
            // On failure, reset the flag so the next fix outside campus retries the delete.
            guard error != nil else { return }
            Task { @MainActor in self?.hasLeftCampus = false }
        }
    }
    
    /// Point-in-polygon test using the ray casting (even-odd) rule: cast a ray from the point and
    /// toggle for each polygon edge it crosses. An odd count means inside. Static and pure so it can be unit tested.
    static func isInside(_ point: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
        var isInside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            if (a.longitude > point.longitude) != (b.longitude > point.longitude) {
                // Latitude of the edge at the point's longitude; the point is "below" it if its latitude is smaller.
                let slope = (b.latitude - a.latitude) / (b.longitude - a.longitude)
                let intersectLat = a.latitude + slope * (point.longitude - a.longitude)
                if point.latitude < intersectLat { isInside.toggle() }
            }
            j = i
        }
        return isInside
    }
}

// MARK: - CLLocationManagerDelegate
/// Delegate callbacks arrive on Core Location's thread, so they are nonisolated and forward to the main actor.
extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Several fixes can be batched; only the newest matters.
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in self.handle(coordinate) }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.authorizationStatus = manager.authorizationStatus }
    }
}
