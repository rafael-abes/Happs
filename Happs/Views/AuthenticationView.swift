//
//  AuthenticationView.swift
//  Happs
//
//  Created by Rafa Abes on 9/21/26.
//
import SwiftUI

struct AuthenticationView: View {
    private enum Method: String, CaseIterable, Identifiable {
        case email = "Email"
        case phone = "Phone"
        var id: String { rawValue }
    }
    
    private enum EmailMode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case createAccount = "Sign Up"
        var id: String { rawValue }
    }
    
    private enum PhoneStep {
        case enterNumber
        case enterCode(verificationID: String)
    }
    
    @EnvironmentObject private var authService: AuthService
    @State private var method = Method.email
    
    // Email state
    @State private var emailMode = EmailMode.signIn
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    
    // Phone state
    @State private var phoneStep = PhoneStep.enterNumber
    @State private var phoneDisplayName = ""
    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    
    @State private var isWorking = false
    @State private var errorMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                
                Picker("Method", selection: $method) {
                    ForEach(Method.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                
                switch method {
                case .email: emailForm
                case .phone: phoneForm
                }
                
                dividerWithLabel("OR")
                
                googleButton
            }
            .padding(28)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .alert("Authentication Error", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
        .onChange(of: method) { _, _ in errorMessage = nil }
    }
    
    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "figure.socialdance")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
            Text("Hello")
                .font(.largeTitle.bold())
            Text("Welcome to Happs")
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Email
    
    private var emailForm: some View {
        VStack(spacing: 14) {
            Picker("Email mode", selection: $emailMode) {
                ForEach(EmailMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            
            if emailMode == .createAccount {
                TextField("Display name", text: $displayName)
                    .textContentType(.name)
            }
            
            TextField("Email address", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            SecureField("Password", text: $password)
                .textContentType(emailMode == .signIn ? .password : .newPassword)
            
            primaryButton(title: emailMode == .signIn ? "Log In" : "Sign Up", action: submitEmail)
        }
        .textFieldStyle(.roundedBorder)
    }
    
    private func submitEmail() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                if emailMode == .signIn {
                    try await authService.signIn(email: email, password: password)
                } else {
                    try await authService.createAccount(displayName: displayName, email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Phone
    
    @ViewBuilder
    private var phoneForm: some View {
        switch phoneStep {
        case .enterNumber:
            VStack(spacing: 14) {
                TextField("Display name (if new)", text: $phoneDisplayName)
                    .textContentType(.name)
                TextField("Phone number, e.g. +61412345678", text: $phoneNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                primaryButton(title: "Send Code", action: sendCode)
            }
            .textFieldStyle(.roundedBorder)
            
        case .enterCode:
            VStack(spacing: 14) {
                Text("Enter the code sent to \(phoneNumber)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("6-digit code", text: $verificationCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                primaryButton(title: "Verify", action: verifyCode)
                Button("Use a different number") {
                    phoneStep = .enterNumber
                    verificationCode = ""
                }
                .font(.footnote)
            }
        }
    }
    
    private func sendCode() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let verificationID = try await authService.startPhoneVerification(phoneNumber: phoneNumber)
                phoneStep = .enterCode(verificationID: verificationID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func verifyCode() {
        guard case let .enterCode(verificationID) = phoneStep else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await authService.signIn(
                    verificationID: verificationID,
                    code: verificationCode,
                    displayName: phoneDisplayName
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Google
    
    private var googleButton: some View {
        Button(action: signInWithGoogle) {
            HStack {
                if isWorking { ProgressView() }
                Image(systemName: "g.circle.fill")
                Text("Continue with Google").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isWorking)
    }
    
    private func signInWithGoogle() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await authService.signInWithGoogle()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Shared
    
    private func primaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if isWorking { ProgressView().tint(.white) }
                Text(title).frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.large)
        .disabled(isWorking)
    }
    
    private func dividerWithLabel(_ label: String) -> some View {
        HStack {
            VStack { Divider() }
            Text(label).font(.caption).foregroundStyle(.secondary)
            VStack { Divider() }
        }
    }
    
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
