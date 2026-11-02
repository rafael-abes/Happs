//
//  AddRecapSheet.swift
//  Happs
//
//  Created by Rafa Abes on 10/27/26.
//


import SwiftUI
import PhotosUI
import FirebaseAuth

/// Pick up to `slotsLeft` photos, add optional captions, post.
struct AddRecapSheet: View {
    let happ: Happ
    let slotsLeft: Int

    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var recapStore: RecapStore
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var drafts: [RecapDraft] = []
    @State private var isLoading = false
    @State private var isPosting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: max(1, slotsLeft),
                        matching: .images
                    ) {
                        Label(drafts.isEmpty ? "Choose photos" : "Change photos", systemImage: "photo.on.rectangle")
                            .frame(minHeight: 44)
                    }
                    .disabled(isPosting)
                    .accessibilityHint("You can add \(slotsLeft) more \(slotsLeft == 1 ? "photo" : "photos").")
                } footer: {
                    Text("You can add \(slotsLeft) more \(slotsLeft == 1 ? "photo" : "photos"). Only people who joined this Happ can see them.")
                }

                if isLoading {
                    Section {
                        ProgressView("Preparing photos...")
                            .accessibilityLabel("Preparing photos")
                    }
                }

                ForEach($drafts) { $draft in
                    let index = drafts.firstIndex { $0.id == draft.id } ?? 0
                    Section {
                        thumbnail(draft, index: index, total: drafts.count)
                        TextField("Add a caption (optional)", text: $draft.caption)
                            .disabled(isPosting)
                            .accessibilityLabel("Caption for photo \(index + 1)")
                            .accessibilityHint("Describe the photo. Screen reader users hear this caption.")
                    }
                }
            }
            .navigationTitle("Add your recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isPosting)
                        .accessibilityHint("Closes without posting.")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isPosting ? "Posting..." : "Post") { post() }
                        .disabled(drafts.isEmpty || isPosting || isLoading)
                        .accessibilityLabel("Post")
                        .accessibilityValue(isPosting ? "Posting" : "")
                        .accessibilityHint("Shares your photos with the people who joined this Happ.")
                }
            }
            .onChange(of: pickerItems) { _, items in
                Task { await load(items) }
            }
            .interactiveDismissDisabled(isPosting)
            .alert("Couldn't Post Recap", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ draft: RecapDraft, index: Int, total: Int) -> some View {
        if let image = UIImage(data: draft.full) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Selected photo \(index + 1) of \(total)")
                .accessibilityAddTraits(.isImage)
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func load(_ items: [PhotosPickerItem]) async {
        isLoading = true
        defer { isLoading = false }
        var result: [RecapDraft] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let prepared = await Task.detached(priority: .userInitiated) {
                ImageProcessor.prepare(data)
            }.value
            if let prepared {
                result.append(RecapDraft(full: prepared.full, preview: prepared.preview))
            }
        }
        drafts = result
    }

    private func post() {
        guard let user = authService.user else {
            errorMessage = "Sign in again before posting."
            return
        }
        isPosting = true
        Task {
            defer { isPosting = false }
            do {
                try await recapStore.post(
                    happID: happ.id,
                    userID: user.uid,
                    authorName: user.displayName ?? user.email ?? "Someone",
                    drafts: drafts
                )
                dismiss()
            } catch {
                errorMessage = RecapError.message(for: error)
            }
        }
    }
}
