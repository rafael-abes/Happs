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
    
    var body: some View {
        NavigationStack {
            Group {
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
            .navigationTitle("Happs")
            .toolbar {
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
    
    private var storeErrorIsPresented: Binding<Bool> {
        Binding(get: { happStore.errorMessage != nil }, set: { if !$0 { happStore.clearError() } })
    }
}

private struct HappRow: View {
    let happ: Happ
    let currentUserID: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(happ.title)
                    .font(.headline)
                if happ.containsParticipant(currentUserID) {
                    Text("Joined")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Text("\(happ.category.rawValue) · \(happ.location)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
