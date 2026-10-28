//
//  HappDetailView.swift
//  Happs
//
//  Created by Rafa Abes on 9/21/26.
//

import SwiftUI
import FirebaseAuth
 
struct HappDetailView: View {
    private enum PendingAction {
        case leave, cancel
    }
 
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var happStore: HappStore
    @Environment(\.dismiss) private var dismiss
    let happID: String
 
    @State private var isWorking = false
    @State private var isEditing = false
    @State private var pendingAction: PendingAction?
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
            if let happ {
                ToolbarItem(placement: .primaryAction) {
                    SpeakButton(id: happ.id, text: happ.spokenSummary)
                }
            }
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
        .confirmationDialog(
            pendingAction == .cancel ? "Cancel this Happ?" : "Leave this Happ?",
            isPresented: pendingIsPresented,
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            switch action {
            case .cancel:
                Button("Cancel Happ", role: .destructive) { deleteHapp() }
            case .leave:
                Button("Leave Happ", role: .destructive) { leaveHapp() }
            }
            Button("Keep", role: .cancel) { }
        } message: { action in
            switch action {
            case .cancel: Text("It will be removed for everyone who joined.")
            case .leave: Text("You can rejoin while it's still on.")
            }
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
                LabeledContent("When", value: happ.timeRangeText)
                LabeledContent("Organiser", value: happ.creatorName)
                LabeledContent("Going", value: "\(happ.participantIDs.count)")
            }
 
            if happ.hasEnded(at: Date()) {
                Section {
                    NavigationLink {
                        RecapTimelineView(happ: happ)
                    } label: {
                        Label("Recap", systemImage: "photo.on.rectangle.angled")
                    }
                }
            }
 
            Section {
                if happ.creatorID == currentUserID {
                    Button("Cancel Happ", role: .destructive) { pendingAction = .cancel }
                        .disabled(isWorking)
                } else if happ.containsParticipant(currentUserID) {
                    Button("Leave Happ", role: .destructive) { pendingAction = .leave }
                        .disabled(isWorking)
                } else {
                    Button("Join Happ") {
                        setParticipation(happ: happ, userID: currentUserID, isJoining: true)
                    }
                    .disabled(isWorking)
                }
            }
        }
    }
 
    private var pendingIsPresented: Binding<Bool> {
        Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })
    }
 
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
 
    private func leaveHapp() {
        guard let happ, let userID = authService.user?.uid else { return }
        setParticipation(happ: happ, userID: userID, isJoining: false)
    }
 
    private func setParticipation(happ: Happ, userID: String, isJoining: Bool) {
        isWorking = true
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
