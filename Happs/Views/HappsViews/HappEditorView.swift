//
//  HappEditorView.swift
//  Happs
//
//  Created by Rafa Abes on 9/21/26.
//
// CODE OVERVIEW
// One form used for both creating and editing a Happ (View layer). Pass a Happ to edit it, or
// nothing to create. The form does not edit the model directly: every field is a local @State
// value seeded in init from a HappDraft, and only save() sends the values to HappStore. That
// way Cancel simply discards the edits. HappDraft is the shared "bag of fields" that the AI
// assistant (AssistantSheet) and Ticketmaster picker (EventSuggestionsView) also produce, so
// all three sources fill the same form through apply(_:). Create-only extras (events, group
// invites) are hidden when editing.
//
import SwiftUI
import CoreLocation
import FirebaseAuth

/// The Create/Edit Happ form. Pushed or presented inside a NavigationStack by its callers.
struct HappEditorView: View {
        /// The Happ being edited, or nil when creating a new one. Decides titles, which sections show and which store call save() makes.
    private let editing: Happ?

        /// Provides the signed-in user (used as the creator and for the invite filter).
    @EnvironmentObject private var authService: AuthService
        /// Performs createHapp and updateHapp.
    @EnvironmentObject private var happStore: HappStore
        /// The user's friend groups, offered as one-tap invites.
    @EnvironmentObject private var groupStore: GroupStore
        /// Provides the on-campus friend IDs passed as audienceIDs when creating.
    @EnvironmentObject private var friendStore: FriendStore
        /// Used only to hide the Describe it button when AI is switched off (aiService.isEnabled).
    @EnvironmentObject private var aiService: AIService
        /// Closes the form after saving or cancelling.
    @Environment(\.dismiss) private var dismiss

        // The fields below are @State copies of the draft so editing is local until Save is pressed.
        /// Happ title text.
    @State private var title: String
        /// Free-text notes.
    @State private var details: String
        /// Human-readable place name shown in the Location row.
    @State private var location: String
        /// Map coordinate for the place, nil if none was chosen (a Happ can exist without one).
    @State private var selectedCoordinate: CLLocationCoordinate2D?
        /// True when the chosen place is outside the campus boundary.
    @State private var isOffCampus: Bool
        /// Segmented-picker choice of HappCategory.
    @State private var category: HappCategory
        /// When the Happ starts.
    @State private var startTime: Date
        /// Whether the person turned on the optional end time toggle.
    @State private var hasEndTime: Bool
        /// End time value. Kept even when the toggle is off so the picker has a sensible value; only used if hasEndTime is true.
    @State private var endTime: Date
        /// IDs of groups to invite (a Set so toggling twice cannot add duplicates). Create only.
    @State private var invitedGroupIDs: Set<String> = []
        /// True while save() runs; disables Save and blocks swipe-to-dismiss.
    @State private var isSaving = false
        /// Presents LocationPickerView.
    @State private var isPresentingLocationPicker = false
        /// Message for the save error alert.
    @State private var errorMessage: String?
        /// Presents AssistantSheet (the Describe it feature).
    @State private var showAssistant = false

        /// - Parameter happ: Happ to edit, or nil to start a blank form.
    init(happ: Happ? = nil) {
        editing = happ
                // Build the starting values from a HappDraft: from the Happ when editing, or a blank draft when creating.
        let seed = happ.map { HappDraft(happ: $0) } ?? HappDraft.blank
                // `_title = State(initialValue:)` sets the wrapped @State storage directly. This is the way to
                // seed @State from an init parameter, because self.title cannot be assigned before init finishes.
        _title = State(initialValue: seed.title)
        _details = State(initialValue: seed.details)
        _location = State(initialValue: seed.location)
        _selectedCoordinate = State(initialValue: seed.coordinate)
        _isOffCampus = State(initialValue: seed.isOffCampus)
        _category = State(initialValue: seed.category)
        _startTime = State(initialValue: seed.startTime)
        _hasEndTime = State(initialValue: seed.endTime != nil)
                // Default end time is one hour after start, so the picker has a valid value if the toggle is switched on.
        _endTime = State(initialValue: seed.endTime ?? seed.startTime.addingTimeInterval(60 * 60))
    }

