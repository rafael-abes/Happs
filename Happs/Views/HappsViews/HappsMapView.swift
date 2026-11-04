//
//  HappsMapView.swift
//  Happs
//
//  Created by Rafa Abes on 10/9/26.
//


// CODE OVERVIEW
// The campus map tab. It is a SwiftUI view (the V in MVC/MVVM terms) that holds no data of its own:
// Happs come from HappStore, friends from FriendStore, the user and location from AuthService and
// LocationService. All four are ObservableObjects injected with @EnvironmentObject by an ancestor, so
// the map redraws by itself whenever a Firestore snapshot listener in those stores publishes new data.
// The pins use the iOS 17 MapKit SwiftUI API (Map, Annotation, MapPolygon, MapCameraPosition).
// Only Happs that have not ended and have a pin are drawn. The rest are counted in a note, and the list
// view shows everything. Local @State only holds UI things: layer mode, selected pin, camera, dialogs.
import SwiftUI
import MapKit
import FirebaseAuth

/// Map of campus showing Happ pins and friend pins, with a card at the bottom for the selected pin.
struct HappsMapView: View {
    /// Which layers the segmented control shows. String raw values double as the segment titles, and
    /// CaseIterable lets the Picker loop over every case.
    private enum LayerMode: String, CaseIterable, Identifiable {
        case all = "All"
        case friends = "Friends"
        case happs = "Happs"
        var id: String { rawValue }
    }

    /// What is currently selected. An enum with the ID inside means one optional can hold either a Happ or a
    /// friend, so only one card can be open. Hashable because Map selection and equality checks need it.
    private enum MapSelection: Hashable {
        case happ(String)
        case friend(String)
    }

    // @EnvironmentObject (not @StateObject): this view does not own the stores, it reads shared instances
    // created higher up so every tab sees the same data.
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var happStore: HappStore
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var locationService: LocationService

    // View-local UI state (@State), reset when the view is recreated.
    @State private var mode = LayerMode.all
    // Two-way bound to Map(position:), so the user can pan and the code can also move the camera.
    @State private var cameraPosition: MapCameraPosition = .region(LocationService.campusRegion)
    @State private var selection: MapSelection?
    // Set to push HappDetailView through navigationDestination(item:). Nil means no detail screen.
    @State private var detailHappID: String?
    // The Happ waiting for the user to confirm leaving (drives the confirmation dialog).
    @State private var happPendingLeave: Happ?
    // True while a join/leave request is running, so the card can disable its button.
    @State private var isWorking = false
    // Current time used to hide ended Happs. Kept as state and refreshed by the expiryClock modifier.
    @State private var now = Date()
    @State private var errorMessage: String?

    // Derived from the layer mode: All shows both layers.
    private var showsHapps: Bool { mode != .friends }
    private var showsFriends: Bool { mode != .happs }

    /// Happs that have not ended at the current time.
    private var liveHapps: [Happ] {
        happStore.happs.filter { !$0.hasEnded(at: now) }
    }

    /// Live Happs that can actually be pinned (showsOnMap is a property of Happ, not checked here).
    private var mappableHapps: [Happ] {
        liveHapps.filter { $0.showsOnMap }
    }

    /// Live Happs without a map pin, reported in a note so users know they are in the list.
    private var offMapCount: Int {
        liveHapps.count - mappableHapps.count
    }

    /// Looks the selected ID up again in the current data rather than storing a Happ copy, so the card
    /// never shows stale data and disappears if the Happ ends or the layer is hidden.
    private var selectedHapp: Happ? {
        guard showsHapps, case .happ(let id)? = selection else { return nil }
        return mappableHapps.first { $0.id == id }
    }

    /// Same idea as selectedHapp, and also requires a known location for that friend.
    private var selectedFriend: UserProfile? {
        guard showsFriends, case .friend(let id)? = selection,
              friendStore.location(for: id) != nil else { return nil }
        return friendStore.friends.first { $0.id == id }
    }

    /// Muted standard map. In Friends and Happs modes other points of interest are hidden to cut clutter.
    private var mapStyle: MapStyle {
        switch mode {
        case .all:
            return .standard(emphasis: .muted)
        case .friends, .happs:
            return .standard(emphasis: .muted, pointsOfInterest: .excludingAll)
        }
    }

