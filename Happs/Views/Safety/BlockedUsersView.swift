//
//  BlockedUsersView.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


import SwiftUI
import FirebaseAuth

struct BlockedUsersView: View {
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

    private func unblock(_ person: BlockedUser) {
        guard let userID = authService.user?.uid else { return }
        Task {
            await safetyStore.unblock(userID: person.id, currentUserID: userID)
            AccessibilityNotification.Announcement("\(person.name) unblocked.").post()
        }
    }
}
