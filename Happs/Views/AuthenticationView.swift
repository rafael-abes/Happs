//
//  AuthenticationView.swift
//  Happs
//
//  Created by Rafa Abes on 9/21/26.
//
// CODE OVERVIEW
// The logged out entry screen. A landing page offers "Log in" and "Sign Up"; each pushes a
// shared form (AuthFormView) onto a NavigationStack. The form also offers Google sign in.
// Role: pure View in the MVC split. It holds only form state (@State) and delegates all real
// work to AuthService, which it receives through @EnvironmentObject (injected once at the app
// root, so no view has to build its own auth object). Once AuthService publishes a signed in
// user, the app root swaps this screen out, so this file never navigates after success itself.
// Design: one form view serves both modes, switched by the AuthMode enum, to avoid duplicated UI.
import SwiftUI

/// The two destinations from the landing page. Raw values double as button and nav titles.
/// Hashable so it can be used as the value for NavigationLink(value:) and navigationDestination(for:).
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

/// Landing screen shown to signed out users. Owns the NavigationStack for the auth flow.
struct AuthenticationView: View {
    // @ScaledMetric makes the logo grow with Dynamic Type instead of staying a fixed 110 pt.
    @ScaledMetric(relativeTo: .largeTitle) private var logoSize: CGFloat = 110

    var body: some View {
        // Value based navigation: links push an AuthMode value and this destination builds the form.
        NavigationStack {
            landing
                .navigationDestination(for: AuthMode.self) { mode in
                    AuthFormView(mode: mode)
                }
        }
    }
    
    /// Title, tagline and the two pills. Wrapped in a ScrollView so it still fits at huge text sizes.
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
            // Cap the content width (readable on iPad) and then centre it with a second maxWidth: .infinity frame.
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        // Only bounce when the content is actually taller than the screen.
        .scrollBounceBehavior(.basedOnSize)
    }
    
    /// App icon shown above the greeting (named "placeholder" because it reuses the AppIcon asset).
    private var logoPlaceholder: some View {
        Image("AppIcon")
            .resizable()
            .scaledToFit()
            .frame(width: logoSize, height: logoSize)
            .accessibilityHidden(true)
    }
    
    /// Solid green capsule label used for the primary "Log in" action.
    private func filledPill(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 18)
            .background(Color.happsGreenFill, in: Capsule())
    }
    
    /// Outlined capsule label for the secondary "Sign Up" action. Same size as the filled one so they align.
    private func outlinedPill(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.medium))
            .foregroundStyle(Color.happsGreenText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 18)
            .overlay(Capsule().stroke(Color.happsGreenText, lineWidth: 3))
    }
}

/// The email/password form shared by log in and sign up. Private because only this file pushes it.
private struct AuthFormView: View {
    /// Decides which fields show and which AuthService call runs on submit.
    let mode: AuthMode
    
    // Shared auth model from the environment (an ObservableObject injected at the app root).
    @EnvironmentObject private var authService: AuthService
    // Local form state. @State is right here because nothing else needs these values.
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    /// True while a network request is in flight; disables the buttons to stop double submits.
    @State private var isWorking = false
    /// Non nil means "show the error alert". See errorIsPresented.
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
        // The alert is driven by a Binding<Bool> derived from errorMessage.
        .alert("Authentication Error", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }
    
    /// The text inputs. Display name is only needed when creating an account.
    private var fields: some View {
        VStack(spacing: 14) {
            if mode == .signUp {
                TextField("Display name", text: $displayName)
                    // textContentType lets iOS offer autofill suggestions for the field.
                    .textContentType(.name)
                    .accessibilityLabel("Display name")
            }
            TextField("Email address", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Email address")
            // .newPassword lets iOS offer a strong generated password on sign up; .password offers saved ones.
            SecureField("Password", text: $password)
                .textContentType(mode == .logIn ? .password : .newPassword)
                .accessibilityLabel("Password")
                .accessibilityHint(mode == .logIn ? "Enter your password." : "Choose a password for your new account.")
        }
        .textFieldStyle(.roundedBorder)
        .frame(minHeight: 44)
    }
    
    /// Main action button. Shows a spinner while working and is disabled to prevent repeat taps.
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
    
    /// "OR" separator between email sign in and Google sign in (purely visual, hidden from VoiceOver).
    private var orDivider: some View {
        HStack {
            VStack { Divider() }
            Text("OR").font(.caption).foregroundStyle(.secondary)
            VStack { Divider() }
        }
        .accessibilityHidden(true)
    }
    
    /// Starts the Google Sign-In flow, which presents a Google page and returns a credential to AuthService.
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
    
    /// Adapts the optional errorMessage into the Bool binding that .alert needs. Dismissing the
    /// alert sets the message back to nil, so the two stay in sync with no extra flag.
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    
    /// Runs sign in or account creation depending on mode. Errors become the alert text.
    // Task bridges from the synchronous button action into async/await.
    private func submit() {
        isWorking = true
        Task {
            // defer guarantees the spinner stops on success and on error, without repeating the line.
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
    
    /// Same pattern as submit(), but for the Google credential flow.
    private func signInWithGoogle() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do { try await authService.signInWithGoogle() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
