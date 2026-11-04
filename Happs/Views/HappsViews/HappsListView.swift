//
//  HappsListView.swift
//  Happs
//
//  Created by Rafa Abes on 9/21/26.
//

// CODE OVERVIEW
// The Happs tab (View layer). It chooses between three things: a locked screen when the person
// is not on campus (CampusLockedView), the map (HappsMapView), or a searchable list with
// sections for upcoming, recap and ended Happs. All data comes from environment stores
// (HappStore, RecapStore, FriendStore, LocationService), which are ObservableObjects, so the
// view re-renders when they change. Filtering and sorting are computed properties rather than
// stored arrays, so they can never get out of date with the store. A small @State clock (now)
// is advanced by .expiryClock so Happs move to "ended" without user action.
//
import SwiftUI
import FirebaseAuth

/// Root view of the Happs tab.
struct HappsListView: View {
        /// Current user, for the user ID.
    @EnvironmentObject private var authService: AuthService
        /// All visible Happs and the load/error state.
    @EnvironmentObject private var happStore: HappStore
        /// Used to show friends who are online on the locked screen.
    @EnvironmentObject private var friendStore: FriendStore
        /// Reports whether the user is inside the campus boundary (campusAccess).
    @EnvironmentObject private var locationService: LocationService
        /// Recap photo previews and their listeners.
    @EnvironmentObject private var recapStore: RecapStore

        /// Presents the new Happ editor sheet.
    @State private var isPresentingEditor = false
        /// Map or list mode. Starts on the map.
    @State private var showsMap = true
        /// The clock used for "has ended" checks. It is state, not Date() inline, so the UI re-evaluates when the clock is advanced.
    @State private var now = Date()
        /// Text typed in the search field.
    @State private var query = ""

        /// The feature is only unlocked while the person is physically inside the campus area.
    private var isUnlocked: Bool {
        locationService.campusAccess == .inside
    }

        /// uid of the signed-in user, or empty string if none (so comparisons simply fail).
    private var currentUserID: String {
        authService.user?.uid ?? ""
    }

