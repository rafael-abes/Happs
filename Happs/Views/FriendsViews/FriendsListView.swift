//
//  FriendsListView.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//
// CODE OVERVIEW
// The Friends tab. Shows the friends list (with incoming requests and a link to Groups) and can
// switch to the campus map (FriendsMapView) with a toolbar toggle. It is a View only: friend data
// comes from FriendStore, group counts from GroupStore, and blocking goes through SafetyStore, all
// injected with @EnvironmentObject. The stores keep Firestore snapshot listeners running, so this
// view updates by itself whenever a friend, request or invitation changes.
// Design: destructive actions (remove, block) are always confirmed with a dialog, and each row
// offers the same actions as swipe, context menu and VoiceOver custom action. Pending choices
// are held in optional @State values (friendPendingRemoval, blockCandidate) that drive the dialogs.
import SwiftUI
import FirebaseAuth

/// Friends tab root: list or map of friends, plus requests, groups link, add friend sheet, report and block flows.
struct FriendsListView: View {
    // App wide stores injected at the root. The views read them; they do not own the data.
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var groupStore: GroupStore
    // Used to stack row content vertically at accessibility text sizes.
    @Environment(\.dynamicTypeSize) private var typeSize
    
    // Drives the Add Friends sheet.
    @State private var isPresentingAddFriends = false
    // false shows the list, true shows the map. Plain @State because it is a purely local view choice.
    @State private var showsMap = false
    // Friend the user has asked to remove; non nil shows the confirmation dialog.
    @State private var friendPendingRemoval: UserProfile?
    // Used to block users and to hide reported content.
    @EnvironmentObject private var safetyStore: SafetyStore
    // Non nil presents ReportSheet for this target.
    @State private var reportTarget: ReportTarget?
    // Tuple of the user's id and name awaiting block confirmation. Non nil shows the block dialog.
    @State private var blockCandidate: (id: String, name: String)?
    
