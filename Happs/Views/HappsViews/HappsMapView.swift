//
//  HappsMapView.swift
//  Happs
//
//  Created by Rafa Abes on 10/9/26.
//


import SwiftUI
import MapKit
import FirebaseAuth

struct HappsMapView: View {
    private enum LayerMode: String, CaseIterable, Identifiable {
        case all = "All"
        case friends = "Friends"
        case happs = "Happs"
        var id: String { rawValue }
    }
    
    private enum MapSelection: Hashable {
        case happ(String)
        case friend(String)
    }
    
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var happStore: HappStore
    @EnvironmentObject private var friendStore: FriendStore
    
    @State private var mode = LayerMode.all
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .region(LocationService.campusRegion))
    @State private var selection: MapSelection?
    @State private var detailHappID: String?
    @State private var isJoining = false
    @State private var errorMessage: String?
    
    private var showsHapps: Bool { mode != .friends }
    private var showsFriends: Bool { mode != .happs }
    
    private var mappableHapps: [Happ] {
        happStore.happs.filter { $0.coordinate != nil }
    }
    
    private var unmappedCount: Int {
        happStore.happs.count - mappableHapps.count
    }
    
    private var selectedHapp: Happ? {
        guard showsHapps, case .happ(let id)? = selection else { return nil }
        return mappableHapps.first { $0.id == id }
    }
    
    private var selectedFriend: UserProfile? {
        guard showsFriends, case .friend(let id)? = selection,
              friendStore.friendLocations[id] != nil else { return nil }
        return friendStore.friends.first { $0.id == id }
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
        .navigationDestination(item: $detailHappID) { id in
            HappDetailView(happID: id)
        }
        .onChange(of: mode) { _, _ in selection = nil }
        .alert("Couldn't Update", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }
    
    @MapContentBuilder
    private var happAnnotations: some MapContent {
        ForEach(mappableHapps) { happ in
            if let coordinate = happ.coordinate {
                Annotation(happ.title, coordinate: coordinate, anchor: .bottom) {
                    HappPin(happ: happ, isSelected: selection == .happ(happ.id))
                        .onTapGesture { selection = .happ(happ.id) }
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
                    FriendPin(friend: friend, isSelected: selection == .friend(friend.id))
                        .onTapGesture { selection = .friend(friend.id) }
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
            HappCard(
                happ: happ,
                currentUserID: authService.user?.uid ?? "",
                isWorking: isJoining,
                onJoinToggle: { toggleJoin(happ) },
                onOpen: { detailHappID = happ.id },
                onClose: { selection = nil }
            )
            .padding(.horizontal)
            .padding(.bottom, 8)
        } else if let friend = selectedFriend {
            FriendCard(friend: friend, onClose: { selection = nil })
                .padding(.horizontal)
                .padding(.bottom, 8)
        } else if showsHapps && unmappedCount > 0 {
            Text("\(unmappedCount) happ\(unmappedCount == 1 ? "" : "s") without a map pin. See the list.")
                .font(.caption)
                .padding(8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 8)
        }
    }
    
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    
    private func toggleJoin(_ happ: Happ) {
        guard let userID = authService.user?.uid else { return }
        let joining = !happ.containsParticipant(userID)
        isJoining = true
        Task {
            defer { isJoining = false }
            do {
                try await happStore.toggleParticipation(happID: happ.id, userID: userID, isJoining: joining)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
