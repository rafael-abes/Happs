//
//  GroupEditorView.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//
import SwiftUI
import FirebaseAuth

struct GroupEditorView: View {
    let group: FriendGroup?
    
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var friendStore: FriendStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var selectedIDs: Set<String>
    @State private var isSaving = false
    @State private var errorMessage: String?
    
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
            .interactiveDismissDisabled(isSaving)
            .alert("Couldn't Save Group", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }
    
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    
    private func stateLabel(for friend: UserProfile) -> String? {
        if group?.memberIDs.contains(friend.id) == true { return "Member" }
        if group?.invitedIDs.contains(friend.id) == true { return "Invited" }
        return nil
    }
    
    private func friendRow(_ friend: UserProfile) -> some View {
        let isSelected = selectedIDs.contains(friend.id)
        let state = stateLabel(for: friend)
        return Button { toggle(friend.id) } label: {
            HStack {
                AvatarView(symbol: friend.avatarSymbol, size: 32)
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
    
    private func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
    
    private func save() {
        guard let userID = authService.user?.uid else {
            errorMessage = "Sign in again before saving."
            return
        }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
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
