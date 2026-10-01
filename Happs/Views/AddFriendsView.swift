//
//  AddFriendsView.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//
import SwiftUI

struct AddFriendsView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var friendStore: FriendStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var results: [UserProfile] = []
    @State private var sentRequestIDs: Set<String> = []
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            List {
                Section("You May Know") {
                    if results.isEmpty {
                        Text(searchText.isEmpty ? "Search for friends by name." : "No matches.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(results) { profile in
                            HStack {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.title2).foregroundStyle(.secondary)
                                Text(profile.displayName)
                                Spacer()
                                Button(sentRequestIDs.contains(profile.id) ? "Sent" : "Request") {
                                    sendRequest(to: profile)
                                }
                                .buttonStyle(.bordered)
                                .disabled(sentRequestIDs.contains(profile.id))
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search")
            .onChange(of: searchText) { _, newValue in search(for: newValue) }
            .navigationTitle("Add Friends")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Couldn't Send Request", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }
    
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    
    private func search(for query: String) {
        guard let userID = authService.user?.uid else { return }
        Task {
            do { results = try await friendStore.searchUsers(matching: query, excluding: userID) }
            catch { errorMessage = error.localizedDescription }
        }
    }
    
    private func sendRequest(to profile: UserProfile) {
        guard let user = authService.user else { return }
        Task {
            do {
                try await friendStore.sendFriendRequest(from: user.uid, fromDisplayName: user.displayName ?? "Someone", to: profile.id)
                sentRequestIDs.insert(profile.id)
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
