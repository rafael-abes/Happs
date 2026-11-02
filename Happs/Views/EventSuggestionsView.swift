//
//  EventSuggestionsView.swift
//  Happs
//
//  Created by Rafa Abes on 10/19/26.
//
import SwiftUI
import Combine

@MainActor
final class EventSuggestionsModel: ObservableObject {
    @Published var searchText = ""
    @Published var category = EventCategory.all
    @Published private(set) var events: [TicketmasterEvent] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service = TicketmasterService()
    private var loadTask: Task<Void, Never>?

    func reload(after delay: Duration = .zero) {
        loadTask?.cancel()
        loadTask = Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            isLoading = true
            errorMessage = nil
            do {
                let found = try await service.events(
                    keyword: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: category,
                    near: LocationService.campusCenter
                )
                guard !Task.isCancelled else { return }
                events = found
                isLoading = false
            } catch is CancellationError {
                return
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

struct EventSuggestionsView: View {
    let onSelect: (HappDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var model = EventSuggestionsModel()

    var body: some View {
        content
            .navigationTitle("Events near campus")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.searchText, prompt: "Search events")
            .onSubmit(of: .search) { model.reload() }
            .onChange(of: model.searchText) { _, _ in model.reload(after: .milliseconds(500)) }
            .onChange(of: model.category) { _, _ in model.reload() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) { categoryMenu }
            }
            .task { model.reload() }
    }

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
        .swipeActions(edge: .trailing) {
            if let url = event.url {
                Button("Tickets", systemImage: "ticket") { openURL(url) }
                    .tint(Color.happsGreenFill)
            }
        }
    }

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

    private func select(_ event: TicketmasterEvent) {
        onSelect(event.asDraft())
        dismiss()
    }
}

private struct EventRow: View {
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
