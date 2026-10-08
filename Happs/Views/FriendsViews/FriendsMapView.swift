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
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .region(Self.campusRegion))
    
    private static var campusRegion: MKCoordinateRegion {
        let coordinates = LocationService.campusBoundary
        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2),
            span: MKCoordinateSpan(latitudeDelta: (lats.max()! - lats.min()!) * 1.6, longitudeDelta: (lons.max()! - lons.min()!) * 1.6)
        )
    }
    
    var body: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
            
            MapPolygon(coordinates: LocationService.campusBoundary)
                .foregroundStyle(.green.opacity(0.12))
                .stroke(.green, lineWidth: 2)
            
            ForEach(friendStore.friends) { friend in
                if let location = friendStore.friendLocations[friend.id] {
                    Annotation(friend.displayName, coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)) {
                        VStack(spacing: 2) {
                            Circle().fill(friend.status.color).frame(width: 12, height: 12)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                            Text(friend.displayName)
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    }
                }
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }
}
