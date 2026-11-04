//
//  AuthService.swift
//  Happs
//
//  Created by Rafa Abes on 9/22/26.
//
//  CODE OVERVIEW
//  -------------
//  Wraps Firebase Authentication for the whole app: email/password sign-in and sign-up, Google
//  Sign-In, re-authentication, rename, sign-out and account deletion. It is an ObservableObject
//  created once in ContentView (@StateObject) and shared with @EnvironmentObject; views react to the
//  published `user` and `isCheckingAuthentication`. A Firebase auth state listener is the single
//  source of truth for "who is signed in", so every sign-in route (email, Google, restored session)
//  ends up in the same place. It also keeps the Firestore profile and search-index documents in step
//  with the Auth account. @MainActor because the published values drive the UI.
//
import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import UIKit
import Combine

/// Authentication and profile upkeep. Dependencies are injected with defaults (see init) so tests
/// could pass other instances.
@MainActor
final class AuthService: ObservableObject {
    /// Maximum characters allowed in a display name.
    private static let displayNameLimit = 60

    /// The signed-in Firebase user, or nil. private(set) so only this class changes it.
    @Published private(set) var user: FirebaseAuth.User?
    /// True until the first auth callback arrives, so the UI shows a loading state instead of
    /// flashing the sign-in screen for an already signed-in user.
    @Published private(set) var isCheckingAuthentication = true

    private let auth: Auth
    private let database: Firestore
    /// Handle kept for the auth state listener registered in init.
    private var authListener: AuthStateDidChangeListenerHandle?
    /// Set while createAccount runs so syncProfile does not race it and create the profile twice.
    private var isCreatingAccount = false

    /// Registers the auth state listener. Firebase calls it at once with the restored session (or nil)
    /// and again on every sign-in or sign-out.
    init(auth: Auth = .auth(), database: Firestore = .firestore()) {
        self.auth = auth
        self.database = database
        authListener = auth.addStateDidChangeListener { [weak self] _, user in
            // [weak self] avoids a retain cycle; the callback is not guaranteed to be on the main actor,
            // so hop onto it before touching published state.
            Task { @MainActor in
                guard let self else { return }
                self.user = user
                self.isCheckingAuthentication = false
                if let user {
                    await self.syncProfile(for: user)
                }
            }
        }
    }

    /// Signs in with email and password. Throws AppError.invalidForm for blank input, or a Firebase error.
    func signIn(email: String, password: String) async throws {
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedEmail.isEmpty, !password.isEmpty else {
            throw AppError.invalidForm("Enter both an email address and password.")
        }
        _ = try await auth.signIn(withEmail: cleanedEmail, password: password)
    }

    /// Creates the Auth account, sets its display name, then writes the Firestore profile and search entry.
    /// If either Firestore write fails the new account and profile are rolled back, so the user is not left
    /// with half an account. Validation (blank, length, ContentFilter, password length) happens before any network call.
    func createAccount(displayName: String, email: String, password: String) async throws {
        let cleanedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedName.isEmpty, !cleanedEmail.isEmpty else {
            throw AppError.invalidForm("Enter your name and email address.")
        }
        guard cleanedName.count <= Self.displayNameLimit else {
            throw AppError.invalidForm("Your name must be \(Self.displayNameLimit) characters or fewer.")
        }
        try ContentFilter.validate(cleanedName, field: "name")
        guard password.count >= 6 else {
            throw AppError.invalidForm("The password must contain at least six characters.")
        }

        // defer guarantees the flag is reset on every exit path, including thrown errors.
        isCreatingAccount = true
        defer { isCreatingAccount = false }

        let result = try await auth.createUser(withEmail: cleanedEmail, password: password)
        let request = result.user.createProfileChangeRequest()
        request.displayName = cleanedName
        try await request.commitChanges()

        let profile = UserProfile(id: result.user.uid, displayName: cleanedName, email: cleanedEmail)

        // try? on cleanup: we are already handling an error and just want best-effort rollback.
        do {
            try await database.collection("users").document(profile.id).setData(profile.creationData)
            try await writeSearchIndex(userID: profile.id, displayName: cleanedName)
        } catch {
            try? await database.collection("users").document(profile.id).delete()
            try? await result.user.delete()
            throw error
        }
    }

    /// Google Sign-In flow: Google SDK shows its sign-in sheet, returns an ID token, which is exchanged
    /// for a Firebase credential. Profile creation is left to syncProfile via the auth listener.
    func signInWithGoogle() async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AppError.invalidForm("Missing Google client ID. Check GoogleService-Info.plist.")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let presentingViewController = Self.topViewController() else {
            throw AppError.invalidForm("Unable to present Google Sign-In right now.")
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)

        guard let idToken = result.user.idToken?.tokenString else {
            throw AppError.invalidForm("Google Sign-In did not return the expected token.")
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        _ = try await auth.signIn(with: credential)
        // The profile is created or repaired by `syncProfile` from the auth listener.
    }

