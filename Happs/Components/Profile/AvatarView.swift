//
//  AvatarView.swift
//  Happs
//
//  Created by Rafa Abes on 10/10/26.
//
// CODE OVERVIEW
// AvatarView is the small reusable circular profile picture used wherever a person is shown
// (friend lists, map pins, profile editor). It is a plain value-type SwiftUI View with no
// state of its own: the caller passes in everything (symbol, photo, ring colour, badge), so the
// same view works for any user. AvatarSymbols is a tiny namespace (a caseless enum) that holds
// the list of SF Symbols a user can pick and their spoken names. Design choice: the picture is
// either a custom JPEG or an SF Symbol, and the symbol is the fallback so the circle is never empty.
import SwiftUI

/// Namespace (caseless enum, so it cannot be instantiated) for the SF Symbol avatars users can choose from.
enum AvatarSymbols {
    /// Symbol used when a user has not chosen one, or when a stored name is not recognised.
    static let fallback = "person.fill"
    /// Every symbol offered by the picture chooser, in display order.
    static let all = [
        "person.fill", "face.smiling.fill", "pawprint.fill", "leaf.fill",
        "flame.fill", "bolt.fill", "star.fill", "heart.fill",
        "moon.fill", "hare.fill", "sportscourt.fill", "music.note"
    ]

    /// What VoiceOver says for each profile picture.
    static let names: [String: String] = [
        "person.fill": "Person",
        "face.smiling.fill": "Smiling face",
        "pawprint.fill": "Paw print",
        "leaf.fill": "Leaf",
        "flame.fill": "Flame",
        "bolt.fill": "Lightning bolt",
        "star.fill": "Star",
        "heart.fill": "Heart",
        "moon.fill": "Moon",
        "hare.fill": "Hare",
        "sportscourt.fill": "Sports court",
        "music.note": "Music note"
    ]

    /// Looks up the spoken name for a symbol. A nil symbol is treated as the fallback, and an
    /// unknown symbol gives the generic "Profile picture" rather than crashing or returning empty.
    static func name(for symbol: String?) -> String {
        names[symbol ?? fallback] ?? "Profile picture"
    }
}

/// Circular avatar: a custom photo if one decodes, otherwise an SF Symbol on a green circle,
/// with an optional coloured status ring and a small status badge in the bottom right corner.
struct AvatarView: View {
    /// SF Symbol name for the symbol avatar. Optional because a profile may not have chosen one yet.
    let symbol: String?
    /// Custom profile picture (JPEG). Falls back to the symbol when nil or undecodable.
    var photo: Data? = nil
    /// Diameter in points. Icon, badge and padding are all derived from this so the view scales as one unit.
    var size: CGFloat = 44
    /// Colour of the status ring (see UserStatus.color). nil draws a clear ring, which keeps the layout the same.
    var ringColor: Color? = nil
    /// Optional SF Symbol drawn in the corner so status is not shown by colour alone.
    var badgeSymbol: String? = nil

    var body: some View {
        // The face is drawn first, then the ring and badge are layered on top with overlays
        // so they never change the size of the avatar.
        face
            .overlay(Circle().stroke(ringColor ?? Color.clear, lineWidth: 3))
            .overlay(alignment: .bottomTrailing) { badge }
            .accessibilityHidden(true)
    }

    /// The picture itself. @ViewBuilder lets the if/else return two different view types.
    @ViewBuilder
    private var face: some View {
        // UIImage(data:) returns nil for corrupt data, so a bad photo drops to the symbol branch.
        if let photo, let image = UIImage(data: photo) {
            Image(uiImage: image)
                .resizable()
                // scaledToFill + fixed frame + clipShape crops non-square photos to a neat circle.
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Image(systemName: symbol ?? AvatarSymbols.fallback)
                // Icon size is a fraction of the circle so it looks the same at any avatar size.
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.happsGreenFill, in: Circle())
        }
    }

    /// Optional status badge. Draws nothing when badgeSymbol is nil.
    @ViewBuilder
    private var badge: some View {
        if let badgeSymbol {
            Image(systemName: badgeSymbol)
                .font(.system(size: size * 0.24, weight: .bold))
                .foregroundStyle(.primary)
                .padding(size * 0.09)
                .background(Color(.systemBackground), in: Circle())
                .overlay(Circle().stroke(ringColor ?? Color.clear, lineWidth: 1.5))
                // Nudges the badge slightly past the corner so it sits on the circle edge.
                .offset(x: size * 0.06, y: size * 0.06)
        }
    }
}
