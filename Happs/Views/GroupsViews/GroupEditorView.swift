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
        _selectedIDs = State(initialValue: Set(group?.memberIDs ?? []))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Group name") {
                    TextField("e.g. Badminton crew", text: $name)
                }
                
                Section("Members") {
                    if friendStore.friends.isEmpty {
                        Text("Add some friends first, then you can group them.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(friendStore.friends) { friend in
                            memberRow(friend)
                        }
                    }
                }
            }
            .navigationTitle(group == nil ? "New Group" : "Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(isSaving)
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
    
    private func memberRow(_ friend: UserProfile) -> some View {
        Button { toggle(friend.id) } label: {
            HStack {
                Text(friend.displayName).foregroundStyle(.primary)
                Spacer()
                if selectedIDs.contains(friend.id) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Image(systemName: "circle").foregroundStyle(.secondary)
                }
            }
        }
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
                    try await groupStore.updateGroup(group, name: name, memberIDs: Array(selectedIDs))
                } else {
                    try await groupStore.createGroup(name: name, ownerID: userID, memberIDs: Array(selectedIDs))
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
