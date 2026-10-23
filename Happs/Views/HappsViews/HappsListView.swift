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
 
    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Create Happ", systemImage: "plus") { isPresentingEditor = true }
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
                if upcoming.isEmpty && past.isEmpty {
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
    }
 
    private var storeErrorIsPresented: Binding<Bool> {
        Binding(get: { happStore.errorMessage != nil }, set: { if !$0 { happStore.clearError() } })
    }
}
 
private struct HappRow: View {
    let happ: Happ
    let currentUserID: String
    let isEnded: Bool
 
    private var badge: (text: String, color: Color)? {
        if isEnded { return ("Ended", .secondary) }
        if happ.containsParticipant(currentUserID) { return ("Joined", .green) }
        if happ.isInvited(currentUserID) { return ("Invited", .orange) }
        return nil
    }
 
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(happ.title)
                    .font(.headline)
                if let badge {
                    Text(badge.text)
                        .font(.caption)
                        .foregroundStyle(badge.color)
                }
            }
            Text("\(happ.category.rawValue) · \(happ.location)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(happ.timeRangeText)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .opacity(isEnded ? 0.6 : 1)
    }
}
 