        /// Case-insensitive search across title, location, organiser and category. An empty query matches all.
    private func matchesQuery(_ happ: Happ) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return true }
        return happ.title.lowercased().contains(text)
            || happ.location.lowercased().contains(text)
            || happ.creatorName.lowercased().contains(text)
            || happ.category.rawValue.lowercased().contains(text)
    }

        /// Happs that have not ended and match the search, soonest first.
    private var upcoming: [Happ] {
        happStore.happs
            .filter { !$0.hasEnded(at: now) && matchesQuery($0) }
            .sorted { $0.startTime < $1.startTime }
    }

        /// Ended Happs the current user took part in, most recent first (the "Ended" section).
    private var past: [Happ] {
        happStore.happs
            .filter { $0.hasEnded(at: now) && $0.containsParticipant(currentUserID) && matchesQuery($0) }
            .sorted { $0.effectiveEndTime > $1.effectiveEndTime }
    }

    /// Happs that ended in the last 7 days. At most 12, so at most 12 preview listeners.
    private var recentlyEnded: [Happ] {
        let cutoff = now.addingTimeInterval(-7 * 24 * 3600)
        let recent = happStore.happs
            .filter { $0.hasEnded(at: now) && $0.effectiveEndTime > cutoff }
            .sorted { $0.effectiveEndTime > $1.effectiveEndTime }
        return Array(recent.prefix(12))
    }

        /// IDs of the recently ended Happs, used as the identity that triggers re-observing previews.
    private var recentlyEndedIDs: [String] {
        recentlyEnded.map(\.id)
    }

    /// Recent Happs worth showing: they have photos, or you were there and can still add yours.
    private var recapRows: [Happ] {
        recentlyEnded.filter { happ in
            guard matchesQuery(happ) else { return false }
            let hasPhotos = !(recapStore.visiblePreviews(happ.id)).isEmpty
            let canAdd = happ.containsParticipant(currentUserID)
                && RecapRules.isWindowOpen(endsAt: happ.effectiveEndTime, now: now)
            return hasPhotos || canAdd
        }
    }

        /// Tab body inside its own NavigationStack, with toolbar, editor sheet, error alert and the clock/preview hooks.
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Happs")
                .navigationBarTitleDisplayMode(isUnlocked && showsMap ? .inline : .large)
                .toolbar {
                    if isUnlocked {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(showsMap ? "List" : "Map", systemImage: showsMap ? "list.bullet" : "map") {
                                showsMap.toggle()
                            }
                            .accessibilityLabel(showsMap ? "Show list" : "Show map")
                            .accessibilityHint("Switches between the campus map and the list of Happs.")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Create Happ", systemImage: "plus") { isPresentingEditor = true }
                                .accessibilityHint("Opens a form to make a new Happ.")
                        }
                    }
                }
                .sheet(isPresented: $isPresentingEditor) {
                    NavigationStack { HappEditorView() }
                }
                .alert("Database Error", isPresented: storeErrorIsPresented) {
                    Button("OK", role: .cancel) { happStore.clearError() }
                } message: {
                    Text(happStore.errorMessage ?? "Please try again.")
                }
                                // (assumed behaviour of expiryClock: updates `now` at the given boundary times so Happs flip to ended on their own.)
                .expiryClock($now, boundaries: happStore.happs.clockBoundaries)
                                // initial: true runs it once on appear as well as when the ID list changes; it (re)starts the preview listeners.
                .onChange(of: recentlyEndedIDs, initial: true) { _, ids in
                    recapStore.observePreviews(for: ids)
                }
        }
    }

        /// Picks the screen for the current state: locked, map or list.
    @ViewBuilder
    private var content: some View {
        if !isUnlocked {
            CampusLockedView(
                access: locationService.campusAccess,
                happs: happStore.happs,
                onlineFriends: friendStore.onlineFriends
            )
        } else if showsMap {
            HappsMapView()
        } else {
            happsList
        }
    }

        /// List mode: loading spinner, empty state, or search field plus the results (or a no-results view).
    @ViewBuilder
    private var happsList: some View {
        if happStore.isLoading && happStore.happs.isEmpty {
            ProgressView("Loading happs…")
                .accessibilityLabel("Loading happs")
        } else if happStore.happs.isEmpty {
            ContentUnavailableView(
                "No Happs Yet",
                systemImage: "figure.2.arms.open",
                description: Text("Tap + to create the first one.")
            )
        } else {
            VStack(spacing: 8) {
                VoiceSearchField(text: $query, id: "happs-search", placeholder: "Search Happs")
                    .padding(.horizontal)
                    .padding(.top, 8)
                if upcoming.isEmpty && past.isEmpty && recapRows.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    resultsList
                }
            }
        }
    }

        /// The list with its three sections. Sections with no rows are left out.
    private var resultsList: some View {
        List {
            if !upcoming.isEmpty {
                Section("Now and upcoming") {
                    ForEach(upcoming) { happ in
                        row(happ, isEnded: false)
                    }
                }
            }
            if !recapRows.isEmpty {
                Section("Recaps") {
                    ForEach(recapRows) { happ in
                        recapRow(happ)
                    }
                }
            }
            if !past.isEmpty {
                Section("Ended") {
                    ForEach(past) { happ in
                        row(happ, isEnded: true)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

        /// One navigable Happ row leading to HappDetailView. Only the ID is passed so the detail screen reads live data.
    private func row(_ happ: Happ, isEnded: Bool) -> some View {
        NavigationLink {
            HappDetailView(happID: happ.id)
        } label: {
            HappRow(happ: happ, currentUserID: currentUserID, isEnded: isEnded)
        }
        .accessibilityHint("Opens the details.")
    }

    /// Attendees get a plain row. Everyone else gets the locked, blurred card.
    private func recapRow(_ happ: Happ) -> some View {
        let previews = recapStore.visiblePreviews(happ.id)
        let attended = happ.containsParticipant(currentUserID)
        return NavigationLink {
            RecapTimelineView(happ: happ)
        } label: {
            if attended {
                AttendeeRecapLabel(
                    happ: happ,
                    photoCount: previews.count,
                    canAdd: RecapRules.isWindowOpen(endsAt: happ.effectiveEndTime, now: now)
                )
            } else {
                LockedRecapCard(happ: happ, previews: previews)
            }
        }
        .accessibilityHint("Opens the recap.")
    }

        /// Bool binding derived from the store's optional errorMessage; dismissing the alert clears it in the store.
    private var storeErrorIsPresented: Binding<Bool> {
        Binding(get: { happStore.errorMessage != nil }, set: { if !$0 { happStore.clearError() } })
    }
}

/// Row label for a recap the user attended: photo count plus a prompt to add theirs while the window is open.
private struct AttendeeRecapLabel: View {
        /// The ended Happ.
    let happ: Happ
        /// How many preview photos are visible.
    let photoCount: Int
        /// Whether the recap window is still open for adding photos.
    let canAdd: Bool

        /// Subtitle text with correct singular or plural wording.
    private var subtitle: String {
        let photos = photoCount == 1 ? "1 photo" : "\(photoCount) photos"
        return canAdd ? "\(photos) · Add your recap" : photos
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.title3)
                .foregroundStyle(Color.happsGreenText)
                .frame(width: 40, height: 40)
                .background(Color.happsGreen.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(happ.title).font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Recap for \(happ.title), \(photoCount == 1 ? "1 photo" : "\(photoCount) photos")\(canAdd ? ", you can add yours" : "")"
        )
    }
}

/// Row for a Happ in the main list, showing title, status badge, category, place and time.
private struct HappRow: View {
        /// The Happ to show.
    let happ: Happ
        /// Used to work out whether this user has joined or been invited.
    let currentUserID: String
        /// Whether the Happ has finished; drives the badge.
    let isEnded: Bool

    /// Text, symbol and an accessible colour. The symbol means colour is never the only cue.
    private var badge: (text: String, symbol: String, color: Color)? {
        if isEnded { return ("Ended", "clock", .secondary) }
        if happ.containsParticipant(currentUserID) { return ("Joined", "checkmark", Color.happsGreenText) }
        if happ.isInvited(currentUserID) { return ("Invited", "envelope", .primary) }
        return nil
    }

        /// Combines the pieces into one row. Visual layout is replaced by one spoken label from AccessibilityText.happRow.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(happ.title)
                    .font(.headline)
                if let badge {
                    Label(badge.text, systemImage: badge.symbol)
                        .font(.caption)
                        .foregroundStyle(badge.color)
                }
            }
            Text("\(happ.category.rawValue) · \(happ.location)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(happ.timeRangeText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AccessibilityText.happRow(
                title: happ.title,
                badge: badge?.text,
                category: happ.category.rawValue,
                location: happ.location,
                time: happ.timeRangeText
            )
        )
    }
}
