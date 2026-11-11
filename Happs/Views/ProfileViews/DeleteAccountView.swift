//
//  DeleteAccountView.swift
//  Happs
//
//  Created by Rafa Abes on 11/2/26.
//


// CODE OVERVIEW
// The in-app account deletion screen, reached from PrivacySafetyView. The view only gathers
// confirmation and credentials and shows progress or errors; the real work is delegated: AuthService
// re-authenticates and deletes the Auth user, and AccountDeletionService (built here from the
// recap and safety stores) removes the user's Firestore and storage data first. Order matters: data
// is purged BEFORE the Auth account is deleted, because once the Auth user is gone the app can no
// longer prove who it is to the security rules. The stores come in through @EnvironmentObject so
// this screen shares the same instances as the rest of the app.
//
import SwiftUI
import FirebaseAuth

/// Form that walks the user through confirming and then deleting their account.
struct DeleteAccountView: View {
    // Shared app-wide objects injected higher up the view tree (not created here, so no @StateObject).
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var recapStore: RecapStore
    @EnvironmentObject private var safetyStore: SafetyStore

    // Local UI state. Only this view cares about these values, so @State rather than a store.
    @State private var password = ""
    @State private var understands = false
    /// True while re-auth and deletion run; disables the button and shows a spinner.
    @State private var isWorking = false
    @State private var showConfirm = false
    /// Non-nil means the error alert is showing (see the Binding built in body).
    @State private var errorMessage: String?

    /// The delete button is enabled only when the user ticked the switch, nothing is already running,
    /// and, for email/password accounts, a password was typed (Google accounts re-auth via a popup).
    private var canDelete: Bool {
        understands && !isWorking && (!authService.usesPassword || !password.isEmpty)
    }

    // A Form gives the standard grouped settings look and Dynamic Type behaviour.
    var body: some View {
        Form {
            Section("This will permanently delete") {
                // Static strings, so id: \.self is enough as the identity.
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
                // The button does not delete directly; it only opens the confirmation dialog below.
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
        // Second, system-styled confirmation. Only this dialog's destructive button calls delete().
        .confirmationDialog("Delete your account?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { delete() }
            Button("Keep My Account", role: .cancel) {}
        } message: {
            Text("Everything listed above will be removed for good.")
        }
        // Alert driven by errorMessage: a hand-made Binding that is true while a message exists and
        // clears the message when the alert is dismissed.
        .alert("Couldn't Delete Account", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    /// Runs the full deletion sequence: re-authenticate, purge data, delete the Auth user.
    /// Any thrown error aborts the sequence and is shown to the user instead of a false success.
    private func delete() {
        // Capture the uid up front; it is needed after the data purge, and the Auth user disappears at the end.
        guard let userID = authService.user?.uid else { return }
        isWorking = true
        // Tell VoiceOver users the long operation started, since the spinner is visual only.
        AccessibilityNotification.Announcement("Deleting your account.").post()
        // Task bridges this synchronous button action into async/await. The view is main-actor isolated, so state changes below run on the main actor.
        Task {
            // defer resets the busy flag on every exit path (success, throw or early return).
            defer { isWorking = false }
            do {
                if authService.usesPassword {
                    // Firebase refuses sensitive operations like deleting a user unless the sign-in is recent.
                    try await authService.reauthenticate(password: password)
                } else {
                    try await authService.reauthenticateWithGoogle()
                }
                // The service is created on demand with the stores it needs; it is not held as long-lived state.
                let service = AccountDeletionService(recapStore: recapStore, safetyStore: safetyStore)
                let result = try await service.purge(
                    userID: userID,
                    friendIDs: profileStore.profile?.friendIDs ?? []
                )
                // Last step: removing the Auth account makes the auth listener switch the app to sign-in.
                try await authService.deleteCurrentUser()
                // Debug builds only: log which purge steps failed (the purge reports partial failures instead of throwing).
                #if DEBUG
                if !result.failedSteps.isEmpty { print("Deletion incomplete: \(result.failedSteps)") }
                #endif
            } catch {
                // Prefer the app's own friendly message when the error is an AppError, otherwise a generic one.
                errorMessage = (error as? AppError)?.errorDescription
                    ?? "We couldn't finish deleting your account. Check your password and connection, then try again."
            }
        }
    }
}
