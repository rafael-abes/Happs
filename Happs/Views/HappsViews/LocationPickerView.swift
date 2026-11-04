//
//  LocationPickerView.swift
//  Happs
//
//  Created by Rafa Abes on 10/3/26.
//


// CODE OVERVIEW
// Sheet for choosing a Happ's location while creating one. It has three outcomes: pick a MapKit search
// result (name plus coordinate), use the typed text as is (no coordinate), or mark the Happ off campus.
// A fourth path opens PinDropView to place an exact pin for the typed name.
// Results are written back through @Binding properties owned by the parent form, so this view returns
// data without callbacks. Searching goes through PlacesService. Typing is debounced (350 ms, cancelling
// the previous task) so one search is not fired per keystroke, which also helps with MapKit throttling.
import SwiftUI
import MapKit

/// Searchable list of nearby places and typed-location options.
struct LocationPickerView: View {
    /// Used to filter the nearby places by type of point of interest (Food, Sport and so on).
    let category: HappCategory
    // Outputs: these three bindings write the chosen location back into the parent form.
    @Binding var selectedName: String
    @Binding var selectedCoordinate: CLLocationCoordinate2D?
    @Binding var isOffCampus: Bool
    @EnvironmentObject private var locationService: LocationService
    // Environment action that closes this sheet.
    @Environment(\.dismiss) private var dismiss

    // Wrapper around MapKit search. Held in @State so one instance lives as long as the view.
    @State private var placesService = PlacesService()
    @State private var searchText = ""
    @State private var results: [MKMapItem] = []
    // The pending debounced search, kept so the next keystroke can cancel it.
    @State private var searchTask: Task<Void, Never>?
    @State private var isDroppingPin = false
    // Set by the pin sheet when the user confirms, so the picker closes itself once the pin sheet is dismissed.
    @State private var pinPlaced = false
    @State private var errorMessage: String?

    /// Search text without leading or trailing whitespace, used everywhere instead of the raw text.
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

    /// Where to search around: the user's position, or the middle (average of corners) of the campus boundary if there is no location.
    private var searchCenter: CLLocationCoordinate2D {
        if let current = locationService.currentCoordinate { return current }
        let points = LocationService.campusBoundary
        let count = Double(points.count)
        return CLLocationCoordinate2D(
            latitude: points.map(\.latitude).reduce(0, +) / count,
            longitude: points.map(\.longitude).reduce(0, +) / count
        )
    }

    // A NavigationStack inside the sheet gives it a title and toolbar.
    var body: some View {
        NavigationStack {
            List {
                optionsSection
                resultsSection
            }
            .searchable(text: $searchText, prompt: "Search or type a place")
            // Every edit schedules a debounced search.
            .onChange(of: searchText) { _, _ in scheduleSearch() }
            // Initial search on appear: shows nearby places because the query is empty.
            .task { await runSearch() }
            .navigationTitle("Choose Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityHint("Closes without choosing a location.")
                }
            }
            // The pin sheet reports its result through a closure. onDismiss then closes this picker too, but only if a pin was placed (not on Cancel).
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

    /// Fixed choices: use typed text, drop a pin (only when something is typed), and off campus.
    private var optionsSection: some View {
        Section {
            if !trimmedQuery.isEmpty {
                Button(action: useTypedLocation) {
                    Label("Use \"\(trimmedQuery)\"", systemImage: "pencil.and.scribble")
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Uses the text exactly as you typed it.")
                Button { isDroppingPin = true } label: {
                    Label("Drop a pin for \"\(trimmedQuery)\"", systemImage: "mappin.and.ellipse")
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Opens a map so you can choose the exact spot.")
            }
            Button(action: useOffCampus) {
                Label(offCampusTitle, systemImage: "location.slash")
                    .frame(minHeight: 44)
            }
            .accessibilityHint("Marks it as off campus. It will not show on the campus map.")
        } footer: {
            Text("Off campus Happs show in the list but not on the campus map.")
        }
    }

    /// The list of MapKit results, or a message when there are none.
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

    /// One result as a single accessible button showing name and address.
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
            .frame(minHeight: 44, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [item.name ?? "Unknown place", item.placemark.title].compactMap { $0 }.joined(separator: ", ")
        )
        .accessibilityHint("Double tap to choose this place.")
    }

    /// Bool Binding for the alert, derived from the optional errorMessage.
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    /// Debounce: cancel the earlier task, wait 350 ms, and search only if this task was not cancelled meanwhile.
    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }

    /// Runs either a nearby search (empty query) or a text search, then publishes the results.
    /// Errors are handled by kind: cancellation is ignored, "not found" means an empty list, MapKit throttling is
    /// ignored quietly, and anything else shows the alert.
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
            // Drop stale results if a newer search has replaced this one while it was running.
            guard !Task.isCancelled else { return }
            results = found
            AccessibilityNotification.Announcement(
                found.isEmpty ? "No places found." : "\(found.count) \(found.count == 1 ? "place" : "places") found."
            ).post()
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

    /// Choose a MapKit result: saves its name and coordinate and works out on or off campus from the boundary polygon.
    private func select(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        selectedName = item.name ?? "Unknown place"
        selectedCoordinate = coordinate
        isOffCampus = !LocationService.isInside(coordinate, polygon: LocationService.campusBoundary)
        dismiss()
    }

    /// Plain text location with no coordinate, so no pin on the map. Not treated as off campus.
    private func useTypedLocation() {
        selectedName = trimmedQuery
        selectedCoordinate = nil
        isOffCampus = false
        dismiss()
    }

    /// Off campus location with no coordinate. The Happ then appears in the list but not on the campus map.
    private func useOffCampus() {
        selectedName = trimmedQuery.isEmpty ? "Off campus" : "\(trimmedQuery) (off campus)"
        selectedCoordinate = nil
        isOffCampus = true
        dismiss()
    }
}
