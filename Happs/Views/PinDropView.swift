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
    
    init(name: String, center: CLLocationCoordinate2D, onConfirm: @escaping (CLLocationCoordinate2D) -> Void) {
        self.name = name
        self.onConfirm = onConfirm
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
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.happsGreen, in: Capsule())
            }
            .padding()
        } else {
            Text("Tap the map to place your pin")
                .font(.subheadline)
                .padding(10)
                .background(.regularMaterial, in: Capsule())
                .padding()
        }
    }
}