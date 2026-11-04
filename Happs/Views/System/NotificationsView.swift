//
//  NotificationsView.swift
//  Happs
//
//  Created by Rafa Abes on 10/11/26.
//

// CODE OVERVIEW
// The notifications inbox, shown as a sheet from the Me tab (ProfileView). It lists notifications
// kept by NotificationStore (a Firestore snapshot listener feeds it, so new items appear live),
// lets the user search them, mark one or all as read, and swipe to delete.
// Each row also has a speaker button (SpeakButton, text to speech) and the search box has a mic
// (VoiceSearchField, speech to text), both from Components/STT_TTS. The filtering is done locally
// on the already loaded array, so no extra Firestore query is needed.
import SwiftUI

/// Inbox sheet listing the user's notifications with search, read and delete actions.
struct NotificationsView: View {
    // Source of notifications and of read and delete operations.
    @EnvironmentObject private var notificationStore: NotificationStore
    // Closes the sheet.
    @Environment(\.dismiss) private var dismiss

    // Search text, also written by voice input.
    @State private var query = ""

    /// Notifications matching the search text in title or body (case insensitive), or all of them when the box is empty.
    private var filtered: [AppNotification] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return notificationStore.notifications }
        return notificationStore.notifications.filter {
            $0.title.lowercased().contains(text) || $0.body.lowercased().contains(text)
        }
    }

    var body: some View {
        // Own NavigationStack because this is presented as a sheet.
        NavigationStack {
            // Group lets the if/else choose between an empty state and the list.
            Group {
                if notificationStore.notifications.isEmpty {
                    ContentUnavailableView(
                        "No Notifications",
                        systemImage: "bell",
                        description: Text("Friend requests, group invites and Happ activity show up here.")
                    )
                } else {
                    VStack(spacing: 8) {
                        VoiceSearchField(text: $query, id: "inbox-search", placeholder: "Search notifications")
                            .padding(.horizontal)
                            .padding(.top, 8)
                        if filtered.isEmpty {
                            ContentUnavailableView.search(text: query)
                        } else {
                            // swipe to delete; allowsFullSwipe lets a long swipe delete straight away.
                            List(filtered) { item in
                                row(item)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            // Store methods are async, so the synchronous button action wraps them in a Task.
                                            Task { await notificationStore.deleteNotification(item) }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityHint("Closes the notifications.")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Mark all read") {
                        Task { await notificationStore.markAllRead() }
                    }
                    .disabled(notificationStore.unreadCount == 0)
                    .accessibilityHint("Marks every notification as read.")
                }
            }
        }
    }

    /// Stable per-row key for the speaker. Works whether the model's id is optional or not.
    private func speakID(for item: AppNotification) -> String {
        "note-\(item.createdAt?.timeIntervalSince1970 ?? 0)-\(item.title)"
    }

    /// The speaker is a sibling of the row button, not inside it, so the two taps never clash.
    private func row(_ item: AppNotification) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Button {
                Task { await notificationStore.markRead(item) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.kind.symbolName)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            item.kind.isNegative ? Color.happsRedFill : Color.happsGreenFill,
                            in: Circle()
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.headline)
                            .fontWeight(item.isRead ? .regular : .bold)
                            .foregroundStyle(.primary)
                        Text(item.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let date = item.createdAt {
                            Text(date.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 4)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                AccessibilityText.notificationRow(
                    isRead: item.isRead,
                    title: item.title,
                    body: item.body,
                    date: item.createdAt
                )
            )
            .accessibilityHint(item.isRead ? "" : "Double tap to mark as read.")
            .accessibilityAddTraits(.isButton)

            // Unread dot and speaker share one line. The dot keeps its space when read,
            // so the speakers stay aligned down the list.
            HStack(spacing: 6) {
                Circle()
                    .fill(item.kind.isNegative ? Color.happsRedFill : Color.happsGreenFill)
                    .frame(width: 10, height: 10)
                    .opacity(item.isRead ? 0 : 1)
                    .accessibilityHidden(true)
                SpeakButton(id: speakID(for: item), text: item.spokenSummary, subject: item.title)
            }
            .frame(minHeight: 44)
        }
    }
}

