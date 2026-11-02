//
//  AuthService.swift
//  Happs
//
//  Created by Rafa Abes on 9/22/26.
//
import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import UIKit
import Combine

@MainActor
final class AuthService: ObservableObject {
    private static let displayNameLimit = 60

    @Published private(set) var user: FirebaseAuth.User?
    @Published private(set) var isCheckingAuthentication = true

    private let auth: Auth
    private let database: Firestore
    private var authListener: AuthStateDidChangeListenerHandle?
    private var isCreatingAccount = false

    init(auth: Auth = .auth(), database: Firestore = .firestore()) {
        self.auth = auth
        self.database = database
        authListener = auth.addStateDidChangeListener { [weak self] _, user in
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

    func signIn(email: String, password: String) async throws {
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedEmail.isEmpty, !password.isEmpty else {
            throw AppError.invalidForm("Enter both an email address and password.")
        }
        _ = try await auth.signIn(withEmail: cleanedEmail, password: password)
    }

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

        isCreatingAccount = true
        defer { isCreatingAccount = false }

        let result = try await auth.createUser(withEmail: cleanedEmail, password: password)
        let request = result.user.createProfileChangeRequest()
        request.displayName = cleanedName
        try await request.commitChanges()

        let profile = UserProfile(id: result.user.uid, displayName: cleanedName, email: cleanedEmail)

        do {
            try await database.collection("users").document(profile.id).setData(profile.creationData)
            try await writeSearchIndex(userID: profile.id, displayName: cleanedName)
        } catch {
            try? await database.collection("users").document(profile.id).delete()
            try? await result.user.delete()
            throw error
        }
    }

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

    var usesPassword: Bool { providerIDs.contains("password") }

    func reauthenticate(password: String) async throws {
        guard let user = auth.currentUser, let email = user.email else {
            throw AppError.invalidForm("You're not signed in.")
        }
        guard !password.isEmpty else {
            throw AppError.invalidForm("Enter your password to confirm.")
        }
        try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: email, password: password))
    }

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

    func deleteCurrentUser() async throws {
        guard let user = auth.currentUser else {
            throw AppError.invalidForm("You're not signed in.")
        }
        try await user.delete()
    }

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
            let snapshot = try await reference.getDocument()
            let authName = Self.resolvedName(for: user)
            var profileName = authName

            if let data = snapshot.data() {
                profileName = (data["displayName"] as? String) ?? authName

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

            let indexReference = database.collection(UserSearchEntry.collectionName).document(user.uid)
            let index = try await indexReference.getDocument()
            let expectedKey = UserSearchEntry.searchKey(for: profileName)
            let storedKey = index.get("searchKey") as? String
            let storedName = index.get("displayName") as? String
            if storedKey != expectedKey || storedName != profileName {
                try await indexReference.setData(["displayName": profileName, "searchKey": expectedKey])
            }
        } catch {
            #if DEBUG
            print("Profile sync failed: \(error)")
            #endif
        }
    }

    private func writeSearchIndex(userID: String, displayName: String) async throws {
        try await database.collection(UserSearchEntry.collectionName).document(userID).setData([
            "displayName": displayName,
            "searchKey": UserSearchEntry.searchKey(for: displayName)
        ])
    }

    private static func resolvedName(for user: FirebaseAuth.User) -> String {
        if let name = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let prefix = user.email?.split(separator: "@").first, !prefix.isEmpty {
            return String(prefix)
        }
        return "New Happs User"
    }

    private static func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first(where: \.isKeyWindow)?.rootViewController
    }
}
