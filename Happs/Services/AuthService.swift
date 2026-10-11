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
    
    init(auth: Auth = .auth(), database: Firestore = .firestore()) {
        self.auth = auth
        self.database = database
        authListener = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.isCheckingAuthentication = false
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
        guard password.count >= 6 else {
            throw AppError.invalidForm("The password must contain at least six characters.")
        }
        
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
        let authResult = try await auth.signIn(with: credential)
        try await ensureProfileExists(for: authResult.user, fallbackDisplayName: result.user.profile?.name ?? "")
    }
    
    func updateDisplayName(_ name: String) async throws {
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
    
    func signOut() throws {
        try auth.signOut()
    }
    
    private static func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first(where: \.isKeyWindow)?.rootViewController
    }
    
    private func ensureProfileExists(for user: FirebaseAuth.User, fallbackDisplayName: String) async throws {
        let reference = database.collection("users").document(user.uid)
        let snapshot = try await reference.getDocument()
        guard snapshot.exists == false else { return }
        
        let cleanedName = fallbackDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = UserProfile(
            id: user.uid,
            displayName: cleanedName.isEmpty ? "New Happs User" : cleanedName,
            email: user.email ?? "",
            phoneNumber: user.phoneNumber
        )
        try await reference.setData(profile.creationData)
        try await writeSearchIndex(userID: user.uid, displayName: profile.displayName)
    }
    
    private func writeSearchIndex(userID: String, displayName: String) async throws {
        try await database.collection(UserSearchEntry.collectionName).document(userID).setData([
            "displayName": displayName
        ])
    }
}
