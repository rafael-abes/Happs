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
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Close")
        .accessibilityHint("Closes this card.")
        .offset(x: 16, y: -16)
    }
}

struct HappCard: View {
    let happ: Happ
    let currentUserID: String
    let isWorking: Bool
    let onJoinToggle: () -> Void
    let onOpen: () -> Void
    let onClose: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

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

    private var buttonHint: String {
        if isHost { return "Opens the details of your Happ." }
        return isJoined ? "Double tap to leave this Happ." : "Double tap to join this Happ."
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
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open details", onOpen)
    }

    private var categoryBadge: some View {
        Image(systemName: happ.category.symbolName)
            .font(.title3)
            .foregroundStyle(.primary)
            .frame(width: 48, height: 48)
            .background(happ.category.tint.opacity(0.2), in: Circle())
            .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(happ.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(happ.creatorName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            SpeakButton(id: happ.id, text: happ.spokenSummary, subject: happ.title)
            actionButton
        }
    }

    /// Side by side normally, stacked at accessibility sizes so nothing is cut off.
    private var chips: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 6))
        return layout {
            chip(timeText)
            chip(happ.category.rawValue)
            chip(happ.location)
        }
        .accessibilityElement(children: .combine)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }

    /// Hosts open the detail screen instead, so a stray tap can't delete their Happ.
    private var actionButton: some View {
        Button(action: isHost ? onOpen : onJoinToggle) {
            Label(buttonTitle, systemImage: buttonSymbol)
                .font(.subheadline)
                .foregroundStyle(isHost || isJoined ? Color.happsGreenText : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minHeight: 44)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .accessibilityHint(buttonHint)
    }
}

struct FriendCard: View {
    let friend: UserProfile
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(
                symbol: friend.avatarSymbol, photo: friend.avatarPhoto,
                size: 52,
                ringColor: friend.status.color,
                badgeSymbol: friend.status.symbolName
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(friend.displayName)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    Image(systemName: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(friend.status.color)
                    Text(friend.status.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            SpeakButton(id: friend.id, text: friend.spokenSummary, subject: friend.displayName)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topTrailing) { CardCloseButton(action: onClose) }
        .accessibilityElement(children: .contain)
    }
}
