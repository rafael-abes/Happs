//
//  MapCards.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//


// CODE OVERVIEW
// The cards that slide up over the map when a pin is selected: HappCard (Join, Joined or
// Hosting, plus open and close) and FriendCard. They are "dumb" views: the parent map screen
// owns the data and passes in values and closures (onJoinToggle, onOpen, onClose), so the card
// never talks to Firestore itself. This is the closure-callback pattern, and it keeps the
// views easy to preview and reuse. Both cards also have a SpeakButton for text-to-speech.
import SwiftUI

/// Shared close button for both cards, positioned over the top trailing corner.
private struct CardCloseButton: View {
    /// Called when the button is tapped; supplied by the parent so the card does not decide what closing means.
    let action: () -> Void

    // Order: category badge on the left, title and chips on the right. The whole card is tappable via onTapGesture; contentShape(Rectangle()) makes the empty areas tappable too.
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
        // Nudges the button so it sits on the card's corner. The 44 pt frame keeps the tap area large.
        .offset(x: 16, y: -16)
    }
}

/// Summary card for a selected Happ on the map.
struct HappCard: View {
    /// The Happ being shown.
    let happ: Happ
    /// Signed-in user's ID, used to work out whether they are the host or have joined.
    let currentUserID: String
    /// True while a join or leave request is in flight; the action button is disabled so it cannot be tapped twice.
    let isWorking: Bool
    /// Called to join or leave. Not used when the user is the host.
    let onJoinToggle: () -> Void
    /// Called to open the Happ's detail screen.
    let onOpen: () -> Void
    /// Called to dismiss the card.
    let onClose: () -> Void

    // Read from the environment so the layout can change at accessibility text sizes.
    @Environment(\.dynamicTypeSize) private var typeSize

    /// True when the signed-in user created this Happ.
    private var isHost: Bool {
        happ.creatorID == currentUserID
    }

    /// True when the signed-in user is in the participant list.
    private var isJoined: Bool {
        happ.containsParticipant(currentUserID)
    }

    /// Time only for today's Happs, otherwise date and time, to keep the chip short.
    private var timeText: String {
        if Calendar.current.isDateInToday(happ.startTime) {
            return happ.startTime.formatted(date: .omitted, time: .shortened)
        }
        return happ.startTime.formatted(date: .abbreviated, time: .shortened)
    }

    /// Button text for the user's relationship to the Happ: host, joined or not joined.
    private var buttonTitle: String {
        if isHost { return "Hosting" }
        return isJoined ? "Joined" : "Join"
    }

    /// SF Symbol that matches the button title, so the state is not shown by text colour alone.
    private var buttonSymbol: String {
        if isHost { return "star.fill" }
        return isJoined ? "checkmark.circle.fill" : "plus.circle"
    }

    /// VoiceOver hint describing what a double tap will do in the current state.
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

    /// Round icon showing the category (decorative; the category is also written in a chip).
    private var categoryBadge: some View {
        Image(systemName: happ.category.symbolName)
            .font(.title3)
            .foregroundStyle(.primary)
            .frame(width: 48, height: 48)
            .background(happ.category.tint.opacity(0.2), in: Circle())
            .accessibilityHidden(true)
    }

    /// Title, host name, speaker button and join button in one row.
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
        // AnyLayout lets the code swap HStackLayout for VStackLayout without rebuilding the child views, so their identity and state are kept.
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

    /// One rounded caption chip. At accessibility sizes the line limit is removed so long text wraps.
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
        // A host gets the open action here, not join/leave. See the comment above this property for why.
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

/// Summary card for a selected friend on the map.
struct FriendCard: View {
    /// The friend's profile.
    let friend: UserProfile
    /// Called to dismiss the card.
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
