//
//  HappEditorView.swift
//  Happs
//
//  Created by Rafa Abes on 9/21/26.
//

import SwiftUI

struct HappEditorView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var happStore: HappStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var details = ""
    @State private var location = ""
    @State private var category = HappCategory.happs
    @State private var startTime = Date()
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    var body: some View {
        Form {
            Section("Happ Title") {
                TextField("What's happening?", text: $title)
            }
            
            Section("Location") {
                TextField("Add location", text: $location)
            }
            
            Section("When") {
                DatePicker("Time", selection: $startTime)
            }
            
            Section("Category") {
                Picker("Category", selection: $category) {
                    ForEach(HappCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Section("Details") {
                TextField("Add notes or anything else", text: $details, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("New Happ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add Happ") { createHapp() }.disabled(isCreating)
            }
        }
        .interactiveDismissDisabled(isCreating)
        .alert("Cannot Create Happ", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }
    
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    
    private func createHapp() {
        guard let user = authService.user else {
            errorMessage = "Sign in again before saving."
            return
        }
        
        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                try await happStore.createHapp(
                    title: title,
                    details: details,
                    location: location,
                    category: category,
                    startTime: startTime,
                    creatorID: user.uid,
                    creatorName: user.displayName ?? user.email ?? "Someone"
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
