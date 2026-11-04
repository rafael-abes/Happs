//
//  GroupsView.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//
// CODE OVERVIEW
// List of the user's groups plus pending invitations, reached from the Groups row on the Friends tab.
// Data comes from GroupStore (kept live by its Firestore snapshot listener); accepting or declining
// an invitation is delegated back to the store. The "+" button opens GroupEditorView in create mode.
// Rows push GroupDetailView by group id. Member names are resolved lazily because groups store only
// user ids, so the view asks the store to look up any names it has not cached yet.
import SwiftUI
import FirebaseAuth

/// Lists invitations and groups; entry point to creating, opening and responding to groups.
struct GroupsView: View {
    // Injected from the app root.
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var groupStore: GroupStore
    
    // Presents the create group sheet.
    @State private var isPresentingNew = false
    
    /// Every user id appearing in any group or invitation, used to know which names to resolve.
    private var allIDs: [String] {
        (groupStore.groups + groupStore.invitations).flatMap { $0.memberIDs + $0.invitedIDs }
    }
    
    var body: some View {
        // No NavigationStack here: this view is pushed inside the Friends tab's stack.
        List {
            if !groupStore.invitations.isEmpty {
                Section("Invitations") {
                    ForEach(groupStore.invitations) { group in
                        invitationRow(group)
                    }
                }
            }
            
            Section("My Groups") {
                if groupStore.groups.isEmpty {
                    Text("You're not in any groups yet. Tap + to make one.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(groupStore.groups) { group in
                        NavigationLink {
                            GroupDetailView(groupID: group.id)
                        } label: {
                            groupRow(group)
                        }
                        .accessibilityHint("Opens the group.")
                    }
                }
            }
        }
        .navigationTitle("Groups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Group", systemImage: "plus") { isPresentingNew = true }
                    .accessibilityLabel("New group")
                    .accessibilityHint("Opens a form to create a group.")
            }
        }
        // Re-runs when the set of ids changes and fetches display names the store has not cached yet.
        .task(id: allIDs) { await groupStore.resolveNames(for: allIDs) }
        // group nil means create mode.
        .sheet(isPresented: $isPresentingNew) { GroupEditorView(group: nil) }
        .alert("Group Error", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { groupStore.clearError() }
        } message: {
            Text(groupStore.errorMessage ?? "Please try again.")
        }
    }
    
    /// Bool binding for the error alert derived from GroupStore's errorMessage.
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { groupStore.errorMessage != nil }, set: { if !$0 { groupStore.clearError() } })
    }
    
    /// One group row: name, owner tag and member count, merged into a single VoiceOver element.
    private func groupRow(_ group: FriendGroup) -> some View {
        let isOwner = group.ownerID == authService.user?.uid
        let members = "\(group.memberIDs.count) member\(group.memberIDs.count == 1 ? "" : "s")"
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(group.name).font(.headline)
                if isOwner {
                    Text("Owner").font(.caption).foregroundStyle(Color.happsGreenText)
                }
            }
            Text(members)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.name), \(isOwner ? "you are the owner, " : "")\(members)")
    }
    
    /// Invitation row with accept and decline buttons, using the shared ResponseRow component.
    @ViewBuilder
    private func invitationRow(_ group: FriendGroup) -> some View {
        ResponseRow(
            title: group.name,
            subtitle: "From \(groupStore.name(for: group.ownerID))",
            onAccept: { respond(group, accept: true) },
            onDecline: { respond(group, accept: false) }
        )
    }
    
    /// Accepts or declines an invitation. The user's name is passed so the store can record it in the group's activity.
    private func respond(_ group: FriendGroup, accept: Bool) {
        guard let user = authService.user else { return }
        Task {
            await groupStore.respond(
                to: group,
                accept: accept,
                userID: user.uid,
                userName: user.displayName ?? "Someone"
            )
        }
    }
}
