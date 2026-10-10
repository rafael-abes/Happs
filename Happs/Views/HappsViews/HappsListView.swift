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
    @State private var isPresentingEditor = false
    @State private var showsMap = true
    
    var body: some View {
        NavigationStack {
            Group {
                if showsMap {
                    HappsMapView()
                } else {
                    happsList
                }
            }
            .navigationTitle("Happs")
            .navigationBarTitleDisplayMode(showsMap ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(showsMap ? "List" : "Map", systemImage: showsMap ? "list.bullet" : "map") {
                        showsMap.toggle()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create Happ", systemImage: "plus") { isPresentingEditor = true }
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
            List(happStore.happs) { happ in
                NavigationLink {
                    HappDetailView(happID: happ.id)
                } label: {
                    HappRow(happ: happ, currentUserID: authService.user?.uid ?? "")
                }
            }
            .listStyle(.plain)
        }
    }
    
    private var storeErrorIsPresented: Binding<Bool> {
        Binding(get: { happStore.errorMessage != nil }, set: { if !$0 { happStore.clearError() } })
    }
}

private struct HappRow: View {
    let happ: Happ
    let currentUserID: String
    
    private var badge: (text: String, color: Color)? {
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
        }
    }
}
