//
//  ProfileView.swift
//  Happs
//
//  Created by Rafa Abes on 10/1/26.
//
import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @EnvironmentObject private var authService: AuthService
    @AppStorage("prefersDarkMode") private var prefersDarkMode = false
    @State private var isInvisibleMode = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    invisibleModeCard
                    appearanceCard
                    
                    VStack(spacing: 10) {
                        MenuRow(systemImage: "house.fill", title: "My Profile")
                        MenuRow(systemImage: "bell.fill", title: "Notifications")
                        MenuRow(systemImage: "calendar", title: "Schedule")
                        MenuRow(systemImage: "square.and.pencil", title: "Preferences")
                        MenuRow(systemImage: "line.3.horizontal", title: "Settings")
                    }
                    
                    Button(role: .destructive, action: signOut) {
                        Text("Sign Out").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding(.top, 10)
                }
                .padding(20)
            }
            .navigationTitle("Me")
            .alert("Sign Out Failed", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }
    
    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
            
            Text(authService.user?.displayName ?? "Happs User")
                .font(.title2.bold())
            
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("Busy")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if let email = authService.user?.email, !email.isEmpty {
                Text(email)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            } else if let phone = authService.user?.phoneNumber {
                Text(phone)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    private var invisibleModeCard: some View {
        HStack {
            Toggle("", isOn: $isInvisibleMode)
                .labelsHidden()
            Text("Invisible Mode")
            Spacer()
            Button {
                // Status picker — not built yet.
            } label: {
                HStack(spacing: 4) {
                    Text("Change Status")
                    Image(systemName: "chevron.down")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
    
    private var appearanceCard: some View {
        HStack(spacing: 14) {
            Image(systemName: prefersDarkMode ? "moon.fill" : "sun.max.fill")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 28, height: 28)
                .background(.quaternary, in: Circle())
            Text("Dark Mode")
            Spacer()
            Toggle("", isOn: $prefersDarkMode)
                .labelsHidden()
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
    
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    
    private func signOut() {
        do {
            try authService.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
