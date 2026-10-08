//
//  AddFriendsView.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//
import SwiftUI
import FirebaseAuth

struct AddFriendsView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var friendStore: FriendStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var results: [UserSearchEntry] = []
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
                        ForEach(results) { entry in
                            searchRow(for: entry)
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
    
    @ViewBuilder
    private func searchRow(for entry: UserSearchEntry) -> some View {
        let isSent = sentRequestIDs.contains(entry.id)
        HStack {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2).foregroundStyle(.secondary)
            Text(entry.displayName)
            Spacer()
            Button(isSent ? "Sent" : "Request") {
                sendRequest(to: entry)
            }
            .buttonStyle(.bordered)
            .disabled(isSent)
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
    
    private func sendRequest(to entry: UserSearchEntry) {
        guard let user = authService.user else { return }
        Task {
            do {
                try await friendStore.sendFriendRequest(from: user.uid, fromDisplayName: user.displayName ?? "Someone", to: entry.id)
                sentRequestIDs.insert(entry.id)
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
