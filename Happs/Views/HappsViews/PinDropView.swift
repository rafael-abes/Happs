//
//  PinDropView.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//


import SwiftUI
import MapKit

struct PinDropView: View {
    let name: String
    let onConfirm: (CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pin: CLLocationCoordinate2D?
    @State private var cameraPosition: MapCameraPosition
    @State private var mapCentre: CLLocationCoordinate2D

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
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    UserAnnotation()
                    if let pin {
                        Marker(name, systemImage: "mappin", coordinate: pin)
                            .tint(.green)
                    }
                }
                .accessibilityLabel("Map. Move it so the target is where you want the pin.")
                .onMapCameraChange(frequency: .onEnd) { context in
                    mapCentre = context.region.center
                }
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
