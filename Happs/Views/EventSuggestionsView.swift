//
//  EventSuggestionsView.swift
//  Happs
//
//  Created by Rafa Abes on 10/19/26.
//
// CODE OVERVIEW
// Lets the person pick a real event from Ticketmaster to pre-fill a new Happ. The file holds
// two layers: EventSuggestionsModel (an ObservableObject that owns search text, category,
// results and the loading/error state) and the SwiftUI views that only render that state.
// Network access is delegated to TicketmasterService; this model just schedules and cancels
// the calls. The chosen event is converted to a HappDraft and returned via the onSelect
// closure, so the caller (the editor) stays in control and nothing is saved here.
//
import SwiftUI
import Combine

/// View model for the event search screen. @MainActor so every @Published change happens on the
/// main thread, which SwiftUI requires, even though the network call suspends in between.
@MainActor
final class EventSuggestionsModel: ObservableObject {
        /// Text in the search field, bound with $model.searchText. Changing it triggers a debounced reload.
    @Published var searchText = ""
        /// Selected category filter (EventCategory.all means no filter).
    @Published var category = EventCategory.all
        /// Current results. private(set) so only this model can change them; views read only.
    @Published private(set) var events: [TicketmasterEvent] = []
        /// True while a request is running; the view uses it to show the spinner.
    @Published private(set) var isLoading = false
        /// Human-readable error from the last failed request, or nil when there is none.
    @Published private(set) var errorMessage: String?

        /// Ticketmaster API client (see TicketmasterService for how requests are built).
    private let service = TicketmasterService()
        /// The request currently in flight, kept so a newer request can cancel it.
    private var loadTask: Task<Void, Never>?

        /// Starts a new search with the current text and category.
        /// - Parameter delay: Wait before searching. Typing uses 500 ms so a request is not sent for
        ///   every keystroke (a simple debounce built from cancel plus sleep).
    func reload(after delay: Duration = .zero) {
                // Cancel the previous task first so an older, slower response cannot overwrite newer results.
        loadTask?.cancel()
                // A Task created in a @MainActor class inherits the main actor, so the property writes below run on the main thread.
        loadTask = Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
                        // If we were cancelled while sleeping (user kept typing), stop before touching state.
            guard !Task.isCancelled else { return }
            isLoading = true
            errorMessage = nil
            do {
                let found = try await service.events(
                    keyword: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: category,
                    near: LocationService.campusCenter
                )
                                // Re-check after the await: the task may have been cancelled while the network call ran.
                guard !Task.isCancelled else { return }
                events = found
                isLoading = false
                        // Cancellation is expected, not an error, so it must not show an error message.
            } catch is CancellationError {
                return
                        // URLSession reports cancellation as URLError.cancelled rather than CancellationError.
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard !Task.isCancelled else { return }
                events = []
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

/// Screen listing Ticketmaster events near campus, with search and a category filter.
/// Calls onSelect with a HappDraft when a row is tapped, then dismisses itself.
struct EventSuggestionsView: View {
        /// Receives the draft built from the tapped event.
    let onSelect: (HappDraft) -> Void

        /// Closes this screen after a selection.
    @Environment(\.dismiss) private var dismiss
        /// Opens a URL in the system browser (used for the Tickets link).
    @Environment(\.openURL) private var openURL
        /// @StateObject because this view creates and owns the model; it survives re-renders of body.
    @StateObject private var model = EventSuggestionsModel()

        /// Search UI: content plus searchable field, filter menu and the triggers that reload results.
    var body: some View {
        content
            .navigationTitle("Events near campus")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.searchText, prompt: "Search events")
            .onSubmit(of: .search) { model.reload() }
                        // Debounced: wait 500 ms after the last keystroke. The two-parameter closure is the iOS 17 onChange form.
            .onChange(of: model.searchText) { _, _ in model.reload(after: .milliseconds(500)) }
            .onChange(of: model.category) { _, _ in model.reload() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) { categoryMenu }
            }
                        // .task runs when the view appears (and is cancelled when it disappears) for the first load.
            .task { model.reload() }
    }

        /// Chooses what to show: spinner, error, empty state or the list. Spinner only shows when there
        /// are no results yet, so a refresh does not blank the list.
    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.events.isEmpty {
            ProgressView("Finding events…")
                .accessibilityLabel("Finding events")
        } else if let message = model.errorMessage {
            ContentUnavailableView {
                Label("Couldn't load events", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { model.reload() }
                    .accessibilityHint("Searches for events again.")
            }
        } else if model.events.isEmpty {
            ContentUnavailableView(
                "No events found",
                systemImage: "ticket",
                description: Text("Try a different search or category.")
            )
        } else {
            eventList
        }
    }

        /// The results list, with the Ticketmaster attribution as the footer.
    private var eventList: some View {
        List {
            Section {
                ForEach(model.events) { event in
                    eventRow(event)
                }
            } footer: {
                Text("Event data from Ticketmaster. Swipe left on an event for its Ticketmaster page.")
            }
        }
    }

        /// One tappable row. Children are ignored and a single custom label is built so VoiceOver reads one stop.
    private func eventRow(_ event: TicketmasterEvent) -> some View {
        Button { select(event) } label: {
            EventRow(event: event)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [event.name, event.venueName, event.dateText].compactMap { $0 }.joined(separator: ", ")
        )
        .accessibilityHint("Double tap to use this event for your Happ.")
        .accessibilityAddTraits(.isButton)
        .accessibilityActions {
            if let url = event.url {
                Button("Open tickets for \(event.name)") { openURL(url) }
            }
        }
                // Swipe is a shortcut for sighted users; the accessibilityActions above give VoiceOver the same action.
        .swipeActions(edge: .trailing) {
            if let url = event.url {
                Button("Tickets", systemImage: "ticket") { openURL(url) }
                    .tint(Color.happsGreenFill)
            }
        }
    }

        /// Toolbar menu with a Picker bound straight to model.category, which triggers the reload via onChange.
    private var categoryMenu: some View {
        Menu {
            Picker("Category", selection: $model.category) {
                ForEach(EventCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
        } label: {
            Label(model.category.rawValue, systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Category")
        .accessibilityValue(model.category.rawValue)
        .accessibilityHint("Choose which kind of event to show.")
    }

        /// Hands the event to the caller as a draft (event.asDraft()) and closes the screen.
    private func select(_ event: TicketmasterEvent) {
        onSelect(event.asDraft())
        dismiss()
    }
}

/// Visual content of one event row: thumbnail, title, venue and date. private because only this file uses it.
private struct EventRow: View {
        /// The event to display.
    let event: TicketmasterEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(event.name)
                    .font(.headline)
                    .lineLimit(2)
                if let venue = event.venueName {
                    Text(venue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(event.dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44, alignment: .leading)
    }

        /// Loads the image from the network with AsyncImage. Until it loads, or if it fails, a placeholder
        /// ticket icon is shown, so layout never shifts or breaks.
    private var thumbnail: some View {
        AsyncImage(url: event.imageURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Color(.tertiarySystemFill)
                    .overlay(Image(systemName: "ticket.fill").foregroundStyle(.secondary))
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }
}

