//
//  HappsListView.swift
//  Happs
//
//  Created by Rafa Abes on 9/21/26.
//

import SwiftUI
import FirebaseAuth

struct HappsListView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var happStore: HappStore
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var recapStore: RecapStore

    @State private var isPresentingEditor = false
    @State private var showsMap = true
    @State private var now = Date()
    @State private var query = ""

    private var isUnlocked: Bool {
        locationService.campusAccess == .inside
    }

    private var currentUserID: String {
        authService.user?.uid ?? ""
    }

    private func matchesQuery(_ happ: Happ) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return true }
        return happ.title.lowercased().contains(text)
            || happ.location.lowercased().contains(text)
            || happ.creatorName.lowercased().contains(text)
            || happ.category.rawValue.lowercased().contains(text)
    }

    private var upcoming: [Happ] {
        happStore.happs
            .filter { !$0.hasEnded(at: now) && matchesQuery($0) }
            .sorted { $0.startTime < $1.startTime }
    }

    private var past: [Happ] {
        happStore.happs
            .filter { $0.hasEnded(at: now) && $0.containsParticipant(currentUserID) && matchesQuery($0) }
            .sorted { $0.effectiveEndTime > $1.effectiveEndTime }
    }

    /// Happs that ended in the last 7 days. At most 12, so at most 12 preview listeners.
    private var recentlyEnded: [Happ] {
        let cutoff = now.addingTimeInterval(-7 * 24 * 3600)
        let recent = happStore.happs
            .filter { $0.hasEnded(at: now) && $0.effectiveEndTime > cutoff }
            .sorted { $0.effectiveEndTime > $1.effectiveEndTime }
        return Array(recent.prefix(12))
    }

    private var recentlyEndedIDs: [String] {
        recentlyEnded.map(\.id)
    }

    /// Recent Happs worth showing: they have photos, or you were there and can still add yours.
    private var recapRows: [Happ] {
        recentlyEnded.filter { happ in
            guard matchesQuery(happ) else { return false }
            let hasPhotos = !(recapStore.previewsByHapp[happ.id] ?? []).isEmpty
            let canAdd = happ.containsParticipant(currentUserID)
                && RecapRules.isWindowOpen(endsAt: happ.effectiveEndTime, now: now)
            return hasPhotos || canAdd
        }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Happs")
                .navigationBarTitleDisplayMode(isUnlocked && showsMap ? .inline : .large)
                .toolbar {
                    if isUnlocked {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(showsMap ? "List" : "Map", systemImage: showsMap ? "list.bullet" : "map") {
                                showsMap.toggle()
                            }
                            .accessibilityLabel(showsMap ? "Show list" : "Show map")
                            .accessibilityHint("Switches between the campus map and the list of Happs.")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Create Happ", systemImage: "plus") { isPresentingEditor = true }
                                .accessibilityHint("Opens a form to make a new Happ.")
                        }
                    }
                }
                .sheet(isPresented: $isPresentingEditor) {
                    NavigationStack { HappEditorView() }
                }
                .alert("Database Error", isPresented: storeErrorIsPresented) {
                    Button("OK", role: .cancel) { happStore.clearError() }
                } message: {
                    Text(happStore.errorMessage ?? "Please try again.")
                }
                .expiryClock($now, boundaries: happStore.happs.clockBoundaries)
                .onChange(of: recentlyEndedIDs, initial: true) { _, ids in
                    recapStore.observePreviews(for: ids)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !isUnlocked {
            CampusLockedView(
                access: locationService.campusAccess,
                happs: happStore.happs,
                onlineFriends: friendStore.onlineFriends
            )
        } else if showsMap {
            HappsMapView()
        } else {
            happsList
        }
    }

    @ViewBuilder
    private var happsList: some View {
        if happStore.isLoading && happStore.happs.isEmpty {
            ProgressView("Loading happs…")
                .accessibilityLabel("Loading happs")
        } else if happStore.happs.isEmpty {
            ContentUnavailableView(
                "No Happs Yet",
                systemImage: "figure.2.arms.open",
                description: Text("Tap + to create the first one.")
            )
        } else {
            VStack(spacing: 8) {
                VoiceSearchField(text: $query, id: "happs-search", placeholder: "Search Happs")
                    .padding(.horizontal)
                    .padding(.top, 8)
                if upcoming.isEmpty && past.isEmpty && recapRows.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    resultsList
                }
            }
        }
    }

    private var resultsList: some View {
        List {
            if !upcoming.isEmpty {
                Section("Now and upcoming") {
                    ForEach(upcoming) { happ in
                        row(happ, isEnded: false)
                    }
                }
            }
            if !recapRows.isEmpty {
                Section("Recaps") {
                    ForEach(recapRows) { happ in
                        recapRow(happ)
                    }
                }
            }
            if !past.isEmpty {
                Section("Ended") {
                    ForEach(past) { happ in
                        row(happ, isEnded: true)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func row(_ happ: Happ, isEnded: Bool) -> some View {
        NavigationLink {
            HappDetailView(happID: happ.id)
        } label: {
            HappRow(happ: happ, currentUserID: currentUserID, isEnded: isEnded)
        }
        .accessibilityHint("Opens the details.")
    }

    /// Attendees get a plain row. Everyone else gets the locked, blurred card.
    private func recapRow(_ happ: Happ) -> some View {
        let previews = recapStore.previewsByHapp[happ.id] ?? []
        let attended = happ.containsParticipant(currentUserID)
        return NavigationLink {
            RecapTimelineView(happ: happ)
        } label: {
            if attended {
                AttendeeRecapLabel(
                    happ: happ,
                    photoCount: previews.count,
                    canAdd: RecapRules.isWindowOpen(endsAt: happ.effectiveEndTime, now: now)
                )
            } else {
                LockedRecapCard(happ: happ, previews: previews)
            }
        }
        .accessibilityHint("Opens the recap.")
    }

    private var storeErrorIsPresented: Binding<Bool> {
        Binding(get: { happStore.errorMessage != nil }, set: { if !$0 { happStore.clearError() } })
    }
}

private struct AttendeeRecapLabel: View {
    let happ: Happ
    let photoCount: Int
    let canAdd: Bool

    private var subtitle: String {
        let photos = photoCount == 1 ? "1 photo" : "\(photoCount) photos"
        return canAdd ? "\(photos) · Add your recap" : photos
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.title3)
                .foregroundStyle(Color.happsGreenText)
                .frame(width: 40, height: 40)
                .background(Color.happsGreen.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(happ.title).font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Recap for \(happ.title), \(photoCount == 1 ? "1 photo" : "\(photoCount) photos")\(canAdd ? ", you can add yours" : "")"
        )
    }
}

private struct HappRow: View {
    let happ: Happ
    let currentUserID: String
    let isEnded: Bool

    /// Text, symbol and an accessible colour. The symbol means colour is never the only cue.
    private var badge: (text: String, symbol: String, color: Color)? {
        if isEnded { return ("Ended", "clock", .secondary) }
        if happ.containsParticipant(currentUserID) { return ("Joined", "checkmark", Color.happsGreenText) }
        if happ.isInvited(currentUserID) { return ("Invited", "envelope", .primary) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(happ.title)
                    .font(.headline)
                if let badge {
                    Label(badge.text, systemImage: badge.symbol)
                        .font(.caption)
                        .foregroundStyle(badge.color)
                }
            }
            Text("\(happ.category.rawValue) · \(happ.location)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(happ.timeRangeText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AccessibilityText.happRow(
                title: happ.title,
                badge: badge?.text,
                category: happ.category.rawValue,
                location: happ.location,
                time: happ.timeRangeText
            )
        )
    }
}
