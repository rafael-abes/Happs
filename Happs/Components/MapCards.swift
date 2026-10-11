//
//  MapCards.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//

import SwiftUI

private struct CardCloseButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
                .background(Circle().fill(.background))
        }
        .accessibilityLabel("Close")
        .offset(x: 8, y: -8)
    }
}

struct HappCard: View {
    let happ: Happ
    let currentUserID: String
    let isWorking: Bool
    let onJoinToggle: () -> Void
    let onOpen: () -> Void
    let onClose: () -> Void
    
    private var isHost: Bool {
        happ.creatorID == currentUserID
    }
    
    private var isJoined: Bool {
        happ.containsParticipant(currentUserID)
    }
    
    private var timeText: String {
        if Calendar.current.isDateInToday(happ.startTime) {
            return happ.startTime.formatted(date: .omitted, time: .shortened)
        }
        return happ.startTime.formatted(date: .abbreviated, time: .shortened)
    }
    
    private var buttonTitle: String {
        if isHost { return "Hosting" }
        return isJoined ? "Joined" : "Join"
    }
    
    private var buttonSymbol: String {
        if isHost { return "star.fill" }
        return isJoined ? "checkmark.circle.fill" : "plus.circle"
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            categoryBadge
            VStack(alignment: .leading, spacing: 8) {
                header
                chips
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topTrailing) { CardCloseButton(action: onClose) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
    
    private var categoryBadge: some View {
        Image(systemName: happ.category.symbolName)
            .font(.title3)
            .foregroundStyle(happ.category.tint)
            .frame(width: 48, height: 48)
            .background(happ.category.tint.opacity(0.2), in: Circle())
    }
    
    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(happ.title).font(.headline)
                Text(happ.creatorName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            actionButton
        }
    }
    
    private var chips: some View {
        HStack(spacing: 6) {
            chip(timeText)
            chip(happ.category.rawValue)
            chip(happ.location)
        }
    }
    
    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
    
    /// Hosts open the detail screen instead, so a stray tap can't delete their Happ.
    private var actionButton: some View {
        Button(action: isHost ? onOpen : onJoinToggle) {
            Label(buttonTitle, systemImage: buttonSymbol)
                .font(.subheadline)
                .foregroundStyle(isHost || isJoined ? Color.happsGreen : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }
}

struct FriendCard: View {
    let friend: UserProfile
    let onClose: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            AvatarView(symbol: friend.avatarSymbol, size: 52, ringColor: friend.status.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(friend.displayName).font(.headline)
                Label(friend.status.rawValue, systemImage: "circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(friend.status.color)
            }
            Spacer()
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topTrailing) { CardCloseButton(action: onClose) }
    }
}
