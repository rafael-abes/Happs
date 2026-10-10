//
//  HappsMapView.swift
//  Happs
//
//  Created by Rafa Abes on 10/9/26.
//


import SwiftUI
import MapKit

struct HappsMapView: View {
    private enum LayerMode: String, CaseIterable, Identifiable {
        case all = "All"
        case friends = "Friends"
        case happs = "Happs"
        var id: String { rawValue }
    }
    
    @EnvironmentObject private var happStore: HappStore
    @EnvironmentObject private var friendStore: FriendStore
    
    @State private var mode = LayerMode.all
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .region(LocationService.campusRegion))
    @State private var selectedHappID: String?
    
    private var showsHapps: Bool { mode != .friends }
    private var showsFriends: Bool { mode != .happs }
    
    private var mappableHapps: [Happ] {
        happStore.happs.filter { $0.coordinate != nil }
    }
    
    private var unmappedCount: Int {
        happStore.happs.count - mappableHapps.count
    }
    
    private var selectedHapp: Happ? {
        guard showsHapps else { return nil }
        return mappableHapps.first { $0.id == selectedHappID }
    }
    
    private var mapStyle: MapStyle {
        switch mode {
        case .all:
            return .standard(emphasis: .muted)
        case .friends, .happs:
            return .standard(emphasis: .muted, pointsOfInterest: .excludingAll)
        }
    }
    
    var body: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
            
            MapPolygon(coordinates: LocationService.campusBoundary)
                .foregroundStyle(.green.opacity(0.12))
                .stroke(.green, lineWidth: 2)
            
            if showsHapps { happAnnotations }
            if showsFriends { friendAnnotations }
        }
        .mapStyle(mapStyle)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .safeAreaInset(edge: .top) { modePicker }
        .safeAreaInset(edge: .bottom) { bottomOverlay }
        .onChange(of: mode) { _, _ in selectedHappID = nil }
    }
    
    @MapContentBuilder
    private var happAnnotations: some MapContent {
        ForEach(mappableHapps) { happ in
            if let coordinate = happ.coordinate {
                Annotation(happ.title, coordinate: coordinate, anchor: .bottom) {
                    HappPin(happ: happ, isSelected: happ.id == selectedHappID)
                        .onTapGesture { selectedHappID = happ.id }
                }
                .annotationTitles(.hidden)
            }
        }
    }
    
    @MapContentBuilder
    private var friendAnnotations: some MapContent {
        ForEach(friendStore.friends) { friend in
            if let location = friendStore.friendLocations[friend.id] {
                Annotation(
                    friend.displayName,
                    coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
                ) {
                    FriendPin(friend: friend)
                }
                .annotationTitles(.hidden)
            }
        }
    }
    
    private var modePicker: some View {
        Picker("Map layers", selection: $mode) {
            ForEach(LayerMode.allCases) { layer in
                Text(layer.rawValue).tag(layer)
            }
        }
        .pickerStyle(.segmented)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 4)
    }
    
    @ViewBuilder
    private var bottomOverlay: some View {
        if let happ = selectedHapp {
            detailCard(for: happ)
        } else if showsHapps && unmappedCount > 0 {
            Text("\(unmappedCount) happ\(unmappedCount == 1 ? "" : "s") without a map pin. See the list.")
                .font(.caption)
                .padding(8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 8)
        }
    }
    
    private func detailCard(for happ: Happ) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink {
                HappDetailView(happID: happ.id)
            } label: {
                cardContent(for: happ)
            }
            .buttonStyle(.plain)
            
            Button {
                selectedHappID = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private func cardContent(for happ: Happ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(happ.title).font(.headline)
            Text("\(happ.category.rawValue) · \(happ.location)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(happ.startTime.formatted(date: .abbreviated, time: .shortened)) · \(happ.creatorName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .padding(.trailing, 24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct HappPin: View {
    let happ: Happ
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: happ.category.symbolName)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(happ.category.tint, in: Circle())
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(happ.title)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(happ.participantIDs.count) going")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(.systemBackground), in: Capsule())
            .overlay(Capsule().stroke(happ.category.tint, lineWidth: isSelected ? 3 : 2))
            .shadow(radius: 4, y: 2)
            
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundStyle(happ.category.tint)
                .offset(y: -2)
        }
        .scaleEffect(isSelected ? 1.15 : 1, anchor: .bottom)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}

private struct FriendPin: View {
    let friend: UserProfile
    
    var body: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(friend.status.color)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            Text(friend.displayName)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: Capsule())
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}
