//
//  HappDetailView.swift
//  Happs
//
//  Created by Rafa Abes on 9/21/26.
//

// CODE OVERVIEW
// Detail screen for one Happ (View layer). It is given only a happID, not a Happ value, and
// looks the Happ up in HappStore each time. That way the screen updates live when the store's
// data changes (someone joins, the organiser edits) instead of showing a stale copy. The view
// shows different actions by role: organiser (Edit, Cancel Happ), participant (Leave) or
// visitor (Join), plus a Recap link once the Happ has ended. Writes go through HappStore;
// blocking goes through SafetyStore; reporting opens ReportSheet.
//
import SwiftUI
import FirebaseAuth
 
/// Shows one Happ and the actions the current user may take on it.
struct HappDetailView: View {
        /// Destructive actions that need a confirmation dialog before running.
    private enum PendingAction {
        case leave, cancel
    }
 
        /// Gives the signed-in user's uid, used to decide the role (organiser, participant, visitor).
    @EnvironmentObject private var authService: AuthService
        /// Source of truth for all Happs; also performs join, leave and delete.
    @EnvironmentObject private var happStore: HappStore
        /// Closes this screen (used after cancel or block).
    @Environment(\.dismiss) private var dismiss
        /// ID of the Happ to show. Only the ID is stored so the view always reads fresh data from the store.
    let happID: String
 
        /// Handles blocking users.
    @EnvironmentObject private var safetyStore: SafetyStore
        /// Passed to block(...) so the friendship can be removed at the same time.
    @EnvironmentObject private var friendStore: FriendStore
        /// When non-nil, ReportSheet is shown for this target.
    @State private var reportTarget: ReportTarget?
        /// The Happ whose organiser the person may be about to block (drives the confirmation dialog).
    @State private var pendingBlock: Happ?
        /// True while a join, leave or delete request runs; disables buttons to prevent double taps.
    @State private var isWorking = false
        /// Presents the editor sheet.
    @State private var isEditing = false
        /// Which confirmation dialog is open, if any.
    @State private var pendingAction: PendingAction?
        /// Message for the error alert; nil means no alert.
    @State private var errorMessage: String?
 
        /// The live Happ from the store, or nil if it was deleted (the body then shows "Happ Not Found").
    private var happ: Happ? {
        happStore.happs.first { $0.id == happID }
    }
 
        /// Top-level layout: content or a not-found state, with toolbar items and all dialogs attached.
    var body: some View {
        Group {
                        // Needs both the Happ and a signed-in user; otherwise show the unavailable state.
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
                // Toolbar items depend on role: everyone gets read-aloud, non-organisers get Report/Block, the organiser gets Edit.
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
                // sheet(item:) needs an Identifiable value, so the optional ReportTarget is wrapped in a
                // ReportItem on the fly. The custom Binding clears reportTarget when the sheet closes.
        .sheet(item: Binding(
            get: { reportTarget.map { ReportItem(target: $0) } },
            set: { if $0 == nil { reportTarget = nil } }
        )) { item in
            ReportSheet(target: item.target)
        }
                // confirmationDialog(isPresented:presenting:) needs a Bool, so a Binding is derived from the optional pendingBlock.
        .confirmationDialog(
            "Block this person?",
            isPresented: Binding(get: { pendingBlock != nil }, set: { if !$0 { pendingBlock = nil } }),
            titleVisibility: .visible,
            presenting: pendingBlock
        ) { happ in
            Button("Block \(happ.creatorName)", role: .destructive) {
                guard let uid = authService.user?.uid else { return }
                                // Task bridges from the synchronous button closure into async code; dismiss after the block completes.
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
                // One dialog serves both Leave and Cancel; the title and the buttons are chosen from pendingAction.
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
 
        /// The List body for a loaded Happ: description, details, optional recap link and the role-based action button.
        /// - Parameters:
        ///   - happ: The Happ to render.
        ///   - currentUserID: Used to decide organiser, participant or visitor.
    private func content(for happ: Happ, currentUserID: String) -> some View {
        List {
            Section {
                                // ContentFilter.displayText filters unwanted words in text written by other users.
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
 
                        // The recap (photo timeline) is only offered once the Happ has ended (happ.hasEnded).
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
 
        /// Bool binding derived from pendingAction so a dialog can be driven by an optional value.
    private var pendingIsPresented: Binding<Bool> {
        Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })
    }
 
        /// Same pattern for the error alert: it shows while errorMessage is non-nil.
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
 
        /// Leaves the Happ for the current user.
    private func leaveHapp() {
        guard let happ, let userID = authService.user?.uid else { return }
        setParticipation(happ: happ, userID: userID, isJoining: false)
    }
 
        /// Joins or leaves via HappStore.toggleParticipation, then announces the result to VoiceOver.
        /// - Parameters:
        ///   - happ: The Happ being changed.
        ///   - userID: The current user.
        ///   - isJoining: true to join, false to leave.
    private func setParticipation(happ: Happ, userID: String, isJoining: Bool) {
        isWorking = true
                    // defer guarantees the buttons are re-enabled whether the call succeeds or throws.
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
 
        /// Deletes the Happ (reached through the Cancel Happ confirmation) and closes the screen on success.
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

/// Wrapper that makes a ReportTarget Identifiable so it can drive sheet(item:). The id combines kind and target ID.
private struct ReportItem: Identifiable {
    let target: ReportTarget
    var id: String { target.kind.rawValue + target.targetID }
}