        /// The form: optional Describe it button, then title, location, time, category, invites and details.
    var body: some View {
        Form {
                        // Only offered when the AI feature is available.
            if aiService.isEnabled {
                Section {
                    Button { showAssistant = true } label: {
                        Label("Describe it", systemImage: "sparkles")
                            .frame(minHeight: 44)
                    }
                    .accessibilityHint("Opens an assistant that fills in this form from what you say or type.")
                }
            }
                        // The event picker and group invites only make sense for a new Happ.
            if editing == nil {
                eventSection
            }

            Section("Happ Title") {
                HStack {
                    TextField("What's happening?", text: $title)
                        .accessibilityLabel("Happ title")
                    MicButton(text: $title, id: "editor-title", fieldName: "title")
                }
            }

            Section("Location") {
                Button {
                    isPresentingLocationPicker = true
                } label: {
                    HStack {
                        Text(location.isEmpty ? "Add Location" : location)
                            .foregroundStyle(location.isEmpty ? .secondary : .primary)
                        Spacer()
                        Image(systemName: isOffCampus ? "location.slash" : "mappin.and.ellipse")
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Location")
                .accessibilityValue(location.isEmpty ? "Not set" : (isOffCampus ? "\(location), off campus" : location))
                .accessibilityHint("Opens a map to choose where it is happening.")
                .accessibilityAddTraits(.isButton)
            }

            whenSection

            Section("Category") {
                Picker("Category", selection: $category) {
                    ForEach(HappCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
            }

            if editing == nil {
                inviteSection
            }

            Section("Details") {
                HStack(alignment: .top) {
                    TextField("Add notes or anything else", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Details")
                    MicButton(text: $details, id: "editor-details", fieldName: "details")
                }
            }
        }
        .navigationTitle(editing == nil ? "New Happ" : "Edit Happ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .accessibilityHint("Closes without saving.")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editing == nil ? "Add Happ" : "Save") { save() }
                    .disabled(isSaving)
                    .accessibilityValue(isSaving ? "Saving" : "")
                    .accessibilityHint(editing == nil ? "Creates this Happ." : "Saves your changes.")
            }
        }
                // Keeps the end time valid: if the start moves past the end, push the end to one hour later.
        .onChange(of: startTime) { _, newStart in
            if endTime <= newStart {
                endTime = newStart.addingTimeInterval(60 * 60)
            }
        }
                // Prevents swiping the sheet away mid-save.
        .interactiveDismissDisabled(isSaving)
                // The picker writes back through bindings, so the form just reads location, coordinate and off-campus flag.
        .sheet(isPresented: $isPresentingLocationPicker) {
            LocationPickerView(
                category: category,
                selectedName: $location,
                selectedCoordinate: $selectedCoordinate,
                isOffCampus: $isOffCampus
            )
        }
                // The assistant returns a draft via closure; apply fills the form and the chosen group is added to the invites.
        .sheet(isPresented: $showAssistant) {
            AssistantSheet { draft, groupID in
                apply(draft)
                if let groupID, editing == nil {
                    invitedGroupIDs.insert(groupID)
                }
            }
        }
                // errorIsPresented derives a Bool from the optional message; clearing the alert resets the message.
        .alert("Couldn't Save Happ", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

        /// Link to EventSuggestionsView. Passing `apply` as onSelect fills this form from the chosen event.
    private var eventSection: some View {
        Section {
            NavigationLink {
                EventSuggestionsView(onSelect: apply)
            } label: {
                Label("Start from a Ticketmaster event", systemImage: "ticket.fill")
                    .frame(minHeight: 44)
            }
            .accessibilityHint("Browse upcoming events and turn one into a Happ.")
        } footer: {
            Text("Browse upcoming events near campus and turn one into a Happ.")
        }
    }

        /// Start time, optional end time toggle and end picker. The end picker's range starts at startTime so end cannot precede start.
    private var whenSection: some View {
        Section {
            DatePicker("Starts", selection: $startTime)
            Toggle("Set an end time", isOn: $hasEndTime)
            if hasEndTime {
                DatePicker("Ends", selection: $endTime, in: startTime...)
            }
        } header: {
            Text("When")
        } footer: {
            if !hasEndTime {
                Text("With no end time, a Happ stays up for 3 hours after it starts.")
            }
        }
    }

        /// One toggle per group so an invite can be set without leaving the form.
    private var inviteSection: some View {
        Section {
            if groupStore.groups.isEmpty {
                Text("Make a group in the Friends tab to invite people in one tap.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groupStore.groups) { group in
                    Toggle(isOn: inviteBinding(for: group)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                            Text("\(group.memberIDs.count) members")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("Invite \(group.name), \(group.memberIDs.count) \(group.memberIDs.count == 1 ? "member" : "members")")
                    .accessibilityHint("Invites everyone in this group when you add the Happ.")
                }
            }
        } header: {
            Text("Invite a group")
        }
    }

        /// Adapts the Set of invited IDs into the Bool binding a Toggle needs.
        /// - Parameter group: The group the toggle controls.
    private func inviteBinding(for group: FriendGroup) -> Binding<Bool> {
        Binding(
            get: { invitedGroupIDs.contains(group.id) },
            set: { isOn in
                if isOn {
                    invitedGroupIDs.insert(group.id)
                } else {
                    invitedGroupIDs.remove(group.id)
                }
            }
        )
    }

        /// Member IDs of all selected groups, de-duplicated through a Set and excluding the current user.
    private var invitedFriendIDs: [String] {
        let members = groupStore.groups
            .filter { invitedGroupIDs.contains($0.id) }
            .flatMap(\.memberIDs)
            .filter { $0 != authService.user?.uid }
        return Array(Set(members))
    }

        /// Bool binding derived from the optional errorMessage for the alert.
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

        /// Copies every field of a draft into the form's @State. Used by the AI assistant and the Ticketmaster picker.
    private func apply(_ seed: HappDraft) {
        title = seed.title
        details = seed.details
        location = seed.location
        selectedCoordinate = seed.coordinate
        isOffCampus = seed.isOffCampus
        category = seed.category
        startTime = seed.startTime
        hasEndTime = seed.endTime != nil
        endTime = seed.endTime ?? seed.startTime.addingTimeInterval(60 * 60)
    }

        /// Validates the sign-in, then creates or updates the Happ asynchronously and closes the form on success.
    private func save() {
        guard let user = authService.user else {
            errorMessage = "Sign in again before saving."
            return
        }

                // The optional end time is only sent if the toggle is on.
        let finalEnd: Date? = hasEndTime ? endTime : nil

        isSaving = true
                // Task bridges the button tap into async code. The defer re-enables the UI on success or failure.
        Task {
            defer { isSaving = false }
            do {
                if let editing {
                    try await happStore.updateHapp(
                        editing,
                        title: title,
                        details: details,
                        location: location,
                        category: category,
                        startTime: startTime,
                        endTime: finalEnd,
                        latitude: selectedCoordinate?.latitude,
                        longitude: selectedCoordinate?.longitude,
                        isOffCampus: isOffCampus
                    )
                } else {
                                        // Create path: also records who is invited and the audience of on-campus friends.
                                        // (assumed reason: so the store can notify or show it to them; see HappStore.createHapp.)
                    try await happStore.createHapp(
                        title: title,
                        details: details,
                        location: location,
                        category: category,
                        startTime: startTime,
                        endTime: finalEnd,
                        creatorID: user.uid,
                                                // Fallback chain for the organiser name: display name, then email, then a generic word.
                        creatorName: user.displayName ?? user.email ?? "Someone",
                        latitude: selectedCoordinate?.latitude,
                        longitude: selectedCoordinate?.longitude,
                        isOffCampus: isOffCampus,
                        invitedIDs: invitedFriendIDs,
                        audienceIDs: friendStore.onCampusFriendIDs
                    )
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
