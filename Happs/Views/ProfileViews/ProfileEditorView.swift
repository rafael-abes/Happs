//
//  ProfileEditorView.swift
//  Happs
//
//  Created by Rafa Abes on 10/2/26.
//

// CODE OVERVIEW
// The "My Profile" editor, presented as a sheet from ProfileView. The user edits their display name
// and picks either a built-in SF Symbol avatar or a custom photo (PhotosPicker). The view keeps all
// edits in local @State and writes nothing until Save, so Cancel discards cleanly. On Save it
// updates the name through AuthService (Firebase Auth) and the avatar through ProfileStore
// (Firestore). Photo picking is split from saving: the picked image is shrunk on a background task
// by AvatarPhotoProcessor so the main thread stays responsive and the stored photo stays small.
//
import SwiftUI
import FirebaseAuth
import PhotosUI

/// Sheet that edits display name, avatar symbol and optional avatar photo.
struct ProfileEditorView: View {
    // Shared objects injected from above: Auth (name) and the profile store (avatar data).
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var profileStore: ProfileStore
    // Environment action that closes this sheet.
    @Environment(\.dismiss) private var dismiss
    /// Avatar tile size that grows with the user's Dynamic Type setting (base 56 pt).
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 56
    
    // Draft values. Nothing is persisted until save() runs.
    @State private var displayName = ""
    @State private var selectedSymbol = AvatarSymbols.fallback
    @State private var isSaving = false
    /// The raw selection from PhotosPicker; loadPhoto turns it into processed data.
    @State private var pickerItem: PhotosPickerItem?
    @State private var newPhoto: Data?          // processed JPEG waiting to be saved
    /// True when the user chose to drop the saved photo (or switched to a symbol).
    @State private var removePhoto = false
    @State private var errorMessage: String?
    
    /// Adaptive grid: as many columns as fit, each at least one avatar wide plus padding.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: avatarSize + 8), spacing: 12)]
    }
    
    // NavigationStack inside the sheet so it can show its own toolbar (Cancel / Save).
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
                    // Two-parameter onChange (iOS 17 style): fires whenever the user picks a new item.
                    .onChange(of: pickerItem) { _, item in loadPhoto(item) }
                }
                
                Section("Or pick a symbol") {
                    // LazyVGrid only builds visible cells; fine for a grid of symbols.
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
            // Pre-fill the draft from the current Auth name and the stored avatar symbol.
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
    
    /// Loads the picked photo, shrinks it, and stores it as the pending photo.
    /// - Parameter item: the PhotosPicker selection; nil (cleared selection) does nothing.
    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            // Load the raw bytes, then run the (CPU heavy) processing in a detached task off the main actor.
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
    
    /// One tappable symbol tile. Choosing a symbol also discards any pending or saved photo, since a
    /// profile shows either a photo or a symbol.
    /// - Parameter symbol: the SF Symbol name this tile represents.
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
    
    /// Bridges the optional error string to the Bool the alert modifier needs (setting false clears the message).
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
    
    /// Validates the name then saves name, symbol and photo changes in order. Dismisses on success,
    /// shows an alert on failure. Each step is awaited so a failure stops later steps.
    private func save() {
        let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { errorMessage = "Enter a name."; return }
        guard let userID = authService.user?.uid else { return }
        
        // Task bridges to async work; defer clears the saving flag however the task ends.
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                // Skip the network call when the name did not change.
                if cleaned != authService.user?.displayName {
                    try await authService.updateDisplayName(cleaned)
                }
                // The symbol is always saved, so there is a fallback even when a photo exists.
                try await profileStore.updateAvatar(selectedSymbol, for: userID)
                if let newPhoto {
                    try await profileStore.setAvatarPhoto(newPhoto, for: userID)
                // Only delete when there is actually a saved photo to remove.
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
