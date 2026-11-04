//
//  FriendsMapView.swift
//  Happs
//
//  Created by Rafa Abes on 10/3/26.
//

// CODE OVERVIEW
// Live map of friends who are on campus, shown when the user toggles to Map in FriendsListView.
// Data: friend profiles and their last known locations come from FriendStore, Happs from HappStore,
// and the user's own position and campus geofence from LocationService, all as @EnvironmentObject.
// Design: the live map is only shown when LocationService says the user is inside campus; otherwise
// a CampusLockedView explains why (a privacy and relevance choice, assumed reason). It uses the iOS 17
// MapKit SwiftUI API (Map with MapContentBuilder, Annotation, MapPolygon) rather than MKMapView.
import SwiftUI
import MapKit

/// Campus map with a pin per friend and a details card for the selected friend.
struct FriendsMapView: View {
    // Stores injected from the app root.
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var happStore: HappStore
    @EnvironmentObject private var locationService: LocationService
    
    // Camera is bound to the Map; starts on the campus region and is recentred in centerCamera().
    @State private var cameraPosition: MapCameraPosition = .region(LocationService.campusRegion)
    // Id of the tapped friend; nil hides the details card.
    @State private var selectedFriendID: String?
    
    /// The tapped friend, but only if the store still has a location for them (so a card never shows for someone who went offline).
    private var selectedFriend: UserProfile? {
        guard let id = selectedFriendID, friendStore.location(for: id) != nil else { return nil }
        return friendStore.friends.first { $0.id == id }
    }
    
    // Gate: the map only appears when the user is physically inside the campus boundary.
    var body: some View {
        if locationService.campusAccess == .inside {
            liveMap
        } else {
            CampusLockedView(
                access: locationService.campusAccess,
                happs: happStore.happs,
                onlineFriends: friendStore.onlineFriends
            )
        }
    }
    
    /// The map itself: user dot, campus boundary polygon, friend pins and the bottom details card.
    private var liveMap: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
            
            // Draws the campus boundary as a faint green shape.
            MapPolygon(coordinates: LocationService.campusBoundary)
                .foregroundStyle(.green.opacity(0.12))
                .stroke(.green, lineWidth: 2)
            
            friendAnnotations
        }
        // Standard controls: recentre on the user, and a compass.
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .accessibilityLabel("Map showing \(friendStore.onlineFriends.count) \(friendStore.onlineFriends.count == 1 ? "friend" : "friends") on campus")
        .accessibilityHint("Friends are also listed on the Friends list. Use Show list in the toolbar.")
        // Recentre when the map appears.
        .onAppear(perform: centerCamera)
        // safeAreaInset lifts the map's content above the card instead of the card covering it.
        .safeAreaInset(edge: .bottom) {
            if let friend = selectedFriend {
                FriendCard(friend: friend, onClose: { selectedFriendID = nil })
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
    }
    
    /// One Annotation per friend that has a known location. @MapContentBuilder lets this property return Map content, not a View.
    @MapContentBuilder
    private var friendAnnotations: some MapContent {
        ForEach(friendStore.friends) { friend in
            if let location = friendStore.location(for: friend.id) {
                Annotation(
                    friend.displayName,
                    coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
                ) {
                    FriendPin(friend: friend, isSelected: selectedFriendID == friend.id)
                        .onTapGesture { selectedFriendID = friend.id }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Double tap to show this friend's details.")
                }
                // Hide the default name label because FriendPin draws its own avatar and status.
                .annotationTitles(.hidden)
            }
        }
    }
    
    /// Centres the camera on the user (600 m square) if their coordinate is known, otherwise on the whole campus.
    private func centerCamera() {
        if let coordinate = locationService.currentCoordinate {
            cameraPosition = .region(
                MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600)
            )
        } else {
            cameraPosition = .region(LocationService.campusRegion)
        }
    }
}
