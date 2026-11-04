//
//  GroupEditorView.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//
// CODE OVERVIEW
// Form sheet used for both creating a new group and editing an existing one. If `group` is nil
// it is "create" mode, otherwise "edit" mode, so one view serves both and the UI cannot drift.
// The user types a name and ticks friends from FriendStore.friends; saving calls GroupStore
// (createGroup or updateGroup), which does the Firestore writes and sends invitations.
// The form never adds people directly: selected friends receive an invitation they must accept.
// Selection state is local (@State Set of ids), seeded in init from the existing group.
import SwiftUI
import FirebaseAuth

/// Create or edit form for a group. Pass nil to create a new group.
struct GroupEditorView: View {
    /// The group being edited, or nil when creating.
    let group: FriendGroup?
    
    // Injected from the app root.
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var friendStore: FriendStore
    // Closes the sheet.
    @Environment(\.dismiss) private var dismiss
    
    // Declared without a default because init seeds them from the group.
    @State private var name: String
    // Ids of friends currently ticked.
    @State private var selectedIDs: Set<String>
    // True while the save request runs; disables Save and blocks swipe to dismiss.
    @State private var isSaving = false
    // Non nil shows the error alert.
    @State private var errorMessage: String?
    
    /// Seeds the @State values. @State cannot be given an initial value from a parameter in the property
    /// declaration, so the wrappers are built directly with State(initialValue:).
    /// In edit mode the owner is left out of the selection (the owner is always kept), while members
    /// and still pending invites start ticked.
    init(group: FriendGroup?) {
        self.group = group
        _name = State(initialValue: group?.name ?? "")
        let existing = (group?.memberIDs ?? []).filter { $0 != group?.ownerID } + (group?.invitedIDs ?? [])
        _selectedIDs = State(initialValue: Set(existing))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Group name") {
                    TextField("e.g. Badminton crew", text: $name)
                        .accessibilityLabel("Group name")
                }
                
                Section {
                    if friendStore.friends.isEmpty {
                        Text("Add some friends first, then you can group them.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(friendStore.friends) { friend in
                            friendRow(friend)
                        }
                    }
                } header: {
                    Text("Friends")
                } footer: {
                    Text("Friends you pick get an invitation they can accept or decline.")
                }
            }
            // Title reflects the mode.
            .navigationTitle(group == nil ? "New Group" : "Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityHint("Closes without saving.")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(group == nil ? "Send Invites" : "Save") { save() }
                        .disabled(isSaving)
                        .accessibilityValue(isSaving ? "Saving" : "")
                        .accessibilityHint(group == nil ? "Creates the group and invites the selected friends." : "Saves your changes.")
                }
            }
            // Stops the user swiping the sheet away mid save, which could hide a failure.
            .interactiveDismissDisabled(isSaving)
            .alert("Couldn't Save Group", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }
    
    /// Bool binding for the error alert derived from the optional errorMessage.
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    
    /// "Member" or "Invited" if the friend already has that relationship to the group being edited, else nil.
    private func stateLabel(for friend: UserProfile) -> String? {
        if group?.memberIDs.contains(friend.id) == true { return "Member" }
        if group?.invitedIDs.contains(friend.id) == true { return "Invited" }
        return nil
    }
    
    /// One tickable friend row, built as a single button that toggles selection.
    private func friendRow(_ friend: UserProfile) -> some View {
        let isSelected = selectedIDs.contains(friend.id)
        let state = stateLabel(for: friend)
        return Button { toggle(friend.id) } label: {
            HStack {
                AvatarView(symbol: friend.avatarSymbol, photo: friend.avatarPhoto, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(friend.displayName).foregroundStyle(.primary)
                    if let state {
                        Text(state).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .frame(minHeight: 44)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [friend.displayName, state?.lowercased(), isSelected ? "selected" : "not selected"]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
        .accessibilityHint("Double tap to select or deselect.")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
    
    /// Adds the id to the selection if absent, removes it if present.
    private func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
    
    /// Validates sign in, then creates or updates the group through GroupStore. Dismisses only on success;
    /// on failure the alert shows the store's error (for example an invalid name).
    private func save() {
        guard let userID = authService.user?.uid else {
            errorMessage = "Sign in again before saving."
            return
        }
        // Set before the Task starts so a fast second tap cannot start another save.
        isSaving = true
        Task {
            // defer clears the flag on success and failure.
            defer { isSaving = false }
            do {
                // Edit mode when a group exists, create mode otherwise.
                if let group {
                    try await groupStore.updateGroup(group, name: name, selectedIDs: selectedIDs)
                } else {
                    try await groupStore.createGroup(name: name, ownerID: userID, inviteIDs: Array(selectedIDs))
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

