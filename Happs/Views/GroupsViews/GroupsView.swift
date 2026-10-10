//
//  GroupsView.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//
import SwiftUI

struct GroupsView: View {
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var friendStore: FriendStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var editingGroup: FriendGroup?
    @State private var isPresentingNew = false
    
    var body: some View {
        NavigationStack {
            List {
                if groupStore.groups.isEmpty {
                    Text("No groups yet. Tap + to make one.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(groupStore.groups) { group in
                        groupRow(group)
                    }
                    .onDelete(perform: deleteGroups)
                }
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Group", systemImage: "plus") { isPresentingNew = true }
                }
            }
            .sheet(isPresented: $isPresentingNew) { GroupEditorView(group: nil) }
            .sheet(item: $editingGroup) { group in GroupEditorView(group: group) }
            .alert("Group Error", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { groupStore.clearError() }
            } message: {
                Text(groupStore.errorMessage ?? "Please try again.")
            }
        }
    }
    
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { groupStore.errorMessage != nil }, set: { if !$0 { groupStore.clearError() } })
    }
    
    private func groupRow(_ group: FriendGroup) -> some View {
        Button { editingGroup = group } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(memberSummary(for: group))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func memberSummary(for group: FriendGroup) -> String {
        let names = friendStore.friends
            .filter { group.memberIDs.contains($0.id) }
            .map(\.displayName)
        return names.isEmpty ? "No members" : names.joined(separator: ", ")
    }
    
    private func deleteGroups(at offsets: IndexSet) {
        let doomed = offsets.map { groupStore.groups[$0] }
        Task {
            for group in doomed {
                await groupStore.deleteGroup(group)
            }
        }
    }
}
