//
//  AuthenticationView.swift
//  Happs
//
//  Created by Rafa Abes on 9/21/26.
//
import SwiftUI

private enum AuthMode: String, Hashable {
    case logIn = "Log in"
    case signUp = "Sign Up"

    /// What the landing pill says it opens, for VoiceOver.
    var hint: String {
        switch self {
        case .logIn: "Opens the log in form."
        case .signUp: "Opens the sign up form."
        }
    }
}

struct AuthenticationView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var logoSize: CGFloat = 110

    var body: some View {
        NavigationStack {
            landing
                .navigationDestination(for: AuthMode.self) { mode in
                    AuthFormView(mode: mode)
                }
        }
    }
    
    private var landing: some View {
        ScrollView {
            VStack(spacing: 0) {
                logoPlaceholder
                    .padding(.top, 40)
                Text("Hello")
                    .font(.largeTitle.bold())
                    .padding(.top, 24)
                    .accessibilityAddTraits(.isHeader)
                Text("Welcome to Happs")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(spacing: 16) {
                    NavigationLink(value: AuthMode.logIn) { filledPill("Log in") }
                        .accessibilityHint(AuthMode.logIn.hint)
                    NavigationLink(value: AuthMode.signUp) { outlinedPill("Sign Up") }
                        .accessibilityHint(AuthMode.signUp.hint)
                }
                .padding(.top, 40)
            }
            .padding(.horizontal, 36)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
    
    private var logoPlaceholder: some View {
        Image("AppIcon")
            .resizable()
            .scaledToFit()
            .frame(width: logoSize, height: logoSize)
            .accessibilityHidden(true)
    }
    
    private func filledPill(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 18)
            .background(Color.happsGreenFill, in: Capsule())
    }
    
    private func outlinedPill(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.medium))
            .foregroundStyle(Color.happsGreenText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 18)
            .overlay(Capsule().stroke(Color.happsGreenText, lineWidth: 3))
    }
}

private struct AuthFormView: View {
    let mode: AuthMode
    
    @EnvironmentObject private var authService: AuthService
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                fields
                submitButton
                orDivider
                googleButton
            }
            .padding(28)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(mode.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Authentication Error", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }
    
    private var fields: some View {
        VStack(spacing: 14) {
            if mode == .signUp {
                TextField("Display name", text: $displayName)
                    .textContentType(.name)
                    .accessibilityLabel("Display name")
            }
            TextField("Email address", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Email address")
            SecureField("Password", text: $password)
                .textContentType(mode == .logIn ? .password : .newPassword)
                .accessibilityLabel("Password")
                .accessibilityHint(mode == .logIn ? "Enter your password." : "Choose a password for your new account.")
        }
        .textFieldStyle(.roundedBorder)
        .frame(minHeight: 44)
    }
    
    private var submitButton: some View {
        Button(action: submit) {
            HStack {
                if isWorking { ProgressView().tint(.white) }
                Text(mode.rawValue).frame(maxWidth: .infinity)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .background(Color.happsGreenFill, in: Capsule())
        }
        .disabled(isWorking)
        .accessibilityLabel(mode.rawValue)
        .accessibilityValue(isWorking ? "Working" : "")
        .accessibilityHint(mode == .logIn ? "Logs in with your email and password." : "Creates your account.")
    }
    
    private var orDivider: some View {
        HStack {
            VStack { Divider() }
            Text("OR").font(.caption).foregroundStyle(.secondary)
            VStack { Divider() }
        }
        .accessibilityHidden(true)
    }
    
    private var googleButton: some View {
        Button(action: signInWithGoogle) {
            Label("Continue with Google", systemImage: "g.circle.fill")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isWorking)
        .accessibilityHint("Opens a Google page to sign in.")
    }
    
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    
    private func submit() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                switch mode {
                case .logIn:
                    try await authService.signIn(email: email, password: password)
                case .signUp:
                    try await authService.createAccount(displayName: displayName, email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func signInWithGoogle() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do { try await authService.signInWithGoogle() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
