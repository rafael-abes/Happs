//
//  DeleteAccountView.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


import SwiftUI
import FirebaseAuth

struct DeleteAccountView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var recapStore: RecapStore
    @EnvironmentObject private var safetyStore: SafetyStore

    @State private var password = ""
    @State private var understands = false
    @State private var isWorking = false
    @State private var showConfirm = false
    @State private var errorMessage: String?

    private var canDelete: Bool {
        understands && !isWorking && (!authService.usesPassword || !password.isEmpty)
    }

    var body: some View {
        Form {
            Section("This will permanently delete") {
                ForEach([
                    "Your profile, name and photo",
                    "Photos you shared in Happ recaps",
                    "Happs and groups you created",
                    "Your friend connections and requests",
                    "Your notifications, blocked list and location"
                ], id: \.self) { Label($0, systemImage: "trash") }
            }

            Section {
                Text("Reports you made or that were made about you may be kept for safety records. Remaining backups are removed by our providers on their normal schedule.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Confirm it's you") {
                if authService.usesPassword {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .accessibilityLabel("Password")
                } else {
                    Text("You'll be asked to sign in with Google before deleting.")
                        .font(.callout)
                }
                Toggle("I understand this can't be undone", isOn: $understands)
            }

            Section {
                Button(role: .destructive) { showConfirm = true } label: {
                    HStack {
                        if isWorking { ProgressView() }
                        Text(isWorking ? "Deleting…" : "Delete My Account")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(!canDelete)
                .accessibilityHint("Permanently deletes your account and data.")
            }
        }
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete your account?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { delete() }
            Button("Keep My Account", role: .cancel) {}
        } message: {
            Text("Everything listed above will be removed for good.")
        }
        .alert("Couldn't Delete Account", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func delete() {
        guard let userID = authService.user?.uid else { return }
        isWorking = true
        AccessibilityNotification.Announcement("Deleting your account.").post()
        Task {
            defer { isWorking = false }
            do {
                if authService.usesPassword {
                    try await authService.reauthenticate(password: password)
                } else {
                    try await authService.reauthenticateWithGoogle()
                }
                let service = AccountDeletionService(recapStore: recapStore, safetyStore: safetyStore)
                let result = try await service.purge(
                    userID: userID,
                    friendIDs: profileStore.profile?.friendIDs ?? []
                )
                try await authService.deleteCurrentUser()
                #if DEBUG
                if !result.failedSteps.isEmpty { print("Deletion incomplete: \(result.failedSteps)") }
                #endif
            } catch {
                errorMessage = (error as? AppError)?.errorDescription
                    ?? "We couldn't finish deleting your account. Check your password and connection, then try again."
            }
        }
    }
}
