//
//  BlockedUsersView.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


// CODE OVERVIEW
// Settings sub-screen that lists blocked people and lets the user unblock them. It is a thin view:
// the list comes from SafetyStore (@EnvironmentObject, observed so the list updates when it
// changes) and unblocking is delegated to SafetyStore.unblock. AuthService supplies the current
// user id. A spoken announcement confirms the action because the row disappears afterwards.
//
import SwiftUI

/// The Blocked People screen (a List with an empty state).
struct BlockedUsersView: View {
        // Both stores are injected from higher in the view tree.
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var safetyStore: SafetyStore

    var body: some View {
        List {
            if safetyStore.blocked.isEmpty {
                ContentUnavailableView(
                    "No blocked people",
                    systemImage: "hand.raised",
                    description: Text("People you block can't send you requests or invitations, and you won't see their Happs or photos.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(safetyStore.blocked) { person in
                    HStack {
                        Text(person.name)
                        Spacer()
                        Button("Unblock") { unblock(person) }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                            .accessibilityLabel("Unblock \(person.name)")
                    }
                }
            }
        }
        .navigationTitle("Blocked People")
        .navigationBarTitleDisplayMode(.inline)
    }

        /// Unblocks one person. Does nothing if nobody is signed in. The store call is async, so it runs
        /// in a Task, and a VoiceOver announcement is posted when it finishes.
    private func unblock(_ person: BlockedUser) {
        guard let userID = authService.user?.uid else { return }
        Task {
            await safetyStore.unblock(userID: person.id, currentUserID: userID)
            AccessibilityNotification.Announcement("\(person.name) unblocked.").post()
        }
    }
}

