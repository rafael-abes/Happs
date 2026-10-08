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
    @Environment(\.dismiss) private var dismiss
    
    @State private var displayName = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Display Name") {
                    TextField("Name", text: $displayName).textContentType(.name)
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
            .onAppear { displayName = authService.user?.displayName ?? "" }
            .alert("Couldn't Save", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }
    
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    
    private func save() {
        let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { errorMessage = "Enter a name."; return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do { try await authService.updateDisplayName(cleaned); dismiss() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
