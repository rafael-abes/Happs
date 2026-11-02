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
 
    @EnvironmentObject private var safetyStore: SafetyStore
    @EnvironmentObject private var friendStore: FriendStore
    @State private var reportTarget: ReportTarget?
    @State private var pendingBlock: Happ?
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
                    SpeakButton(id: happ.id, text: happ.spokenSummary, subject: happ.title)
                }
            }
            if let happ, happ.creatorID != authService.user?.uid {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Report Happ", systemImage: "flag") {
                            reportTarget = ReportTarget(
                                kind: .happ, targetID: happ.id, happID: happ.id,
                                offenderID: happ.creatorID, offenderName: happ.creatorName,
                                summary: happ.title, hideID: happ.id
                            )
                        }
                        Button("Block \(happ.creatorName)", systemImage: "hand.raised", role: .destructive) {
                            pendingBlock = happ
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More options")
                    .accessibilityHint("Report this Happ or block the organiser.")
                }
            }
            if let happ, happ.creatorID == authService.user?.uid {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { isEditing = true }
                        .accessibilityLabel("Edit Happ")
                        .accessibilityHint("Change the title, place or time.")
                }
            }
        }
        .sheet(item: Binding(
            get: { reportTarget.map { ReportItem(target: $0) } },
            set: { if $0 == nil { reportTarget = nil } }
        )) { item in
            ReportSheet(target: item.target)
        }
        .confirmationDialog(
            "Block this person?",
            isPresented: Binding(get: { pendingBlock != nil }, set: { if !$0 { pendingBlock = nil } }),
            titleVisibility: .visible,
            presenting: pendingBlock
        ) { happ in
            Button("Block \(happ.creatorName)", role: .destructive) {
                guard let uid = authService.user?.uid else { return }
                Task {
                    await safetyStore.block(userID: happ.creatorID, name: happ.creatorName, currentUserID: uid, friendStore: friendStore)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: { happ in
            Text("You'll stop seeing \(happ.creatorName)'s Happs and photos, and you'll no longer be friends.")
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
                Text(happ.details.isEmpty ? "No description added." : ContentFilter.displayText(happ.details))
            }
 
            Section("Details") {
                LabeledContent("Category", value: happ.category.rawValue)
                    .accessibilityElement(children: .combine)
                LabeledContent("Location", value: happ.location)
                    .accessibilityElement(children: .combine)
                LabeledContent("When", value: happ.timeRangeText)
                    .accessibilityElement(children: .combine)
                LabeledContent("Organiser", value: happ.creatorName)
                    .accessibilityElement(children: .combine)
                LabeledContent("Going", value: "\(happ.participantIDs.count)")
                    .accessibilityElement(children: .combine)
            }
 
            if happ.hasEnded(at: Date()) {
                Section {
                    NavigationLink {
                        RecapTimelineView(happ: happ)
                    } label: {
                        Label("Recap", systemImage: "photo.on.rectangle.angled")
                    }
                    .accessibilityHint("Opens the photo timeline for this Happ.")
                }
            }
 
            Section {
                if happ.creatorID == currentUserID {
                    Button("Cancel Happ", role: .destructive) { pendingAction = .cancel }
                        .disabled(isWorking)
                        .frame(minHeight: 44)
                        .accessibilityHint("Asks you to confirm. It is removed for everyone who joined.")
                } else if happ.containsParticipant(currentUserID) {
                    Button("Leave Happ", role: .destructive) { pendingAction = .leave }
                        .disabled(isWorking)
                        .frame(minHeight: 44)
                        .accessibilityValue(isWorking ? "Working" : "")
                        .accessibilityHint("Asks you to confirm before you leave.")
                } else {
                    Button("Join Happ") {
                        setParticipation(happ: happ, userID: currentUserID, isJoining: true)
                    }
                    .disabled(isWorking)
                    .frame(minHeight: 44)
                    .accessibilityValue(isWorking ? "Working" : "")
                    .accessibilityHint("Adds you to the people going to \(happ.title).")
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
                AccessibilityNotification.Announcement(
                    isJoining ? "You joined \(happ.title)." : "You left \(happ.title)."
                ).post()
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

private struct ReportItem: Identifiable {
    let target: ReportTarget
    var id: String { target.kind.rawValue + target.targetID }
}

