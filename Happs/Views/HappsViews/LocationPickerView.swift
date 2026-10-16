//
//  LocationPickerView.swift
//  Happs
//
//  Created by Rafa Abes on 10/3/26.
//


import SwiftUI
import MapKit

struct LocationPickerView: View {
    let category: HappCategory
    @Binding var selectedName: String
    @Binding var selectedCoordinate: CLLocationCoordinate2D?
    @Binding var isOffCampus: Bool
    @EnvironmentObject private var locationService: LocationService
    @Environment(\.dismiss) private var dismiss
    
    @State private var placesService = PlacesService()
    @State private var searchText = ""
    @State private var results: [MKMapItem] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isDroppingPin = false
    @State private var pinPlaced = false
    @State private var errorMessage: String?
    
    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var resultsTitle: String {
        trimmedQuery.isEmpty ? "Nearby places" : "Suggestions"
    }
    
    private var emptyMessage: String {
        trimmedQuery.isEmpty
            ? "No nearby spots found."
            : "No suggestions. You can still use what you typed above."
    }
    
    private var offCampusTitle: String {
        trimmedQuery.isEmpty ? "Off campus" : "Off campus: \"\(trimmedQuery)\""
    }
    
    private var searchCenter: CLLocationCoordinate2D {
        if let current = locationService.currentCoordinate { return current }
        let points = LocationService.campusBoundary
        let count = Double(points.count)
        return CLLocationCoordinate2D(
            latitude: points.map(\.latitude).reduce(0, +) / count,
            longitude: points.map(\.longitude).reduce(0, +) / count
        )
    }
    
    var body: some View {
        NavigationStack {
            List {
                optionsSection
                resultsSection
            }
            .searchable(text: $searchText, prompt: "Search or type a place")
            .onChange(of: searchText) { _, _ in scheduleSearch() }
            .task { await runSearch() }
            .navigationTitle("Choose Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isDroppingPin, onDismiss: {
                if pinPlaced { dismiss() }
            }) {
                PinDropView(name: trimmedQuery, center: searchCenter) { coordinate in
                    selectedName = trimmedQuery
                    selectedCoordinate = coordinate
                    isOffCampus = !LocationService.isInside(coordinate, polygon: LocationService.campusBoundary)
                    pinPlaced = true
                }
            }
            .alert("Search Failed", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }
    
    private var optionsSection: some View {
        Section {
            if !trimmedQuery.isEmpty {
                Button(action: useTypedLocation) {
                    Label("Use \"\(trimmedQuery)\"", systemImage: "pencil.and.scribble")
                }
                Button { isDroppingPin = true } label: {
                    Label("Drop a pin for \"\(trimmedQuery)\"", systemImage: "mappin.and.ellipse")
                }
            }
            Button(action: useOffCampus) {
                Label(offCampusTitle, systemImage: "location.slash")
            }
        } footer: {
            Text("Off campus Happs show in the list but not on the campus map.")
        }
    }
    
    private var resultsSection: some View {
        Section(resultsTitle) {
            if results.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(results, id: \.self) { item in
                    resultRow(item)
                }
            }
        }
    }
    
    private func resultRow(_ item: MKMapItem) -> some View {
        Button { select(item) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name ?? "Unknown place")
                    .foregroundStyle(.primary)
                if let address = item.placemark.title {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    
    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }
    
    private func runSearch() async {
        do {
            let found: [MKMapItem]
            if trimmedQuery.isEmpty {
                found = try await placesService.nearbyPlaces(
                    around: searchCenter,
                    filter: category.pointOfInterestFilter
                )
            } else {
                found = try await placesService.searchPlaces(
                    matching: trimmedQuery,
                    near: searchCenter
                )
            }
            guard !Task.isCancelled else { return }
            results = found
        } catch is CancellationError {
            return
        } catch let error as MKError where error.code == .placemarkNotFound {
            results = []
        } catch let error as MKError where error.code == .loadingThrottled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func select(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        selectedName = item.name ?? "Unknown place"
        selectedCoordinate = coordinate
        isOffCampus = !LocationService.isInside(coordinate, polygon: LocationService.campusBoundary)
        dismiss()
    }
    
    private func useTypedLocation() {
        selectedName = trimmedQuery
        selectedCoordinate = nil
        isOffCampus = false
        dismiss()
    }
    
    private func useOffCampus() {
        selectedName = trimmedQuery.isEmpty ? "Off campus" : "\(trimmedQuery) (off campus)"
        selectedCoordinate = nil
        isOffCampus = true
        dismiss()
    }
}
