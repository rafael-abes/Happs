//
//  ProfileEditorView.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//

import SwiftUI
import FirebaseAuth

struct ProfileEditorView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var displayName = ""
    @State private var selectedSymbol = AvatarSymbols.fallback
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 12)]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Display Name") {
                    TextField("Name", text: $displayName).textContentType(.name)
                }
                
                Section("Profile Picture") {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(AvatarSymbols.all, id: \.self) { symbol in
                            avatarButton(symbol)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("My Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(isSaving)
                }
            }
            .onAppear {
                displayName = authService.user?.displayName ?? ""
                selectedSymbol = profileStore.profile?.avatarSymbol ?? AvatarSymbols.fallback
            }
            .alert("Couldn't Save", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }
    
    private func avatarButton(_ symbol: String) -> some View {
        let isSelected = selectedSymbol == symbol
        return Button { selectedSymbol = symbol } label: {
            AvatarView(symbol: symbol, size: 56, ringColor: isSelected ? Color.primary : nil)
        }
        .buttonStyle(.plain)
    }
    
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    
    private func save() {
        let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { errorMessage = "Enter a name."; return }
        guard let userID = authService.user?.uid else { return }
        
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                if cleaned != authService.user?.displayName {
                    try await authService.updateDisplayName(cleaned)
                }
                try await profileStore.updateAvatar(selectedSymbol, for: userID)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
