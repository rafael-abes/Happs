//
//  AddFriendsView.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//
// CODE OVERVIEW
// Sheet for finding other users by name and sending them a friend request. It is presented
// from the friends list. The view only holds UI state (search text, results, which requests were
// sent); the actual Firestore queries and writes live in FriendStore, which it reads through
// @EnvironmentObject. AuthService supplies the signed in user's id and display name.
// Design: results are fetched on every keystroke through onChange, and a local Set of ids
// remembers which rows were already requested so the button can switch to a disabled "Sent" state.
import SwiftUI
import FirebaseAuth

/// Search sheet: type a name, get matching users, tap Request to send a friend request.
struct AddFriendsView: View {
    // Stores come from the environment (injected once at the app root) rather than being created here.
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var friendStore: FriendStore
    // Lets the sheet close itself without needing a binding from the parent.
    @Environment(\.dismiss) private var dismiss
    // Read so the row layout can switch to a vertical stack at accessibility text sizes.
    @Environment(\.dynamicTypeSize) private var typeSize
    
    // Text typed into the .searchable field.
    @State private var searchText = ""
    // Latest search results returned by FriendStore (UserSearchEntry is a lightweight search record).
    @State private var results: [UserSearchEntry] = []
    // Ids of users already requested in this session, so their buttons show "Sent" and are disabled.
    @State private var sentRequestIDs: Set<String> = []
    // Non nil means an error alert is showing (see errorIsPresented).
    @State private var errorMessage: String?
    
    var body: some View {
        // Own NavigationStack because this view is shown as a sheet, which has its own navigation context.
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
            // .searchable adds the system search bar; its text is bound to searchText.
            .searchable(text: $searchText, prompt: "Search")
            // Two parameter onChange (iOS 17+) gives old and new value; we only need the new one.
            .onChange(of: searchText) { _, newValue in search(for: newValue) }
            .navigationTitle("Add Friends")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityHint("Closes the search.")
                }
            }
            .alert("Couldn't Send Request", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }
    
    /// One result row: avatar, name and a Request button. @ViewBuilder lets the let constants and layout call sit before the returned view.
    @ViewBuilder
    private func searchRow(for entry: UserSearchEntry) -> some View {
        let isSent = sentRequestIDs.contains(entry.id)
        // AnyLayout lets us swap between HStack and VStack layouts for the same children, which keeps the
        // Button's identity and state (a plain if/else on the container would rebuild the subviews).
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
        layout {
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(entry.displayName)
            }
            if !typeSize.isAccessibilitySize { Spacer() }
            Button(isSent ? "Sent" : "Request") {
                sendRequest(to: entry)
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .disabled(isSent)
            .accessibilityLabel(isSent ? "Request sent to \(entry.displayName)" : "Send friend request to \(entry.displayName)")
            .accessibilityHint(isSent ? "" : "Sends a friend request.")
        }
    }
    
    /// Adapts the optional errorMessage into the Bool binding .alert needs; dismissing clears the message.
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    
    /// Runs a user search for the current text, excluding the signed in user so you cannot add yourself.
    /// FriendStore does a prefix match on a normalised searchKey field and also drops blocked users.
    /// Errors go to the alert. The Task bridges the synchronous onChange callback into async/await.
    private func search(for query: String) {
        // No signed in user means nothing sensible to search for.
        guard let userID = authService.user?.uid else { return }
        Task {
            do { results = try await friendStore.searchUsers(matching: query, excluding: userID) }
            catch { errorMessage = error.localizedDescription }
        }
    }
    
    /// Sends a friend request to the tapped user, then marks the row as sent and announces it to VoiceOver.
    private func sendRequest(to entry: UserSearchEntry) {
        // Display name is sent along so the recipient's notification can show who it is from without another lookup (assumed reason).
        guard let user = authService.user else { return }
        Task {
            do {
                try await friendStore.sendFriendRequest(from: user.uid, fromDisplayName: user.displayName ?? "Someone", to: entry.id)
                // Only record success after the await returns, so a failed request leaves the button usable.
                sentRequestIDs.insert(entry.id)
                AccessibilityNotification.Announcement("Request sent to \(entry.displayName).").post()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
