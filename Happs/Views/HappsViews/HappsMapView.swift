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
    @EnvironmentObject private var locationService: LocationService
    
    @State private var mode = LayerMode.all
    @State private var cameraPosition: MapCameraPosition = .region(LocationService.campusRegion)
    @State private var selection: MapSelection?
    @State private var detailHappID: String?
    @State private var happPendingLeave: Happ?
    @State private var isWorking = false
    @State private var now = Date()
    @State private var errorMessage: String?
    
    private var showsHapps: Bool { mode != .friends }
    private var showsFriends: Bool { mode != .happs }
    
    private var liveHapps: [Happ] {
        happStore.happs.filter { !$0.hasEnded(at: now) }
    }
    
    private var mappableHapps: [Happ] {
        liveHapps.filter { $0.showsOnMap }
    }
    
    private var offMapCount: Int {
        liveHapps.count - mappableHapps.count
    }
    
    private var selectedHapp: Happ? {
        guard showsHapps, case .happ(let id)? = selection else { return nil }
        return mappableHapps.first { $0.id == id }
    }
    
    private var selectedFriend: UserProfile? {
        guard showsFriends, case .friend(let id)? = selection,
              friendStore.location(for: id) != nil else { return nil }
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
        .expiryClock($now, boundaries: happStore.happs.clockBoundaries)
        .onAppear(perform: centerCamera)
        .onChange(of: mode) { _, _ in selection = nil }
        .confirmationDialog(
            "Leave this Happ?",
            isPresented: leaveIsPresented,
            titleVisibility: .visible,
            presenting: happPendingLeave
        ) { happ in
            Button("Leave \(happ.title)", role: .destructive) {
                if let userID = authService.user?.uid {
                    updateParticipation(happ, isJoining: false, userID: userID)
                }
            }
            Button("Stay", role: .cancel) { }
        } message: { _ in
            Text("You can rejoin while it's still on.")
        }
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
            if let location = friendStore.location(for: friend.id) {
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
                isWorking: isWorking,
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
        } else if showsHapps && offMapCount > 0 {
            Text("\(offMapCount) happ\(offMapCount == 1 ? "" : "s") not on the map (off campus or no pin). See the list.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 8)
        }
    }
    
    private var leaveIsPresented: Binding<Bool> {
        Binding(get: { happPendingLeave != nil }, set: { if !$0 { happPendingLeave = nil } })
    }
    
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
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
    
    private func toggleJoin(_ happ: Happ) {
        guard let userID = authService.user?.uid else { return }
        if happ.containsParticipant(userID) {
            happPendingLeave = happ
        } else {
            updateParticipation(happ, isJoining: true, userID: userID)
        }
    }
    
    private func updateParticipation(_ happ: Happ, isJoining: Bool, userID: String) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await happStore.toggleParticipation(happID: happ.id, userID: userID, isJoining: isJoining)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
