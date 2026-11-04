//
//  MapPin.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//
// CODE OVERVIEW
// The two annotation views drawn on the map: HappPin (category icon, title and going count) and
// FriendPin (avatar with status ring and name). They are pure views driven by a model and an
// isSelected flag; the parent map owns selection and the tap handling. Category and status are
// drawn with shapes as well as colours, and each pin sets one spoken label built by
// AccessibilityText.
import SwiftUI

/// Map annotation for a Happ: a capsule with icon, title and attendee count, and a small pointer triangle underneath.
struct HappPin: View {
    /// The Happ to draw.
    let happ: Happ
    /// Selected pins are slightly enlarged with a thicker outline.
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: happ.category.symbolName)
                    .font(.caption.bold())
                    .foregroundStyle(.black)
                    .frame(width: 26, height: 26)
                    .background(happ.category.tint, in: Circle())

                VStack(alignment: .leading, spacing: 0) {
                    Text(happ.title)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(happ.participantIDs.count) going")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(.systemBackground), in: Capsule())
            .overlay(Capsule().stroke(happ.category.tint, lineWidth: isSelected ? 3 : 2))
            .shadow(radius: 4, y: 2)

            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundStyle(happ.category.tint)
                .offset(y: -2)
        }
        // anchor .bottom makes the pin grow upwards from its tip, so the tip stays on the coordinate.
        .scaleEffect(isSelected ? 1.15 : 1, anchor: .bottom)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AccessibilityText.happPin(
                title: happ.title,
                category: happ.category.rawValue,
                goingCount: happ.participantIDs.count
            )
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Map annotation for a friend: avatar with a status ring and badge, and the name underneath.
struct FriendPin: View {
    /// The friend to draw.
    let friend: UserProfile
    /// Selected pins are slightly enlarged.
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            AvatarView(
                symbol: friend.avatarSymbol, photo: friend.avatarPhoto,
                size: 38,
                ringColor: friend.status.color,
                badgeSymbol: friend.status.symbolName
            )
            .shadow(radius: 3, y: 1)
            .scaleEffect(isSelected ? 1.2 : 1)
            Text(friend.displayName)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: Capsule())
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AccessibilityText.friendPin(name: friend.displayName, status: friend.status.rawValue)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

