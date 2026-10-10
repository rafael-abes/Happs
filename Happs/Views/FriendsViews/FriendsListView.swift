//
//  FriendsListView.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//
import SwiftUI

struct FriendsListView: View {
    @EnvironmentObject private var friendStore: FriendStore
    @State private var isPresentingAddFriends = false
    @State private var isPresentingGroups = false
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Groups", systemImage: "person.3") { isPresentingGroups = true }
                    Button("Add Friends", systemImage: "plus") { isPresentingAddFriends = true }
                }
            }
            .sheet(isPresented: $isPresentingAddFriends) { AddFriendsView() }
            .sheet(isPresented: $isPresentingGroups) { GroupsView() }
            .alert("Database Error", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { friendStore.clearError() }
            } message: {
                Text(friendStore.errorMessage ?? "Please try again.")
            }
        }
    }
    
    private var friendsList: some View {
        List {
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
    
    private func friendRow(_ friend: UserProfile) -> some View {
        HStack {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
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
