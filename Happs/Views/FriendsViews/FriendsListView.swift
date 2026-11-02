//
//  FriendsListView.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//
import SwiftUI
import FirebaseAuth

struct FriendsListView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var groupStore: GroupStore
    @Environment(\.dynamicTypeSize) private var typeSize
    
    @State private var isPresentingAddFriends = false
    @State private var showsMap = false
    @State private var friendPendingRemoval: UserProfile?
    
    var body: some View {
        NavigationStack {
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
            .sheet(isPresented: $isPresentingAddFriends) { AddFriendsView() }
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
            .alert("Database Error", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { friendStore.clearError() }
            } message: {
                Text(friendStore.errorMessage ?? "Please try again.")
            }
        }
    }
    
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AccessibilityText.groupsRow(
                groupCount: groupStore.groups.count,
                newInvitations: groupStore.invitations.count
            )
        )
    }
    
    private func friendRow(_ friend: UserProfile) -> some View {
        let onCampus = friendStore.isOnlineOnCampus(friend)
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout())
        return layout {
            HStack {
                AvatarView(
                    symbol: friend.avatarSymbol,
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Remove", role: .destructive) { friendPendingRemoval = friend }
        }
    }
    
    private func requestRow(_ request: FriendRequest) -> some View {
        ResponseRow(
            title: request.fromDisplayName,
            subtitle: nil,
            onAccept: { respond(request, accept: true) },
            onDecline: { respond(request, accept: false) }
        )
    }
    
    private var removalIsPresented: Binding<Bool> {
        Binding(get: { friendPendingRemoval != nil }, set: { if !$0 { friendPendingRemoval = nil } })
    }
    
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { friendStore.errorMessage != nil }, set: { if !$0 { friendStore.clearError() } })
    }
    
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
    
    private func respond(_ request: FriendRequest, accept: Bool) {
        Task {
            if accept { try? await friendStore.acceptRequest(request) }
            else { try? await friendStore.declineRequest(request) }
        }
    }
    
    private func remove(_ friend: UserProfile) {
        guard let userID = authService.user?.uid else { return }
        Task { await friendStore.removeFriend(friend.id, currentUserID: userID) }
    }
}

