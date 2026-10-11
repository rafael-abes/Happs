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
}

struct AuthenticationView: View {
    var body: some View {
        NavigationStack {
            landing
                .navigationDestination(for: AuthMode.self) { mode in
                    AuthFormView(mode: mode)
                }
        }
    }
    
    private var landing: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            logoPlaceholder
            Text("Hello")
                .font(.system(size: 44, weight: .bold))
                .padding(.top, 24)
            Text("Welcome to Happs")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 16) {
                NavigationLink(value: AuthMode.logIn) { filledPill("Log in") }
                NavigationLink(value: AuthMode.signUp) { outlinedPill("Sign Up") }
            }
            .padding(.top, 40)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }
    
    private var logoPlaceholder: some View {
        Image(systemName: "figure.socialdance")
            .font(.system(size: 64))
            .foregroundStyle(Color.happsGreen)
            .frame(width: 110, height: 110)
            .background(Color.happsGreen.opacity(0.15), in: Circle())
    }
    
    private func filledPill(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.happsGreen, in: Capsule())
    }
    
    private func outlinedPill(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.medium))
            .foregroundStyle(Color.happsGreen)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .overlay(Capsule().stroke(Color.happsGreen, lineWidth: 3))
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
            }
            TextField("Email address", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(mode == .logIn ? .password : .newPassword)
        }
        .textFieldStyle(.roundedBorder)
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
            .background(Color.happsGreen, in: Capsule())
        }
        .disabled(isWorking)
    }
    
    private var orDivider: some View {
        HStack {
            VStack { Divider() }
            Text("OR").font(.caption).foregroundStyle(.secondary)
            VStack { Divider() }
        }
    }
    
    private var googleButton: some View {
        Button(action: signInWithGoogle) {
            Label("Continue with Google", systemImage: "g.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isWorking)
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
