//
//  GroupsView.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//
import SwiftUI
import FirebaseAuth

struct GroupsView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var groupStore: GroupStore
    
    @State private var isPresentingNew = false
    
    private var allIDs: [String] {
        (groupStore.groups + groupStore.invitations).flatMap { $0.memberIDs + $0.invitedIDs }
    }
    
    var body: some View {
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
        .task(id: allIDs) { await groupStore.resolveNames(for: allIDs) }
        .sheet(isPresented: $isPresentingNew) { GroupEditorView(group: nil) }
        .alert("Group Error", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { groupStore.clearError() }
        } message: {
            Text(groupStore.errorMessage ?? "Please try again.")
        }
    }
    
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { groupStore.errorMessage != nil }, set: { if !$0 { groupStore.clearError() } })
    }
    
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
    
    @ViewBuilder
    private func invitationRow(_ group: FriendGroup) -> some View {
        ResponseRow(
            title: group.name,
            subtitle: "From \(groupStore.name(for: group.ownerID))",
            onAccept: { respond(group, accept: true) },
            onDecline: { respond(group, accept: false) }
        )
    }
    
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
