//
//  AddRecapSheet.swift
//  Happs
//
//  Created by Rafa Abes on 10/27/26.
//


// CODE OVERVIEW
// Sheet where a participant adds photos to a Happ's recap. The flow is: PhotosPicker selection ->
// each photo is decoded and resized in a background task by ImageProcessor into a full image and a
// small preview (a RecapDraft) -> user adds optional captions -> Post hands the drafts to
// RecapStore, which uploads and writes to Firestore. The view never talks to Firestore or storage
// itself; all of that is in RecapStore. It also passes a RecapAudience so the store knows who to
// notify. Errors from the store come back as a message shown in an alert.
//
import SwiftUI
import PhotosUI
import FirebaseAuth

/// Pick up to `slotsLeft` photos, add optional captions, post.
struct AddRecapSheet: View {
    /// The Happ this recap belongs to.
    let happ: Happ
    /// How many more photos may still be added; caps the picker's selection count.
    let slotsLeft: Int

    // Shared objects injected from above. RecapStore does the uploading.
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var recapStore: RecapStore
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss

    /// Raw PhotosPicker selection. Changing it triggers load(_:).
    @State private var pickerItems: [PhotosPickerItem] = []
    /// Processed photos (full image, preview, caption) ready to post.
    @State private var drafts: [RecapDraft] = []
    /// True while the picked photos are being decoded and resized.
    @State private var isLoading = false
    /// True during the upload; disables editing and swipe-to-dismiss.
    @State private var isPosting = false
    @State private var errorMessage: String?

    // Form with a picker section, an optional progress section, then one section per photo draft.
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(
                        selection: $pickerItems,
                        // max(1, ...) keeps the picker's limit valid (at least 1) even if slotsLeft is 0.
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

                // ForEach over a Binding collection gives each row a binding ($draft) so the caption field can edit the draft in place.
                ForEach($drafts) { $draft in
                    // Position of this draft, used only for the accessibility wording ("photo 2 of 3").
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
                        // Can post only when there is something to post and nothing is still busy.
                        .disabled(drafts.isEmpty || isPosting || isLoading)
                        .accessibilityLabel("Post")
                        .accessibilityValue(isPosting ? "Posting" : "")
                        .accessibilityHint("Shares your photos with the people who joined this Happ.")
                }
            }
            // Whenever the selection changes, reload the drafts from it.
            .onChange(of: pickerItems) { _, items in
                Task { await load(items) }
            }
            // Stops the user swiping the sheet away mid-upload.
            .interactiveDismissDisabled(isPosting)
            .alert("Couldn't Post Recap", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    /// Preview of one selected photo; draws nothing if the data cannot be decoded as an image.
    /// - Parameters:
    ///   - draft: the photo to show (its full-size data).
    ///   - index: zero-based position, used for the accessibility label.
    ///   - total: how many photos are selected.
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

    /// Bridges the optional error string to the alert's Bool (setting false clears the message).
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    /// Converts the picker selection into drafts. Photos that fail to load or process are skipped
    /// silently. Replaces any previous drafts (so captions typed earlier are lost on re-pick).
    /// - Parameter items: the current PhotosPicker selection.
    private func load(_ items: [PhotosPickerItem]) async {
        isLoading = true
        defer { isLoading = false }
        var result: [RecapDraft] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            // Detached task: image decoding and resizing is CPU heavy, so keep it off the main actor.
            let prepared = await Task.detached(priority: .userInitiated) {
                ImageProcessor.prepare(data)
            }.value
            if let prepared {
                result.append(RecapDraft(full: prepared.full, preview: prepared.preview))
            }
        }
        drafts = result
    }

    /// Uploads the drafts through RecapStore, then closes the sheet. Shows an alert on failure.
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
                    // Fallback chain for the stored author name.
                    authorName: user.displayName ?? user.email ?? "Someone",
                    drafts: drafts,
                    // Who to notify: attendees (photos posted) and the poster's friends (see what you missed).
                    notify: RecapAudience(
                        happTitle: happ.title,
                        attendeeIDs: happ.participantIDs,
                        friendIDs: profileStore.profile?.friendIDs ?? []
                    )
                )
                dismiss()
            } catch {
                errorMessage = RecapError.message(for: error)
            }
        }
    }
}

