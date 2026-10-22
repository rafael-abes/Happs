//
//  FriendsMapView.swift
//  Happs
//
//  Created by Rafa Abes on 10/3/26.
//

import SwiftUI
import MapKit

struct FriendsMapView: View {
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var happStore: HappStore
    @EnvironmentObject private var locationService: LocationService
    
    @State private var cameraPosition: MapCameraPosition = .region(LocationService.campusRegion)
    @State private var selectedFriendID: String?
    
    private var selectedFriend: UserProfile? {
        guard let id = selectedFriendID, friendStore.location(for: id) != nil else { return nil }
        return friendStore.friends.first { $0.id == id }
    }
    
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
    
    private var liveMap: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
            
            MapPolygon(coordinates: LocationService.campusBoundary)
                .foregroundStyle(.green.opacity(0.12))
                .stroke(.green, lineWidth: 2)
            
            friendAnnotations
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onAppear(perform: centerCamera)
        .safeAreaInset(edge: .bottom) {
            if let friend = selectedFriend {
                FriendCard(friend: friend, onClose: { selectedFriendID = nil })
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
    }
    
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
                }
                .annotationTitles(.hidden)
            }
        }
    }
    
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
