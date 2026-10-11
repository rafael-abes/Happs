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
                    List(notificationStore.notifications) { item in
                        row(item)
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
    
    private func row(_ item: AppNotification) -> some View {
        Button {
            Task { await notificationStore.markRead(item) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.kind.symbolName)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.happsGreen, in: Circle())
                
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
                
                if !item.isRead {
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                        .padding(.top, 6)
                }
            }
        }
        .buttonStyle(.plain)
    }
}