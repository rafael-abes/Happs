//
//  HappDetailView.swift
//  Happs
//
//  Created by Rafa Abes on 9/21/26.
//
import SwiftUI
import FirebaseAuth

struct HappDetailView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var happStore: HappStore
    @Environment(\.dismiss) private var dismiss
    let happID: String
    
    @State private var isWorking = false
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?
    
    private var happ: Happ? {
        happStore.happs.first { $0.id == happID }
    }
    
    var body: some View {
        Group {
            if let happ, let currentUserID = authService.user?.uid {
                content(for: happ, currentUserID: currentUserID)
            } else {
                ContentUnavailableView(
                    "Happ Not Found",
                    systemImage: "questionmark.circle",
                    description: Text("This happ may have been removed.")
                )
            }
        }
        .navigationTitle(happ?.title ?? "Happ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let happ, happ.creatorID == authService.user?.uid {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { isEditing = true }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let happ {
                NavigationStack { HappEditorView(happ: happ) }
            }
        }
        .confirmationDialog("Cancel this Happ?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Cancel Happ", role: .destructive) { deleteHapp() }
            Button("Keep", role: .cancel) { }
        } message: {
            Text("It will be removed for everyone who joined.")
        }
        .alert("Something Went Wrong", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }
    
    private func content(for happ: Happ, currentUserID: String) -> some View {
        List {
            Section {
                Text(happ.details.isEmpty ? "No description added." : happ.details)
            }
            
            Section("Details") {
                LabeledContent("Category", value: happ.category.rawValue)
                LabeledContent("Location", value: happ.location)
                LabeledContent("Starts", value: happ.startTime.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Organiser", value: happ.creatorName)
                LabeledContent("Going", value: "\(happ.participantIDs.count)")
            }
            
            Section {
                if happ.creatorID == currentUserID {
                    Button("Cancel Happ", role: .destructive) { isConfirmingDelete = true }
                        .disabled(isWorking)
                } else {
                    Button(happ.containsParticipant(currentUserID) ? "Leave Happ" : "Join Happ") {
                        toggleParticipation(happ: happ, userID: currentUserID)
                    }
                    .disabled(isWorking)
                }
            }
        }
    }
    
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    
    private func toggleParticipation(happ: Happ, userID: String) {
        isWorking = true
        let isJoining = happ.containsParticipant(userID) == false
        Task {
            defer { isWorking = false }
            do {
                try await happStore.toggleParticipation(happID: happ.id, userID: userID, isJoining: isJoining)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func deleteHapp() {
        guard let happ else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await happStore.deleteHapp(happ)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
