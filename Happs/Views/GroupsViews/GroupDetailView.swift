//
//  GroupDetailView.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//


import SwiftUI
import FirebaseAuth

struct GroupDetailView: View {
    private enum PendingAction {
        case leave, delete
    }
    
    let groupID: String
    
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var groupStore: GroupStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var isEditing = false
    @State private var reportTarget: ReportTarget?
    @State private var pendingAction: PendingAction?
    
    private var group: FriendGroup? {
        groupStore.groups.first { $0.id == groupID }
    }
    
    private var currentUserID: String {
        authService.user?.uid ?? ""
    }
    
    var body: some View {
        Group {
            if let group {
                content(for: group)
            } else {
                ContentUnavailableView(
                    "Group Not Found",
                    systemImage: "person.3",
                    description: Text("You may have left this group, or it was deleted.")
                )
            }
        }
        .onAppear { groupStore.listenToActivity(groupID: groupID) }
        .onDisappear { groupStore.stopActivity() }
    }
    
    private func content(for group: FriendGroup) -> some View {
        List {
            membersSection(group)
            if !group.invitedIDs.isEmpty {
                invitedSection(group)
            }
            activitySection
            actionsSection(group)
        }
        .task(id: group.memberIDs + group.invitedIDs) {
            await groupStore.resolveNames(for: group.memberIDs + group.invitedIDs)
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if group.ownerID != currentUserID {
                ToolbarItem(placement: .primaryAction) {
                    Button("Report", systemImage: "flag") {
                        reportTarget = ReportTarget(
                            kind: .group, targetID: group.id, happID: nil,
                            offenderID: group.ownerID,
                            offenderName: groupStore.names[group.ownerID] ?? "Group owner",
                            summary: group.name, hideID: nil
                        )
                    }
                    .accessibilityLabel("Report group")
                    .accessibilityHint("Tells Happs this group breaks the community rules.")
                }
            }
            if group.ownerID == currentUserID {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { isEditing = true }
                        .accessibilityLabel("Edit group")
                        .accessibilityHint("Change the name or who is invited.")
                }
            }
        }
        .sheet(isPresented: $isEditing) { GroupEditorView(group: group) }
        .sheet(item: Binding(
            get: { reportTarget.map { GroupReportItem(target: $0) } },
            set: { if $0 == nil { reportTarget = nil } }
        )) { item in
            ReportSheet(target: item.target)
        }
        .confirmationDialog(
            pendingAction == .delete ? "Delete this group?" : "Leave this group?",
            isPresented: pendingIsPresented,
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            switch action {
            case .delete:
                Button("Delete Group", role: .destructive) { delete(group) }
            case .leave:
                Button("Leave Group", role: .destructive) { leave(group) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { action in
            switch action {
            case .delete: Text("Everyone in it is told, and it can't be undone.")
            case .leave: Text("You'll need a new invite to rejoin.")
            }
        }
    }
    
    private var pendingIsPresented: Binding<Bool> {
        Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })
    }
    
    private func membersSection(_ group: FriendGroup) -> some View {
        Section("Members (\(group.memberIDs.count))") {
            ForEach(group.memberIDs, id: \.self) { id in
                let isOwner = id == group.ownerID
                HStack {
                    Text(displayName(for: id))
                    Spacer()
                    if isOwner {
                        Text("Owner").font(.caption).foregroundStyle(Color.happsGreenText)
                    }
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(isOwner ? "\(displayName(for: id)), owner" : displayName(for: id))
            }
        }
    }
    
    private func invitedSection(_ group: FriendGroup) -> some View {
        Section("Invited") {
            ForEach(group.invitedIDs, id: \.self) { id in
                HStack {
                    Text(displayName(for: id))
                    Spacer()
                    Text("Pending").font(.caption).foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(displayName(for: id)), invitation pending")
            }
        }
    }
    
    private var activitySection: some View {
        Section("Activity") {
            if groupStore.activity.isEmpty {
                Text("No activity yet.").foregroundStyle(.secondary)
            } else {
                ForEach(groupStore.activity) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.text)
                        if let date = item.createdAt {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
    
    private func actionsSection(_ group: FriendGroup) -> some View {
        Section {
            if group.ownerID == currentUserID {
                Button("Delete Group", role: .destructive) { pendingAction = .delete }
                    .frame(minHeight: 44)
                    .accessibilityHint("Asks you to confirm. Deleting cannot be undone.")
            } else {
                Button("Leave Group", role: .destructive) { pendingAction = .leave }
                    .frame(minHeight: 44)
                    .accessibilityHint("Asks you to confirm before you leave.")
            }
        }
    }
    
    private func displayName(for id: String) -> String {
        let name = groupStore.name(for: id)
        return id == currentUserID ? "\(name) (you)" : name
    }
    
    private func leave(_ group: FriendGroup) {
        guard let user = authService.user else { return }
        Task {
            await groupStore.leave(group, userID: user.uid, userName: user.displayName ?? "Someone")
            dismiss()
        }
    }
    
    private func delete(_ group: FriendGroup) {
        Task {
            await groupStore.deleteGroup(group)
            dismiss()
        }
    }
}

private struct GroupReportItem: Identifiable {
    let target: ReportTarget
    var id: String { target.kind.rawValue + target.targetID }
}
