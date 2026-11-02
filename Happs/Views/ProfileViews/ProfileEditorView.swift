//
//  ProfileEditorView.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//

import SwiftUI
import FirebaseAuth
import PhotosUI

struct ProfileEditorView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 56
    
    @State private var displayName = ""
    @State private var selectedSymbol = AvatarSymbols.fallback
    @State private var isSaving = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var newPhoto: Data?          // processed JPEG waiting to be saved
    @State private var removePhoto = false
    @State private var errorMessage: String?
    
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: avatarSize + 8), spacing: 12)]
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Display Name") {
                    TextField("Name", text: $displayName)
                        .textContentType(.name)
                        .accessibilityLabel("Display name")
                }
                
                Section("Profile Photo") {
                    HStack(spacing: 16) {
                        AvatarView(symbol: selectedSymbol, photo: currentPhoto, size: avatarSize * 1.4)
                        VStack(alignment: .leading, spacing: 8) {
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                Label("Choose a photo", systemImage: "photo")
                                    .frame(minHeight: 44, alignment: .leading)
                            }
                            .accessibilityHint("Opens your photos. Only the photo you pick is shared with Happs.")
                            if currentPhoto != nil {
                                Button(role: .destructive) {
                                    newPhoto = nil
                                    removePhoto = true
                                    pickerItem = nil
                                } label: {
                                    Label("Use a symbol instead", systemImage: "trash")
                                        .frame(minHeight: 44, alignment: .leading)
                                }
                                .accessibilityHint("Removes your photo and shows the symbol you pick below.")
                            }
                        }
                    }
                    .onChange(of: pickerItem) { _, item in loadPhoto(item) }
                }
                
                Section("Or pick a symbol") {
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityHint("Closes without saving.")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving)
                        .accessibilityValue(isSaving ? "Saving" : "")
                        .accessibilityHint("Saves your name and picture.")
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
    
    /// The photo that would show right now: a new pick, otherwise the saved one unless removed.
    private var currentPhoto: Data? {
        if let newPhoto { return newPhoto }
        return removePhoto ? nil : profileStore.profile?.avatarPhoto
    }
    
    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let processed = await Task.detached(priority: .userInitiated, operation: {
                      AvatarPhotoProcessor.process(data)
                  }).value else {
                errorMessage = "That photo couldn't be used. Try a different one."
                return
            }
            newPhoto = processed
            removePhoto = false
            AccessibilityNotification.Announcement("Photo chosen. Tap Save to keep it.").post()
        }
    }
    
    private func avatarButton(_ symbol: String) -> some View {
        let isSelected = selectedSymbol == symbol && currentPhoto == nil
        return Button {
            selectedSymbol = symbol
            newPhoto = nil
            removePhoto = true
        } label: {
            AvatarView(symbol: symbol, size: avatarSize, ringColor: isSelected && currentPhoto == nil ? Color.primary : nil)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AvatarSymbols.name(for: symbol))
        .accessibilityHint("Double tap to use this picture.")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
                if let newPhoto {
                    try await profileStore.setAvatarPhoto(newPhoto, for: userID)
                } else if removePhoto, profileStore.profile?.avatarPhoto != nil {
                    try await profileStore.removeAvatarPhoto(for: userID)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
