//
//  PinDropView.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//


// CODE OVERVIEW
// Sheet shown from LocationPickerView to choose an exact spot on a map. The user either taps the map or
// pans it and presses a button to drop a pin at the map centre. onConfirm hands the coordinate back to the
// caller as a closure (so this view knows nothing about the form that uses it).
// MapReader gives a proxy that converts a screen point into a map coordinate. onMapCameraChange tracks the
// map centre in state so the button can use it.
import SwiftUI
import MapKit

/// Map sheet for placing a single pin.
struct PinDropView: View {
    /// Place name, used for the marker label and the VoiceOver message.
    let name: String
    /// Called with the chosen coordinate when the user confirms.
    let onConfirm: (CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss
    // The pin placed so far. Nil until the user taps or uses the centre button.
    @State private var pin: CLLocationCoordinate2D?
    // Two-way bound camera, set in init because it depends on the passed in centre.
    @State private var cameraPosition: MapCameraPosition
    // Latest centre of the visible map, updated when the camera stops moving.
    @State private var mapCentre: CLLocationCoordinate2D

    /// A custom init is needed to give @State its starting values from parameters.
    /// Assigning to _mapCentre and _cameraPosition sets the property wrapper storage directly.
    /// The closure is @escaping because it is stored and called later. The camera opens 600 m wide around `center`.
    init(name: String, center: CLLocationCoordinate2D, onConfirm: @escaping (CLLocationCoordinate2D) -> Void) {
        self.name = name
        self.onConfirm = onConfirm
        _mapCentre = State(initialValue: center)
        _cameraPosition = State(initialValue: .region(
            MKCoordinateRegion(center: center, latitudinalMeters: 600, longitudinalMeters: 600)
        ))
    }

    var body: some View {
        NavigationStack {
            // MapReader exposes a MapProxy so a tap location can be converted into a coordinate.
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    UserAnnotation()
                    if let pin {
                        Marker(name, systemImage: "mappin", coordinate: pin)
                            .tint(.green)
                    }
                }
                .accessibilityLabel("Map. Move it so the target is where you want the pin.")
                // Only fires when the gesture ends (not every frame), which is cheaper.
                .onMapCameraChange(frequency: .onEnd) { context in
                    mapCentre = context.region.center
                }
                // Tap gives a screen point. convert returns nil if it cannot be mapped, hence the optional check.
                .onTapGesture { screenPoint in
                    if let coordinate = proxy.convert(screenPoint, from: .local) {
                        pin = coordinate
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle("Drop a Pin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityHint("Closes without choosing a spot.")
                }
            }
        }
    }

    @ViewBuilder
    /// Once a pin exists, shows the confirm button. Before that, shows the instructions and the centre pin button.
    private var bottomBar: some View {
        if let pin {
            Button {
                onConfirm(pin)
                dismiss()
            } label: {
                Text("Use this spot")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, 14)
                    .background(Color.happsGreenFill, in: Capsule())
            }
            .padding()
            .accessibilityHint("Confirms the pin and closes the map.")
        } else {
            VStack(spacing: 10) {
                Text("Tap the map to place your pin, or move the map and use the button below.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                Button {
                    pin = mapCentre
                    AccessibilityNotification.Announcement("Pin placed at \(name).").post()
                } label: {
                    Label("Drop pin at map centre", systemImage: "scope")
                        .font(.headline)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Places the pin in the middle of the map. Move the map first to choose the spot.")
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding()
        }
    }
}
