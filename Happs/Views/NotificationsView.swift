//
//  NotificationsView.swift
//  Happs
//
//  Created by Rafa Abes on 10/11/26.
//

import SwiftUI
 
struct NotificationsView: View {
    @EnvironmentObject private var notificationStore: NotificationStore
    @Environment(\.dismiss) private var dismiss
 
    @State private var query = ""
 
    private var filtered: [AppNotification] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return notificationStore.notifications }
        return notificationStore.notifications.filter {
            $0.title.lowercased().contains(text) || $0.body.lowercased().contains(text)
        }
    }
 
    var body: some View {
        NavigationStack {
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
                            List(filtered) { item in
                                row(item)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
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
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Mark all read") {
                        Task { await notificationStore.markAllRead() }
                    }
                    .disabled(notificationStore.unreadCount == 0)
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
                            item.kind.isNegative ? .red : Color.happsGreen,
                            in: Circle()
                        )
 
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(item.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let date = item.createdAt {
                            Text(date.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
 
                    Spacer(minLength: 4)
                }
            }
            .buttonStyle(.plain)
 
            // Unread dot and speaker share one line. The dot keeps its space when read,
            // so the speakers stay aligned down the list.
            HStack(spacing: 6) {
                Circle()
                    .fill(item.kind.isNegative ? .red : .green)
                    .frame(width: 10, height: 10)
                    .opacity(item.isRead ? 0 : 1)
                SpeakButton(id: speakID(for: item), text: item.spokenSummary)
            }
            .frame(height: 34)
        }
    }
}
