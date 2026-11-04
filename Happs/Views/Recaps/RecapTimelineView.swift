//
//  RecapTimelineView.swift
//  Happs
//
//  Created by Rafa Abes on 10/27/26.
//
// CODE OVERVIEW
// The Recap screen for one Happ: a shared photo timeline for people who joined it, and a
// locked preview for everyone else. It is a pure SwiftUI view layer (the V in MVC). Data and
// writes go through the EnvironmentObject stores (RecapStore, SafetyStore, FriendStore), so the
// view holds only UI state (@State) and never talks to Firestore itself. Timing rules (is the
// photo window open, max photos) live in RecapRules, a separate type, so they can be tested
// without a view. RecapImageView loads one photo through RecapImageLoader (signed URLs for
// private storage). Reporting reuses ReportSheet; blocking calls SafetyStore.block.
//
import SwiftUI
import FirebaseAuth

/// Shows one private photo. The image is fetched asynchronously from `RecapImageLoader`
/// (a shared loader, assumed to cache), because the storage bucket is private and needs a signed URL.
/// It owns three visual states: loaded, failed and loading.
/// Loads one private photo through a signed URL.
struct RecapImageView: View {
    /// Storage path of the photo; also the identity that restarts the load task when it changes.
    let path: String
    /// What VoiceOver says for the photo. Built from author and caption by the caller.
    var accessibilityDescription = "Photo"

    // Local view state: the decoded image and a failure flag drive which branch of `body` shows.
    @State private var image: UIImage?
    @State private var failed = false

        // ZStack keeps one layout slot while the content swaps between image, error and spinner.
    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(accessibilityDescription)
                    .accessibilityAddTraits(.isImage)
            } else if failed {
                Label("Couldn't load photo", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(height: 120)
            } else {
                ProgressView()
                    .frame(height: 160)
                    .accessibilityLabel("Loading photo")
            }
        }
        .frame(maxWidth: .infinity)
                // `.task(id:)` runs when the view appears and re-runs if `path` changes; SwiftUI cancels it
                // automatically when the view disappears, so no manual cleanup is needed.
        .task(id: path) {
            do {
                image = try await RecapImageLoader.shared.image(for: path)
                failed = false
            } catch {
                failed = true
            }
        }
    }
}

/// The recap page for one Happ. Attendees see the shared timeline and can add photos.
/// Everyone else sees the locked preview.
struct RecapTimelineView: View {
    let happ: Happ

        // Stores arrive by @EnvironmentObject (created once higher up) instead of being passed down,
        // so every screen shares the same instances.
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var recapStore: RecapStore

        // `now` is refreshed by a 30 second loop below so the window state (open/closed) updates live.
    @State private var now = Date()
    @State private var showsAdd = false
        // Photo awaiting delete confirmation; non-nil shows the confirmation dialog.
    @State private var pendingDelete: Recap?
    @EnvironmentObject private var safetyStore: SafetyStore
    @EnvironmentObject private var friendStore: FriendStore
        // Set when the user taps Report; drives the ReportSheet sheet.
        // pendingBlock is the photo author awaiting block confirmation.
    @State private var reportTarget: ReportTarget?
    @State private var pendingBlock: Recap?

        // Derived values (computed, not stored) so they always reflect the latest store data.
        // visibleRecaps and visiblePreviews already exclude blocked people and hidden photos.
    private var userID: String { authService.user?.uid ?? "" }
    private var isAttendee: Bool { happ.containsParticipant(userID) }
    private var endsAt: Date { happ.effectiveEndTime }
    private var windowOpen: Bool { RecapRules.isWindowOpen(endsAt: endsAt, now: now) }
    private var recaps: [Recap] { recapStore.visibleRecaps(happ.id) }
    private var previews: [RecapPreview] { recapStore.visiblePreviews(happ.id) }
    private var myCount: Int { recaps.filter { $0.authorID == userID }.count }
    private var slotsLeft: Int { max(0, RecapRules.maxPhotosPerPerson - myCount) }

        // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if isAttendee {
                    addSection
                    timeline
                } else {
                    LockedRecapCard(happ: happ, previews: previews)
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                    Text("Only people who joined this Happ can see its photos.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .navigationTitle("Recap")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsAdd) {
            AddRecapSheet(happ: happ, slotsLeft: slotsLeft)
        }
                // Delete uses a confirmation dialog because removing a photo cannot be undone.
                // The Binding turns the optional `pendingDelete` into a Bool: shown while non-nil,
                // and cleared when the dialog is dismissed.
        .confirmationDialog(
            "Delete this photo?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { recap in
            Button("Delete Photo", role: .destructive) {
                Task { await recapStore.delete(recap) }
            }
            Button("Keep", role: .cancel) { }
        }
                // `.sheet(item:)` needs an Identifiable value, so the ReportTarget is wrapped in
                // IdentifiedReport (defined at the bottom of this file).
        .sheet(item: Binding(
            get: { reportTarget.map(IdentifiedReport.init) },
            set: { if $0 == nil { reportTarget = nil } }
        )) { item in
            ReportSheet(target: item.target)
        }
                // Block asks for confirmation first because it also ends the friendship (see the message).
        .confirmationDialog(
            "Block this person?",
            isPresented: Binding(get: { pendingBlock != nil }, set: { if !$0 { pendingBlock = nil } }),
            titleVisibility: .visible,
            presenting: pendingBlock
        ) { recap in
            Button("Block \(recap.authorName)", role: .destructive) {
                                // Task bridges from the synchronous button closure into the async store method.
                Task {
                    await safetyStore.block(
                        userID: recap.authorID, name: recap.authorName,
                        currentUserID: userID, friendStore: friendStore
                    )
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: { recap in
            Text("You'll stop seeing \(recap.authorName)'s photos and Happs, and you'll no longer be friends.")
        }
                // The store publishes a single errorMessage; this alert shows it and clears it on dismiss.
        .alert("Something Went Wrong", isPresented: Binding(
            get: { recapStore.errorMessage != nil },
            set: { if !$0 { recapStore.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { recapStore.errorMessage = nil }
        } message: {
            Text(recapStore.errorMessage ?? "Please try again.")
        }
                // Attendees start the recap observation for this Happ; non-attendees only load previews.
                // (Assumed: the store attaches a Firestore listener in observeRecaps, stopped in onDisappear.)
        .task(id: happ.id) {
            if isAttendee {
                recapStore.observeRecaps(happID: happ.id)
            } else {
                recapStore.ensurePreviews(happID: happ.id)
            }
        }
                // Ticks every 30 seconds so `now` changes and the Add button state updates without leaving
                // the screen. The loop ends when the task is cancelled (view disappears).
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
            }
        }
                // Stop the live observation so it does not keep running after leaving the screen.
        .onDisappear { recapStore.stopRecaps(happID: happ.id) }
    }

        /// Title, category and place, and the end time that the recap window is counted from.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(happ.title).font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("\(happ.category.rawValue) at \(happ.location)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(endsAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

        /// The add area has four states, checked in order: Happ not finished, window closed,
        /// photo limit reached, otherwise the Add button. @ViewBuilder lets `if/else` return different views.
    @ViewBuilder
    private var addSection: some View {
        if now < endsAt {
            note("Recaps open when this Happ ends.")
        } else if !windowOpen {
            note("The \(RecapRules.windowHours) hour window to add photos has closed.")
        } else if slotsLeft == 0 {
            note("You've added all \(RecapRules.maxPhotosPerPerson) of your photos.")
        } else {
            Button {
                showsAdd = true
            } label: {
                Label("Add your recap", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.happsGreenFill, in: Capsule())
                    .foregroundStyle(.white)
            }
            .accessibilityHint("\(slotsLeft) \(slotsLeft == 1 ? "photo" : "photos") left to add.")
            Text("\(slotsLeft) \(slotsLeft == 1 ? "photo" : "photos") left. The window closes \(RecapRules.windowCloses(endsAt: endsAt).formatted(date: .abbreviated, time: .shortened)).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

        /// A small rounded grey message box used for the non-actionable states above.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

        /// The list of photo cards, or an empty state when there are none yet.
    @ViewBuilder
    private var timeline: some View {
        Text("Shared timeline").font(.headline)
            .accessibilityAddTraits(.isHeader)
        if recaps.isEmpty {
            ContentUnavailableView(
                "No recaps yet",
                systemImage: "photo.on.rectangle.angled",
                description: Text("Photos from this Happ will show up here.")
            )
        } else {
                        // Array(enumerated()) gives the index so VoiceOver can say "Photo 2 of 5".
            ForEach(Array(recaps.enumerated()), id: \.element.id) { index, recap in
                recapCard(recap, index: index, total: recaps.count)
            }
        }
    }

        /// One photo card: author, relative time, owner or other-user actions, the image and its caption.
        /// - Parameters:
        ///   - index: zero-based position, used for the spoken position.
        ///   - total: number of photos in the timeline.
    private func recapCard(_ recap: Recap, index: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recap.authorName).font(.subheadline.weight(.semibold))
                    Text(recap.createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                                // Owners get Delete; everyone else gets a menu with Report and Block.
                if recap.authorID == userID {
                    Button {
                        pendingDelete = recap
                    } label: {
                        Image(systemName: "trash")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete photo by \(recap.authorName)")
                    .accessibilityHint("Asks you to confirm before it is removed.")
                } else {
                    Menu {
                        Button("Report photo", systemImage: "flag") {
                                                        // Builds the report payload. `safeID` makes the storage path safe to use as an
                                                        // identifier, and hideID lets the reporter also hide the photo locally.
                            reportTarget = ReportTarget(
                                kind: .photo,
                                targetID: ReportTarget.safeID(recap.storagePath),
                                happID: happ.id,
                                offenderID: recap.authorID,
                                offenderName: recap.authorName,
                                summary: recap.caption.isEmpty ? "Photo in \(happ.title)" : recap.caption,
                                hideID: RecapStore.hideID(for: recap)
                            )
                        }
                        Button("Block \(recap.authorName)", systemImage: "hand.raised", role: .destructive) {
                            pendingBlock = recap
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("More options for photo by \(recap.authorName)")
                    .accessibilityHint("Report the photo or block this person.")
                }
            }
            RecapImageView(
                path: recap.storagePath,
                accessibilityDescription: AccessibilityText.photoPosition(index: index + 1, total: total)
                                    // Caption passes through ContentFilter before it is shown or read aloud.
                    + " "
                    + AccessibilityText.recapPhoto(author: recap.authorName, caption: ContentFilter.displayText(recap.caption))
            )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if !recap.caption.isEmpty {
                Text(ContentFilter.displayText(recap.caption)).font(.subheadline)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Lets a ReportTarget drive `.sheet(item:)`.
private struct IdentifiedReport: Identifiable {
    let target: ReportTarget
    var id: String { target.kind.rawValue + target.targetID }
}


