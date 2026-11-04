//
//  GroupDetailView.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//


// CODE OVERVIEW
// Detail page for one group: members, pending invitations, an activity feed and the Leave or
// Delete action. It is pushed from GroupsView and receives only the group's id, then looks the
// group up in GroupStore.groups. Looking it up (instead of passing a copy) means the page updates
// live when the store's snapshot listener delivers a change, and shows "Group Not Found" if the
// group is deleted or the user leaves while the page is open.
// The owner sees Edit and Delete; other members see Report and Leave. Both destructive actions
// go through one confirmationDialog driven by the PendingAction enum.
import SwiftUI
import FirebaseAuth

/// Detail screen for a single group, identified by id.
struct GroupDetailView: View {
    /// Which destructive action the user has asked for and still has to confirm.
    private enum PendingAction {
        case leave, delete
    }
    
    /// Id of the group to show. Only the id is stored so the view always reads fresh data from the store.
    let groupID: String
    
    // Injected from the app root.
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var groupStore: GroupStore
    // Used to pop this screen after leaving or deleting.
    @Environment(\.dismiss) private var dismiss
    
    // Presents GroupEditorView as a sheet.
    @State private var isEditing = false
    // Non nil presents ReportSheet.
    @State private var reportTarget: ReportTarget?
    // Non nil shows the leave or delete confirmation.
    @State private var pendingAction: PendingAction?
    
    /// Current version of this group from the store, or nil if it no longer exists for this user.
    private var group: FriendGroup? {
        groupStore.groups.first { $0.id == groupID }
    }
    
    /// Signed in user's id, or an empty string (which never equals an owner id) when signed out.
    private var currentUserID: String {
        authService.user?.uid ?? ""
    }
    
    var body: some View {
        Group {
            // `if let group` uses Swift 5.7 shorthand for `if let group = group`.
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
        // The activity feed is a Firestore snapshot listener that only runs while this page is on screen:
        // started on appear and removed on disappear so it does not keep reading in the background.
        .onAppear { groupStore.listenToActivity(groupID: groupID) }
        .onDisappear { groupStore.stopActivity() }
    }
    
    /// The page content once the group exists: sections, toolbar, sheets and the confirmation dialog.
    private func content(for group: FriendGroup) -> some View {
        List {
            membersSection(group)
            if !group.invitedIDs.isEmpty {
                invitedSection(group)
            }
            activitySection
            actionsSection(group)
        }
        // .task(id:) re-runs whenever the member or invited ids change, looking up display names for ids
        // not yet cached. It is cancelled automatically when the view disappears.
        .task(id: group.memberIDs + group.invitedIDs) {
            await groupStore.resolveNames(for: group.memberIDs + group.invitedIDs)
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Non owners can report the group.
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
            // Only the owner can edit.
            if group.ownerID == currentUserID {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { isEditing = true }
                        .accessibilityLabel("Edit group")
                        .accessibilityHint("Change the name or who is invited.")
                }
            }
        }
        // Editor is reused for both create (group nil) and edit (group given).
        .sheet(isPresented: $isEditing) { GroupEditorView(group: group) }
        // Same optional-to-Identifiable Binding trick as in FriendsListView, to drive .sheet(item:).
        .sheet(item: Binding(
            get: { reportTarget.map { GroupReportItem(target: $0) } },
            set: { if $0 == nil { reportTarget = nil } }
        )) { item in
            ReportSheet(target: item.target)
        }
        // One dialog for both actions; the title and buttons switch on pendingAction.
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
    
    /// Bool binding for the dialog derived from the optional pendingAction.
    private var pendingIsPresented: Binding<Bool> {
        Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })
    }
    
    /// Members list. The owner row gets an "Owner" tag.
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
    
    /// Invited users who have not accepted yet.
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
    
    /// Newest first activity feed (sorting is done in GroupStore) with each item's date.
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
    
    /// Owner gets Delete; everyone else gets Leave. Both only set pendingAction, the dialog does the real work.
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
    
    /// Display name from the store's cache, with "(you)" appended for the current user.
    private func displayName(for id: String) -> String {
        let name = groupStore.name(for: id)
        return id == currentUserID ? "\(name) (you)" : name
    }
    
    /// Leaves the group (GroupStore records it in the activity feed using the user's name), then closes the page.
    private func leave(_ group: FriendGroup) {
        guard let user = authService.user else { return }
        Task {
            await groupStore.leave(group, userID: user.uid, userName: user.displayName ?? "Someone")
            dismiss()
        }
    }
    
    /// Deletes the whole group, then closes the page. Only reachable by the owner.
    private func delete(_ group: FriendGroup) {
        Task {
            await groupStore.deleteGroup(group)
            dismiss()
        }
    }
}

/// Identifiable wrapper so a ReportTarget can drive .sheet(item:).
private struct GroupReportItem: Identifiable {
    let target: ReportTarget
    var id: String { target.kind.rawValue + target.targetID }
}