    // The map, with overlays layered on using safeAreaInset so the controls and map content do not overlap.
    var body: some View {
        Map(position: $cameraPosition) {
            // The system blue dot for the user's own position.
            UserAnnotation()

            // Shades the campus boundary, the same polygon used elsewhere to decide on or off campus.
            MapPolygon(coordinates: LocationService.campusBoundary)
                .foregroundStyle(.green.opacity(0.12))
                .stroke(.green, lineWidth: 2)

            if showsHapps { happAnnotations }
            if showsFriends { friendAnnotations }
        }
        .mapStyle(mapStyle)
        .accessibilityLabel("Campus map showing \(showsHapps ? "\(mappableHapps.count) happs" : "")\(showsHapps && showsFriends ? " and " : "")\(showsFriends ? "\(friendStore.onlineFriends.count) friends on campus" : "")")
        .accessibilityHint("The same Happs are in the list. Use Show list in the toolbar.")
        // Built in locate-me button and compass.
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .safeAreaInset(edge: .top) { modePicker }
        .safeAreaInset(edge: .bottom) { bottomOverlay }
        // Pushes the detail screen whenever detailHappID becomes non-nil.
        .navigationDestination(item: $detailHappID) { id in
            HappDetailView(happID: id)
        }
        // Custom modifier that updates `now` when a Happ start or end time is crossed (assumed behaviour from its name and arguments), so ended Happs leave the map without a reload.
        .expiryClock($now, boundaries: happStore.happs.clockBoundaries)
        // Centre the camera each time the tab appears.
        .onAppear(perform: centerCamera)
        // Changing layer clears the selection so a hidden pin cannot keep its card open.
        .onChange(of: mode) { _, _ in selection = nil }
        // Asks before leaving a Happ (a destructive action). `presenting:` passes the Happ into the closures.
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

    // MapContentBuilder is the result builder for Map content, like @ViewBuilder but for annotations and overlays.
    @MapContentBuilder
    /// One Annotation per mappable Happ. Tapping sets the selection, which opens the card.
    private var happAnnotations: some MapContent {
        ForEach(mappableHapps) { happ in
            if let coordinate = happ.coordinate {
                Annotation(happ.title, coordinate: coordinate, anchor: .bottom) {
                    HappPin(happ: happ, isSelected: selection == .happ(happ.id))
                        .onTapGesture { selection = .happ(happ.id) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Double tap to show details.")
                }
                .annotationTitles(.hidden)
            }
        }
    }

    @MapContentBuilder
    /// One Annotation per friend who currently has a shared location.
    private var friendAnnotations: some MapContent {
        ForEach(friendStore.friends) { friend in
            if let location = friendStore.location(for: friend.id) {
                Annotation(
                    friend.displayName,
                    coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
                ) {
                    FriendPin(friend: friend, isSelected: selection == .friend(friend.id))
                        .onTapGesture { selection = .friend(friend.id) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Double tap to show details.")
                }
                .annotationTitles(.hidden)
            }
        }
    }

    /// Segmented control floating over the top of the map.
    private var modePicker: some View {
        Picker("Map layers", selection: $mode) {
            ForEach(LayerMode.allCases) { layer in
                Text(layer.rawValue).tag(layer)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("Choose whether the map shows everything, friends or Happs.")
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 4)
    }

    // @ViewBuilder lets this property return different view types from if/else branches.
    @ViewBuilder
    /// Bottom area. Shows a Happ card, else a friend card, else the off-map note, else nothing.
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
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.bottom, 8)
        }
    }

    /// Adapts the optional happPendingLeave into a Bool Binding for the dialog. Setting it false clears the Happ.
    private var leaveIsPresented: Binding<Bool> {
        Binding(get: { happPendingLeave != nil }, set: { if !$0 { happPendingLeave = nil } })
    }

    /// Same pattern for the error alert: present while errorMessage is non-nil.
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    /// Moves the camera to a 600 m square around the user, or to the campus region if there is no location yet.
    private func centerCamera() {
        if let coordinate = locationService.currentCoordinate {
            cameraPosition = .region(
                MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600)
            )
        } else {
            cameraPosition = .region(LocationService.campusRegion)
        }
    }

    /// Join immediately, but joining again means leaving, which goes through the confirmation dialog first.
    private func toggleJoin(_ happ: Happ) {
        guard let userID = authService.user?.uid else { return }
        if happ.containsParticipant(userID) {
            happPendingLeave = happ
        } else {
            updateParticipation(happ, isJoining: true, userID: userID)
        }
    }

    /// Calls HappStore to join or leave and reports the result. Errors go into the alert.
    private func updateParticipation(_ happ: Happ, isJoining: Bool, userID: String) {
        isWorking = true
        // Task started from a SwiftUI view inherits the main actor here, so state can be set directly (assumed from the view being main actor isolated).
        Task {
            // defer clears the busy flag on both success and failure paths.
            defer { isWorking = false }
            do {
                try await happStore.toggleParticipation(happID: happ.id, userID: userID, isJoining: isJoining)
                // Spoken confirmation for VoiceOver users, who otherwise get no feedback.
                AccessibilityNotification.Announcement(
                    isJoining ? "You joined \(happ.title)." : "You left \(happ.title)."
                ).post()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