    var body: some View {
        // Own NavigationStack for this tab, so pushes (Groups) stay inside the Friends tab.
        NavigationStack {
            // Group lets the if/else swap the whole content between list and map without extra containers.
            Group {
                if showsMap {
                    FriendsMapView()
                } else {
                    friendsList
                }
            }
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(showsMap ? "List" : "Map", systemImage: showsMap ? "list.bullet" : "map") {
                        showsMap.toggle()
                    }
                    .accessibilityLabel(showsMap ? "Show list" : "Show map")
                    .accessibilityHint("Switches between your friends list and the campus map.")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Friends", systemImage: "plus") { isPresentingAddFriends = true }
                        .accessibilityHint("Opens a search to find and add friends.")
                }
            }
            // Sheet presented by a Bool flag.
            .sheet(isPresented: $isPresentingAddFriends) { AddFriendsView() }
            // .sheet(item:) needs an Identifiable value, but reportTarget is optional and not Identifiable.
            // This Binding wraps it in a FriendReportItem on read and clears reportTarget when the sheet closes.
            .sheet(item: Binding(
                get: { reportTarget.map { FriendReportItem(target: $0) } },
                set: { if $0 == nil { reportTarget = nil } }
            )) { item in
                ReportSheet(target: item.target)
            }
            // Block confirmation. The Binding is built inline: presented when blockCandidate is set,
            // and dismissing clears it.
            .confirmationDialog(
                "Block this person?",
                isPresented: Binding(get: { blockCandidate != nil }, set: { if !$0 { blockCandidate = nil } }),
                titleVisibility: .visible
            ) {
                if let candidate = blockCandidate {
                    Button("Block \(candidate.name)", role: .destructive) { block(candidate.id, candidate.name) }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("They won't be able to see you on the map, and you won't see their Happs or photos. You can unblock them in Me > Privacy and Safety.")
            }
            // Remove confirmation. `presenting:` hands the pending friend to the button and message closures.
            .confirmationDialog(
                "Remove friend?",
                isPresented: removalIsPresented,
                titleVisibility: .visible,
                presenting: friendPendingRemoval
            ) { friend in
                Button("Remove \(friend.displayName)", role: .destructive) { remove(friend) }
                Button("Cancel", role: .cancel) { }
            } message: { _ in
                Text("You'll stop seeing each other's status and location. You can send a new request later.")
            }
            // Errors are published by FriendStore itself (errorMessage); the alert clears them through clearError().
            .alert("Database Error", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { friendStore.clearError() }
            } message: {
                Text(friendStore.errorMessage ?? "Please try again.")
            }
        }
    }
    
    /// The list body: Groups link, incoming requests (only when there are some) and the friends.
    private var friendsList: some View {
        List {
            Section {
                NavigationLink {
                    GroupsView()
                } label: {
                    groupsRow
                }
                .accessibilityHint("Opens your groups and invitations.")
            }
            
            if !friendStore.incomingRequests.isEmpty {
                Section("Requests") {
                    ForEach(friendStore.incomingRequests) { request in
                        requestRow(request)
                    }
                }
            }
            
            Section("Friends") {
                if friendStore.friends.isEmpty {
                    Text("No friends yet. Tap + to add some.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(friendStore.friends) { friend in
                        friendRow(friend)
                    }
                }
            }
        }
    }
    
    /// Groups navigation row showing the group count, or a red "N new" badge when invitations are waiting.
    private var groupsRow: some View {
        HStack {
            Label("Groups", systemImage: "person.3.fill")
            Spacer()
            if groupStore.invitations.isEmpty {
                Text("\(groupStore.groups.count)")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(groupStore.invitations.count) new")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.happsRedFill, in: Capsule())
            }
        }
        // Merge the row into one VoiceOver element and read a single sentence built by AccessibilityText.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AccessibilityText.groupsRow(
                groupCount: groupStore.groups.count,
                newInvitations: groupStore.invitations.count
            )
        )
    }
    
    /// One friend row. Visible friends show their status colour ring and symbol; hidden ones show "Hidden".
    /// Remove, Block and Report are offered as swipe, context menu and VoiceOver actions so none is touch only.
    private func friendRow(_ friend: UserProfile) -> some View {
        // Online on campus is decided by the store (visible, flagged on campus and a recent lastSeenAt).
        let onCampus = friendStore.isOnlineOnCampus(friend)
        // AnyLayout swaps HStack and VStack without rebuilding the children.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout())
        return layout {
            HStack {
                AvatarView(
                    symbol: friend.avatarSymbol, photo: friend.avatarPhoto,
                    size: 36,
                    ringColor: friend.isVisible ? friend.status.color : nil,
                    badgeSymbol: friend.isVisible ? friend.status.symbolName : nil
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.displayName)
                    if onCampus {
                        Label("On campus", systemImage: "location.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.happsGreenText)
                    }
                }
            }
            if !typeSize.isAccessibilitySize { Spacer() }
            statusLabel(for: friend)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AccessibilityText.friendRow(
                name: friend.displayName,
                status: friend.status.rawValue,
                isVisible: friend.isVisible,
                isOnCampus: onCampus
            )
        )
        .accessibilityAction(named: "Remove \(friend.displayName)") { friendPendingRemoval = friend }
        .accessibilityAction(named: "Block \(friend.displayName)") { blockCandidate = (friend.id, friend.displayName) }
        .accessibilityAction(named: "Report \(friend.displayName)") { report(friend) }
        // allowsFullSwipe false stops a long swipe from removing a friend by accident.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Remove", role: .destructive) { friendPendingRemoval = friend }
        }
        .contextMenu {
            Button("Report profile", systemImage: "flag") { report(friend) }
            Button("Block", systemImage: "hand.raised", role: .destructive) { blockCandidate = (friend.id, friend.displayName) }
        }
    }
    
    /// One incoming friend request, with accept and decline (ResponseRow) and a Block action.
    private func requestRow(_ request: FriendRequest) -> some View {
        ResponseRow(
            title: request.fromDisplayName,
            subtitle: nil,
            onAccept: { respond(request, accept: true) },
            onDecline: { respond(request, accept: false) }
        )
        .accessibilityAction(named: "Block \(request.fromDisplayName)") {
            blockCandidate = (request.fromUserID, request.fromDisplayName)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Block", role: .destructive) {
                blockCandidate = (request.fromUserID, request.fromDisplayName)
            }
        }
    }
    
    /// Bool binding for the removal dialog derived from the optional friendPendingRemoval.
    private var removalIsPresented: Binding<Bool> {
        Binding(get: { friendPendingRemoval != nil }, set: { if !$0 { friendPendingRemoval = nil } })
    }
    
    /// Bool binding for the error alert derived from FriendStore's errorMessage.
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { friendStore.errorMessage != nil }, set: { if !$0 { friendStore.clearError() } })
    }
    
    /// Right hand status text: "Hidden" when the friend turned visibility off, otherwise status name and symbol.
    @ViewBuilder
    private func statusLabel(for friend: UserProfile) -> some View {
        if friend.isVisible == false {
            Text("Hidden").font(.caption).foregroundStyle(.secondary)
        } else {
            Label(friend.status.rawValue, systemImage: friend.status.symbolName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    /// Accepts or declines a request. try? ignores errors here (assumed reason: FriendStore also publishes its own errorMessage, which the alert shows).
    private func respond(_ request: FriendRequest, accept: Bool) {
        Task {
            if accept { try? await friendStore.acceptRequest(request) }
            else { try? await friendStore.declineRequest(request) }
        }
    }
    
    /// Builds the ReportTarget for a friend's profile and so opens the report sheet.
    private func report(_ friend: UserProfile) {
        reportTarget = ReportTarget(
            kind: .profile, targetID: friend.id, happID: nil,
            offenderID: friend.id, offenderName: friend.displayName,
            summary: "Profile of \(friend.displayName)", hideID: nil
        )
    }
    
    /// Blocks a user through SafetyStore (which also removes the friendship) and announces it to VoiceOver.
    private func block(_ id: String, _ name: String) {
        guard let userID = authService.user?.uid else { return }
        Task {
            await safetyStore.block(userID: id, name: name, currentUserID: userID, friendStore: friendStore)
            AccessibilityNotification.Announcement("\(name) blocked.").post()
        }
    }
    
    /// Removes a friend after the user confirmed in the dialog.
    private func remove(_ friend: UserProfile) {
        guard let userID = authService.user?.uid else { return }
        Task { await friendStore.removeFriend(friend.id, currentUserID: userID) }
    }
}

/// Identifiable wrapper so a ReportTarget can drive .sheet(item:). The id combines kind and target id.
private struct FriendReportItem: Identifiable {
    let target: ReportTarget
    var id: String { target.kind.rawValue + target.targetID }
}