    /// Renames the user in three places that must agree: the Auth profile, the Firestore user document
    /// and the search index. Then reloads and republishes the user so the UI sees the new name.
    func updateDisplayName(_ name: String) async throws {
        try ContentFilter.validate(name, field: "name")
        guard let user = auth.currentUser else {
            throw AppError.invalidForm("You're not signed in.")
        }
        let request = user.createProfileChangeRequest()
        request.displayName = name
        try await request.commitChanges()
        try await database.collection("users").document(user.uid).updateData(["displayName": name])
        try await writeSearchIndex(userID: user.uid, displayName: name)
        try await user.reload()
        self.user = auth.currentUser
    }

    /// "password" for email accounts, "google.com" for Google sign-in.
    var providerIDs: [String] {
        auth.currentUser?.providerData.map(\.providerID) ?? []
    }

    /// True if the account has a password (so re-authentication should ask for it).
    var usesPassword: Bool { providerIDs.contains("password") }

    /// Re-confirms an email account's identity. Firebase requires a recent sign-in before sensitive
    /// actions such as deleting the account.
    func reauthenticate(password: String) async throws {
        guard let user = auth.currentUser, let email = user.email else {
            throw AppError.invalidForm("You're not signed in.")
        }
        guard !password.isEmpty else {
            throw AppError.invalidForm("Enter your password to confirm.")
        }
        try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: email, password: password))
    }

    /// Same as reauthenticate(password:) for Google accounts: runs the Google flow again and
    /// reauthenticates with the fresh credential.
    func reauthenticateWithGoogle() async throws {
        guard let user = auth.currentUser else {
            throw AppError.invalidForm("You're not signed in.")
        }
        guard let presenting = Self.topViewController() else {
            throw AppError.invalidForm("Unable to present Google Sign-In right now.")
        }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AppError.invalidForm("Google Sign-In did not return the expected token.")
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        try await user.reauthenticate(with: credential)
    }

    /// Deletes the Firebase Auth account. Callers purge Firestore data first (see the note at the top).
    func deleteCurrentUser() async throws {
        guard let user = auth.currentUser else {
            throw AppError.invalidForm("You're not signed in.")
        }
        try await user.delete()
    }

    /// Signs out; the auth listener then sets user to nil.
    func signOut() throws {
        try auth.signOut()
    }

    // MARK: - Profile upkeep

    /// Runs on every sign-in, for every provider. Creates a missing profile, fills in any
    /// missing fields without touching existing ones, and keeps the search entry current.
    private func syncProfile(for user: FirebaseAuth.User) async {
        guard !isCreatingAccount else { return }

        let reference = database.collection("users").document(user.uid)
        do {
            // One-off read (getDocument), not a listener: this is a check-then-repair step.
            let snapshot = try await reference.getDocument()
            let authName = Self.resolvedName(for: user)
            var profileName = authName

            if let data = snapshot.data() {
                profileName = (data["displayName"] as? String) ?? authName

                // Only add fields that are absent, so existing user data is never overwritten.
                var missing: [String: Any] = [:]
                if data["displayName"] == nil { missing["displayName"] = authName }
                if data["email"] == nil { missing["email"] = user.email ?? "" }
                if data["status"] == nil { missing["status"] = UserStatus.available.rawValue }
                if data["isVisible"] == nil { missing["isVisible"] = true }
                if data["friendIDs"] == nil { missing["friendIDs"] = [String]() }
                if !missing.isEmpty {
                    try await reference.updateData(missing)
                }
            } else {
                let profile = UserProfile(
                    id: user.uid,
                    displayName: authName,
                    email: user.email ?? "",
                    phoneNumber: user.phoneNumber
                )
                try await reference.setData(profile.creationData)
            }

            // Keep the search index in step; write only when the key or name differs to avoid needless writes.
            let indexReference = database.collection(UserSearchEntry.collectionName).document(user.uid)
            let index = try await indexReference.getDocument()
            let expectedKey = UserSearchEntry.searchKey(for: profileName)
            let storedKey = index.get("searchKey") as? String
            let storedName = index.get("displayName") as? String
            if storedKey != expectedKey || storedName != profileName {
                try await indexReference.setData(["displayName": profileName, "searchKey": expectedKey])
            }
        } catch {
            // Best effort: a failed sync should not block sign-in.
            #if DEBUG
            print("Profile sync failed: \(error)")
            #endif
        }
    }

    /// Writes the public search entry; searchKey is the normalised name used for matching.
    private func writeSearchIndex(userID: String, displayName: String) async throws {
        try await database.collection(UserSearchEntry.collectionName).document(userID).setData([
            "displayName": displayName,
            "searchKey": UserSearchEntry.searchKey(for: displayName)
        ])
    }

    /// Picks a display name: Auth display name, else the email prefix, else a fixed fallback.
    private static func resolvedName(for user: FirebaseAuth.User) -> String {
        if let name = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let prefix = user.email?.split(separator: "@").first, !prefix.isEmpty {
            return String(prefix)
        }
        return "New Happs User"
    }

    /// Finds the view controller Google Sign-In needs to present from. SwiftUI has no direct handle on
    /// one, so it is found through the key window's root view controller.
    private static func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first(where: \.isKeyWindow)?.rootViewController
    }
}
