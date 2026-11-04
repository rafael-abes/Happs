//
//  MenuRow.swift
//  Happs
//
//  Created by Rafa Abes on 10/1/26.
//
// CODE OVERVIEW
// A reusable row used in menu-style lists: round icon, title and chevron, inside a Button. The
// parent supplies the icon name, title, optional accessibility hint and the tap closure, so the
// same row works for every menu entry. A Button with .plain style is used so the whole
// rounded card is tappable but the system does not tint the content.
import SwiftUI

/// One tappable menu entry.
struct MenuRow: View {
    /// SF Symbol name for the leading icon.
    let systemImage: String
    /// Visible text, also what VoiceOver reads.
    let title: String
    /// Optional VoiceOver hint; empty means none.
    var hint: String = ""
    /// Tap handler. Defaults to doing nothing so rows without a destination yet can still be drawn.
    var action: () -> Void = {}

    // @ScaledMetric scales this number with the user's Dynamic Type setting, relative to body text.
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 28

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.medium))
                    .frame(width: iconSize, height: iconSize)
                    .background(.quaternary, in: Circle())
                    .accessibilityHidden(true)

                Text(title)
                    .font(.body)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(minHeight: 44)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        // .plain removes the default button tint, so the row keeps its own colours. foregroundStyle(.primary) below keeps text black or white.
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(hint)
    }
}
