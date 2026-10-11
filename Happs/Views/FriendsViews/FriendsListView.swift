//
//  FriendsListView.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//
import SwiftUI

struct FriendsListView: View {
    @EnvironmentObject private var friendStore: FriendStore
    @EnvironmentObject private var groupStore: GroupStore
    @State private var isPresentingAddFriends = false
    @State private var showsMap = false
    
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
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Friends", systemImage: "plus") { isPresentingAddFriends = true }
                }
            }
            .sheet(isPresented: $isPresentingAddFriends) { AddFriendsView() }
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
                    .background(.red, in: Capsule())
            }
        }
    }
    
    private func friendRow(_ friend: UserProfile) -> some View {
        HStack {
            AvatarView(symbol: friend.avatarSymbol, size: 36, ringColor: friend.isVisible ? friend.status.color : nil)
            Text(friend.displayName)
            Spacer()
            statusLabel(for: friend)
        }
    }
    
    @ViewBuilder
    private func requestRow(_ request: FriendRequest) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(request.fromDisplayName)
                Spacer()
                requestButtons(request)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(request.fromDisplayName)
                requestButtons(request)
            }
        }
    }
    
    private func requestButtons(_ request: FriendRequest) -> some View {
        HStack {
            Button("Accept") { respond(request, accept: true) }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            Button("Decline") { respond(request, accept: false) }
                .buttonStyle(.bordered)
        }
    }
    
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { friendStore.errorMessage != nil }, set: { if !$0 { friendStore.clearError() } })
    }
    
    @ViewBuilder
    private func statusLabel(for friend: UserProfile) -> some View {
        if friend.isVisible == false {
            Text("Hidden").font(.caption).foregroundStyle(.secondary)
        } else {
            Label(friend.status.rawValue, systemImage: "circle.fill")
                .font(.caption)
                .foregroundStyle(friend.status.color)
        }
    }
    
    private func respond(_ request: FriendRequest, accept: Bool) {
        Task {
            if accept { try? await friendStore.acceptRequest(request) }
            else { try? await friendStore.declineRequest(request) }
        }
    }
}
